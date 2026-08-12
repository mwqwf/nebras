/**
 * metadataRegister.js — يكتب مرآة Firestore لعنصر IA **بدون رفع أيّ بايت
 * إلى Firebase Storage**. هذا قلب معماريّة "Metadata-only + Proxy".
 *
 * ╔══════════════════════════════════════════════════════════════════╗
 * ║  بديل adminUploader.js (الذي كان يُنزّل الملفّ ويرفعه لـ Storage).  ║
 * ║                                                                  ║
 * ║   • الحقول العامّة (sourceUrl/file_url/audio_url/video_url) تشير   ║
 * ║     إلى رابط Proxy داخليّ:  {base}/api/proxy/ia/{fileId}.{ext}    ║
 * ║   • thumbnail يشير إلى:     {base}/api/proxy/ia/{fileId}?t=thumb  ║
 * ║   • الرابط الحقيقيّ لـ archive.org يُحفظ في __iaFileUrl/__iaThumbUrl║
 * ║     (لا يقرأها التطبيق — يقرأها مسار الـ proxy فقط server-side).   ║
 * ║                                                                  ║
 * ║  📵 التطبيق يرفض أيّ رابط فيه "archive.org" (content_model.dart    ║
 * ║  → _rejectArchiveOrg)، لذا رابط الـ proxy إلزاميّ لظهور العنصر.   ║
 * ╚══════════════════════════════════════════════════════════════════╝
 */

import { adminFsWriteFileMirrorBoth } from '$lib/server/nebrasUnifiedFirestoreAdmin.js';
import { stripUndefinedDeep } from '$lib/nebrasUnifiedSanitize.js';
import {
	buildMobileCompatibleFields,
	generateNebrasFileId
} from '$lib/nebrasMobileUploadSchema.js';
import { getPublicBaseUrl } from '$lib/server/publicBaseUrl.js';
import { extractExtension } from './playabilityFilter.js';

/** الامتداد المُفضَّل لرابط الـ proxy حسب النوع (يساعد مشغّلات التطبيق). */
const FALLBACK_EXT = Object.freeze({ document: '.pdf', audio: '.mp3', video: '.mp4' });

function toNebrasContentType(nebrasType) {
	if (nebrasType === 'audio') return 'audio';
	if (nebrasType === 'video') return 'video';
	return 'document';
}

function proxyExtension(filename, nebrasContentType) {
	const ext = extractExtension(filename);
	return ext || FALLBACK_EXT[nebrasContentType] || '';
}

/**
 * يكتب سجلَّيْن متطابقَيْن (content_unified_files + dashboard_uploads) عبر
 * adminFsWriteFileMirrorBoth، بنفس schema الرفع اليدوي، لكن بروابط proxy.
 *
 * @param {Object} args
 * @param {string} args.iaFileUrl   رابط التنزيل المباشر من archive.org.
 * @param {string|null} [args.iaThumbUrl] رابط صورة الغلاف من archive.org.
 * @param {string} args.contentType  MIME المستنبط (application/pdf، …).
 * @param {number} args.size         الحجم بالبايت (من probe).
 * @param {string} args.filename     اسم الملفّ الأصليّ في IA.
 * @param {'document'|'audio'|'video'} args.nebrasContentType
 * @param {Object} args.metadata     { title, description, author, subsection, main_section, … }
 * @param {Object} args.uploader     { uid, email }
 * @param {Object} [args.iaInfo]     { identifier, iaSourceUrl, license, collection, licenseTier }
 * @returns {Promise<{ fileId: string, proxyUrl: string, thumbnailUrl: string|null, size: number }>}
 */
export async function adminRegisterIaMetadata(args) {
	const {
		iaFileUrl,
		iaThumbUrl,
		contentType,
		size,
		filename,
		nebrasContentType,
		metadata,
		uploader,
		iaInfo
	} = args;

	if (!iaFileUrl || !/^https:\/\//i.test(String(iaFileUrl))) {
		throw Object.assign(new Error('iaFileUrl غير صالح.'), {
			reason: 'invalid_ia_file_url',
			status: 400
		});
	}
	if (!metadata?.title) {
		throw Object.assign(new Error('metadata.title مطلوب.'), {
			reason: 'metadata_title_required',
			status: 400
		});
	}
	if (!metadata?.subsection) {
		throw Object.assign(new Error('metadata.subsection مطلوب (الهيكلية الذهبيّة).'), {
			reason: 'metadata_subsection_required',
			status: 400
		});
	}

	const fileId = generateNebrasFileId();
	const base = getPublicBaseUrl();
	const ext = proxyExtension(filename, nebrasContentType);
	// رابط الـ proxy العامّ — لا يحوي "archive.org" فيمرّ حارس التطبيق.
	const proxyUrl = `${base}/api/proxy/ia/${fileId}${ext}`;
	const thumbnailProxyUrl = iaThumbUrl ? `${base}/api/proxy/ia/${fileId}?t=thumb` : null;

	const finalContentType = contentType || 'application/octet-stream';
	const now = Date.now();
	const createdAtIso = new Date(now).toISOString();
	const finalMetadata = {
		...metadata,
		id: fileId,
		thumbnail: thumbnailProxyUrl || metadata.thumbnail || null,
		content_type: toNebrasContentType(nebrasContentType),
		is_listed: metadata.is_listed ?? true,
		created_at: createdAtIso
	};

	// يملأ sourceUrl/source_url/file_url (+audio_url/video_url) بـ proxyUrl.
	const compatible = buildMobileCompatibleFields(finalMetadata, proxyUrl);

	const payload = stripUndefinedDeep({
		fileId,
		id: fileId,
		downloadUrl: proxyUrl,
		filename,
		fileType: finalContentType,
		fileSize: Number(size) || 0,
		metadata: finalMetadata,
		// لا storagePath — لا شيء على Storage.
		// ⚠️ createdAt = millis رقميّة لا serverTimestamp(): الـ sentinel
		// يمرّ على stripUndefinedDeep مرّتين فيتحوّل إلى {} ويُكسر الترتيب
		// الزمنيّ في التطبيق (compareContentOldestFirst يعتمد createdAt).
		// التطبيق يقبل num millis في _parseDate. القيمة حقيقيّة وقابلة للفرز.
		createdAt: now,

		// علامات داخليّة — لا يقرأها التطبيق (ولا تكسر schema).
		__provider: 'internet_archive',
		__delivery: 'proxy_stream', // ⇐ يميّز عناصر metadata-only عن رفع Storage القديم
		__iaIdentifier: String(iaInfo?.identifier || ''),
		__iaSourceUrl: String(iaInfo?.iaSourceUrl || ''),
		__iaFileUrl: String(iaFileUrl), // ⇐ المصدر الحقيقيّ — يقرأه الـ proxy فقط
		__iaThumbUrl: iaThumbUrl ? String(iaThumbUrl) : '',
		__iaLicense: String(iaInfo?.license || ''),
		__iaCollection: String(iaInfo?.collection || ''),
		__iaImportedAt: createdAtIso,
		__iaOriginalFilename: String(filename || ''),

		// ────────── ⚖️ Google Play / DMCA compliance metadata ──────────
		__license_status:
			iaInfo?.licenseTier === 'community_collection'
				? 'community_collection'
				: iaInfo?.license
					? 'verified_open_license'
					: 'unknown',
		__license_url: String(iaInfo?.license || ''),
		__license_collection: String(iaInfo?.collection || ''),
		__attribution_url: String(iaInfo?.iaSourceUrl || ''),
		__source_provider: 'archive.org',
		__compliance_version: '2026.05',
		__verified_at: createdAtIso,

		created_at: createdAtIso,
		...compatible
	});

	await adminFsWriteFileMirrorBoth(fileId, payload);

	return { fileId, proxyUrl, thumbnailUrl: thumbnailProxyUrl, size: Number(size) || 0 };
}
