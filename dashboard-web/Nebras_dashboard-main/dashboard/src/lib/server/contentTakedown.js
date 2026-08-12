/**
 * حذف محتوًى مخالف من كلّ المواضع — مصدر واحد لمنطق الإزالة يستخدمه:
 *   • واجهة بلاغات المحتوى   (/api/admin/reports)
 *   • أداة تدقيق المحتوى      (/api/admin/content-audit)
 *
 * يحذف من: content_unified_files + dashboard_uploads + ملفّ Storage المرتبط
 * (PDF/صوت/فيديو) + الصور المصغّرة، إن وُجدت.
 *
 * ويشمل منشورات المجتمع (ugc_contents): وثيقة المنشور + تعليقاتها الفرعية
 * + ملفّ Storage وصورته المصغّرة في مجلد الناشر — تُميَّز بمعرّف يبدأ بـ `ugc_` أو
 * contentType == 'ugc'. قبل هذه الإضافة كان حذف بلاغ على منشور مجتمعيّ
 * يُعلّم البلاغ "محذوفاً" بينما المنشور يبقى حيّاً.
 *
 * ⚠️ ميزة يوتيوب أُزيلت بالكامل من اللوحة (لا إنشاء/تعديل). نُبقي هنا حذفاً
 * أفضل-جهد لأيّ وثيقة قديمة في content_unified_youtube حتى يمكن تطهير السجلّات
 * المتبقّية من قبل هذه الإزالة. هذا مسار تنظيف فقط، لا يُنشئ أيّ محتوى جديد.
 */
import {
	getNebrasFirestoreAdmin,
	getNebrasAdminApp
} from '$lib/server/firebaseAdmin.js';
import { getStorage } from 'firebase-admin/storage';
import { adminFsDeleteFileMirrorBoth } from '$lib/server/nebrasUnifiedFirestoreAdmin.js';
import {
	NEBRAS_FS_CONTENT_FILES,
	NEBRAS_FS_CONTENT_YOUTUBE
} from '$lib/firebase/nebrasUnifiedPaths.js';
import { writeAuditEntry } from '$lib/server/auditLog.js';
import { recordFailure as recordHindawiFailure } from '$lib/server/hindawi/registry.js';

/**
 * @param {string} contentId
 * @param {string} [contentType] 'youtube' أو غيره
 */
export async function deleteContentEverywhere(contentId, contentType = '') {
	const id = String(contentId || '').trim();
	if (!id) return;
	const fs = getNebrasFirestoreAdmin();
	const isYouTube = String(contentType || '').toLowerCase() === 'youtube';

	if (isYouTube) {
		await fs.collection(NEBRAS_FS_CONTENT_YOUTUBE).doc(id).delete().catch(() => {});
		await writeAuditEntry({
			action: 'delete',
			provider: 'youtube_legacy',
			contentId: id,
			contentType: 'youtube',
			result: 'ok',
			reason: 'takedown_cleanup'
		});
		return;
	}

	// ─── منشورات المجتمع (ugc_contents) ────────────────────────────
	// معرّفات المجتمع تبدأ بـ ugc_ (UgcService.publish في تطبيق الجوال).
	const isUgc =
		id.startsWith('ugc_') || String(contentType || '').toLowerCase() === 'ugc';
	if (isUgc) {
		const ugcRef = fs.collection('ugc_contents').doc(id);
		let ugcStoragePath = '';
		let ugcChannelId = '';
		try {
			const snap = await ugcRef.get();
			if (snap.exists) {
				const d = snap.data() || {};
				ugcStoragePath = String(d.storage_path || '');
				ugcChannelId = String(d.channelId || '');
			}
		} catch {
			/* ignore */
		}

		// Firestore لا يحذف subcollections تعاقبياً: ننظّف التعليقات
		// والتفاعلات قبل وثيقة المنشور.
		for (const childCollection of ['comments', 'reactions']) {
			try {
				const children = await ugcRef.collection(childCollection).listDocuments();
				while (children.length) {
					const batch = fs.batch();
					for (const ref of children.splice(0, 400)) batch.delete(ref);
					await batch.commit();
				}
			} catch (err) {
				console.warn(
					`[takedown] ugc ${childCollection} delete failed:`,
					err?.message || String(err)
				);
			}
		}

		await ugcRef.delete().catch(() => {});

		if (ugcStoragePath) {
			try {
				const bucket = getStorage(getNebrasAdminApp()).bucket();
				const folder = ugcStoragePath.split('/').slice(0, -1).join('/');
				const [files] = await bucket.getFiles({ prefix: `${folder}/` });
				for (const file of files) {
					await file.delete({ ignoreNotFound: true }).catch(() => {});
				}
			} catch (err) {
				console.warn('[takedown] ugc storage delete failed:', err?.message || String(err));
			}
		}

		await writeAuditEntry({
			action: 'delete',
			provider: 'ugc',
			contentId: id,
			contentType: 'ugc',
			result: 'ok',
			reason: 'takedown',
			meta: { storagePath: ugcStoragePath, channelId: ugcChannelId }
		});
		return;
	}

	// نقرأ storagePath قبل الحذف لإزالة الملفّ الفعليّ.
	let storagePath = '';
	let providerSnap = '';
	let licenseStatusSnap = '';
	let sourceBookIdSnap = '';
	try {
		const snap = await fs.collection(NEBRAS_FS_CONTENT_FILES).doc(id).get();
		if (snap.exists) {
			const d = snap.data() || {};
			storagePath = String(d.storagePath || '');
			providerSnap = String(d.__provider || d.__source_provider || '');
			licenseStatusSnap = String(d.__license_status || '');
			sourceBookIdSnap = String(d.__sourceBookId || d.__hindawiId || '');
		}
	} catch {
		/* ignore */
	}

	await adminFsDeleteFileMirrorBoth(id).catch(() => {});
	// احتياطاً: احذف وثيقة YouTube بنفس المعرّف إن كان النوع غير دقيق.
	await fs.collection(NEBRAS_FS_CONTENT_YOUTUBE).doc(id).delete().catch(() => {});

	if (storagePath) {
		try {
			const bucket = getStorage(getNebrasAdminApp()).bucket();
			await bucket.file(storagePath).delete({ ignoreNotFound: true });
			const folder = storagePath.split('/').slice(0, -1).join('/');
			const [files] = await bucket.getFiles({ prefix: `${folder}/thumbnail_` });
			for (const f of files) {
				await f.delete({ ignoreNotFound: true }).catch(() => {});
			}
		} catch (err) {
			console.warn('[takedown] storage delete failed:', err?.message || String(err));
		}
	}

	// 🛡️ منع إعادة الجلب بعد الإزالة: نسجّل كتاب هنداوي في قائمة الفشل الدائم
	// (permanent=true) كي لا يعيد المحرّك استيراده في الدورة التالية — مطابق
	// لما يفعله مسار DMCA لأرشيف الإنترنت (ia_library_dmca_blacklist).
	// (مكتبة نور موقوفة بمفتاح صارم فلا حاجة لقائمة منع لها حالياً.)
	if (sourceBookIdSnap && providerSnap.toLowerCase().includes('hindawi')) {
		try {
			await recordHindawiFailure(sourceBookIdSnap, {
				reason: 'takedown',
				message: 'removed by report/audit/DMCA',
				permanent: true
			});
		} catch (err) {
			console.warn('[takedown] hindawi blacklist write failed:', err?.message || String(err));
		}
	}

	// سجلّ التدقيق: نُثبت أنّ المحتوى حُذف فعلاً بعد بلاغ/تدقيق/DMCA.
	await writeAuditEntry({
		action: 'delete',
		provider: providerSnap || 'unknown',
		contentId: id,
		contentType: contentType || 'document',
		licenseStatus: licenseStatusSnap,
		result: 'ok',
		reason: 'takedown',
		meta: { storagePath }
	});
}
