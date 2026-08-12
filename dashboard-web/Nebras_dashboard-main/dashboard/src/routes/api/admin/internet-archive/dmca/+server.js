/**
 * POST /api/admin/internet-archive/dmca
 *
 * ╔══════════════════════════════════════════════════════════════════╗
 * ║  Google Play / DMCA Compliance Endpoint                          ║
 * ║                                                                  ║
 * ║  يحذف وثيقة محتوى بناءً على شكوى حقوق طبع. يحذف:                  ║
 * ║   • Firestore: من content_unified_files + dashboard_uploads      ║
 * ║   • Storage:   ملف PDF/MP3/MP4 + thumbnail                       ║
 * ║   • Registry:  يضيف العنصر إلى blacklist لمنع إعادة استيراده      ║
 * ║                                                                  ║
 * ║  body: { fileId: string, reason?: string, reporter?: string }    ║
 * ╚══════════════════════════════════════════════════════════════════╝
 */
import { json } from '@sveltejs/kit';
import {
	getAdminDatabase,
	getNebrasFirestoreAdmin,
	isAdminConfigured
} from '$lib/server/firebaseAdmin.js';
import { getStorage } from 'firebase-admin/storage';
import { getNebrasAdminApp } from '$lib/server/firebaseAdmin.js';
import { adminFsDeleteFileMirrorBoth } from '$lib/server/nebrasUnifiedFirestoreAdmin.js';
import { requireAdminRole } from '$lib/server/adminApiAuth.js';

/** @type {import('@sveltejs/kit').RequestHandler} */
export async function POST(event) {
	const gate = requireAdminRole(event);
	if (!gate.ok) return gate.response;
	if (!isAdminConfigured()) {
		return json({ error: 'not_configured' }, { status: 501 });
	}

	let body;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'invalid_body' }, { status: 400 });
	}

	const fileId = String(body?.fileId || '').trim();
	const reason = String(body?.reason || 'dmca_request').slice(0, 200);
	const reporter = String(body?.reporter || 'unknown').slice(0, 200);
	if (!fileId) {
		return json({ error: 'file_id_required' }, { status: 400 });
	}

	const fs = getNebrasFirestoreAdmin();
	const db = getAdminDatabase();

	// 1) اقرأ الوثيقة لاكتشاف __iaIdentifier (لمنع إعادة استيراد نفس العنصر)
	let iaIdentifier = '';
	let storagePath = '';
	try {
		const snap = await fs.collection('content_unified_files').doc(fileId).get();
		if (snap.exists) {
			const data = snap.data() || {};
			iaIdentifier = String(data?.__iaIdentifier || '');
			storagePath = String(data?.storagePath || '');
		}
	} catch {
		/* doc may not exist; continue */
	}

	// 2) احذف الوثيقتين من Firestore
	await adminFsDeleteFileMirrorBoth(fileId).catch(() => {});

	// 3) احذف الملف من Storage إن وُجد
	if (storagePath) {
		try {
			const bucket = getStorage(getNebrasAdminApp()).bucket();
			await bucket.file(storagePath).delete({ ignoreNotFound: true });
			// احذف ملفّ الـ thumbnail أيضاً (يبدأ بـ thumbnail_)
			const folder = storagePath.split('/').slice(0, -1).join('/');
			const [files] = await bucket.getFiles({ prefix: `${folder}/thumbnail_` });
			for (const f of files) {
				await f.delete({ ignoreNotFound: true }).catch(() => {});
			}
		} catch (err) {
			console.warn('[dmca] storage delete failed:', err?.message || String(err));
		}
	}

	// 4) أضف الـ identifier إلى blacklist لمنع إعادة الاستيراد
	if (iaIdentifier) {
		await db.ref(`ia_library_dmca_blacklist/${iaIdentifier}`).set({
			fileId,
			reason,
			reporter,
			deletedAt: Date.now()
		}).catch(() => {});

		// كذلك ضع علامة "permanent failure" في registry حتى لا يحاول المحرّك تكراره
		await db.ref(`ia_library_failures/${iaIdentifier}`).set({
			reason: 'dmca_takedown',
			message: `Removed by DMCA: ${reason}`,
			permanent: true,
			deletedAt: Date.now()
		}).catch(() => {});
	}

	// 5) سجلّ ضمن audit log (مطلوب لـ Google Play)
	await db.ref('ia_library_engine/log').push({
		level: 'warn',
		message: `DMCA takedown: ${fileId} (IA: ${iaIdentifier || 'unknown'})`,
		reason: 'dmca_takedown',
		fileId,
		iaIdentifier,
		reporter,
		ts: Date.now()
	}).catch(() => {});

	return json({
		ok: true,
		fileId,
		iaIdentifier,
		blacklisted: Boolean(iaIdentifier),
		deletedAt: new Date().toISOString()
	});
}

/**
 * GET — يعرض قائمة العناصر المحجوبة بـ DMCA (للمراجعة).
 */
export async function GET(event) {
	const gate = requireAdminRole(event);
	if (!gate.ok) return gate.response;
	if (!isAdminConfigured()) {
		return json({ error: 'not_configured' }, { status: 501 });
	}

	const db = getAdminDatabase();
	const snap = await db.ref('ia_library_dmca_blacklist').get();
	if (!snap.exists()) return json({ ok: true, count: 0, items: [] });

	const items = Object.entries(snap.val() || {}).map(([id, v]) => ({
		iaIdentifier: id,
		...(v || {})
	}));
	return json({ ok: true, count: items.length, items });
}
