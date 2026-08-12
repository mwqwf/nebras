/**
 * adminUploader.js — رفع buffer إلى Firebase Storage Admin ثمّ كتابة
 * السجلّ في Realtime Database بنفس **شكل البيانات** الذي يكتبه
 * `src/lib/firebase/storageUpload.js` تماماً.
 *
 * ╔══════════════════════════════════════════════════════════════════╗
 * ║  🔒 عـزل صـارم — Nebras Only (Target Isolation)                ║
 * ╠══════════════════════════════════════════════════════════════════╣
 * ║  هذا الملفّ يتعامل **حصراً** مع مشروع نبراس (`nebras-9118c`):    ║
 * ║   • Storage      → bucket nebras-9118c (عبر getNebrasAdminApp)   ║
 * ║   • RTDB        → nebras-9118c-default-rtdb (عبر getAdminDatabase)║
 * ║                                                                  ║
 * ║  ❌ لا يستورد ولا يستدعي أبداً:                                  ║
 * ║    - getMshcatAdminApp / getMshcatFirestoreAdmin                 ║
 * ║    - getOldAppAdminApp / getOldAppFirestoreAdmin                 ║
 * ║    - mshcatServiceAccount.json / oldappServiceAccount.json       ║
 * ║    - متغيّرات MSHCAT_* / OLDAPP_*                                  ║
 * ║                                                                  ║
 * ║  بفضل التهيئة الكسولة (Lazy init) في firebaseAdmin.js، استدعاء   ║
 * ║  getNebrasAdminApp() لا يلمس مشاريع mshcat/oldapp إطلاقاً، حتى     ║
 * ║  لو كانت ملفّاتها مفقودة. السكريبت يعمل بنجاح تامّ بمفتاح        ║
 * ║  Nebras وحده.                                                    ║
 * ║                                                                  ║
 * ║  ⚠️ لا يجوز إضافة أيّ استيراد لـ Mshcat/OldApp في هذا الملفّ.    ║
 * ╚══════════════════════════════════════════════════════════════════╝
 *
 * لماذا تكرار شكل البيانات؟ لأنّ ملفّات الطبقات الخمس ممنوع تعديلها
 * (قيد المهمّة). فبدل استدعاء storageUpload.js (الذي يحتاج File من
 * المتصفّح + Web SDK)، نُعيد بناء **نفس البنية** عبر Admin SDK لكي
 * يبقى تطبيق الموبايل يقرأ المحتوى الجديد بنفس الحقول.
 *
 * نقاط التطابق مع storageUpload.js:
 *   • مسار Storage: dashboard/noor-library/{fileId}/{ts}_{safeName}
 *     (بادئة "noor-library/" للتمييز ولقواعد Storage المخصّصة)
 *   • Download URL مع firebaseStorageDownloadTokens (UUID) → يعمل كرابط
 *     عام بدون قواعد قراءة عمومية على الـ object نفسه.
 *   • RTDB: نكتب dashboard_uploads/{fileId} **و** content_unified/files/{fileId}
 *     في عمليّة واحدة (multi-path update) لضمان ظهور المحتوى في كلّ مكان.
 *   • نُضمِّن نفس compatibleFields التي يبنيها storageUpload.js
 *     (sourceUrl/source_url/file_url/audio_url/video_url حسب content_type).
 */

import { randomUUID } from 'node:crypto';
import { getStorage } from 'firebase-admin/storage';
// ⚠️ لا تستورد من firebaseAdmin.js إلا ما يخصّ Nebras. استيراد أيّ من
//    getMshcatAdminApp / getOldAppAdminApp هنا يكسر العزل (Target Isolation).
import { FieldValue } from 'firebase-admin/firestore';
import { getNebrasAdminApp } from '$lib/server/firebaseAdmin.js';
import { adminFsWriteFileMirrorBoth } from '$lib/server/nebrasUnifiedFirestoreAdmin.js';
import { stripUndefinedDeep } from '$lib/nebrasUnifiedSanitize.js';

// معرّف مشروع Nebras المُتوقَّع. أيّ تطبيق Admin يخالفه → نرفض الرفع
// (defense in depth ضدّ تسرّب الإعدادات بين البيئات).
const NEBRAS_PROJECT_ID = 'nebras-9118c';

/**
 * يتحقّق أنّ التطبيق المُستلم فعلاً يخصّ مشروع Nebras (وليس Mshcat/OldApp
 * عن طريق الخطأ). يُفعّل قاعدة "Target Isolation" وقت التشغيل.
 *
 * @param {import('firebase-admin/app').App} app
 */
function assertNebrasApp(app) {
	const projectId = app?.options?.projectId || '';
	if (projectId !== NEBRAS_PROJECT_ID) {
		throw Object.assign(
			new Error(
				`عُزل صارم انتُهك: سكريبت Noor Library يجب أن يستخدم Nebras (${NEBRAS_PROJECT_ID}) فقط، ` +
					`لكنّه تلقّى تطبيقاً لمشروع "${projectId}".`
			),
			{ reason: 'target_isolation_violated', status: 500 }
		);
	}
}

function sanitizeSegment(name) {
	return String(name || 'file')
		.trim()
		.replace(/[\u0000-\u001F\u007F]/g, '')
		.replace(/[#$\[\]./\\:*?"<>|]+/g, '_')
		.slice(0, 180) || 'file';
}

function buildDownloadUrl(bucketName, objectPath, token) {
	const encoded = encodeURIComponent(objectPath);
	return `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encoded}?alt=media&token=${token}`;
}

function inferContentTypeFromMime(mime, fallback = 'document') {
	const m = String(mime || '').toLowerCase();
	if (m.startsWith('video/')) return 'video';
	if (m.startsWith('audio/')) return 'audio';
	if (m === 'application/pdf' || m.startsWith('application/epub')) return 'document';
	return fallback;
}

/**
 * يُكرِّر منطق `buildMobileCompatibleFields` من storageUpload.js حرفيّاً.
 * نسخ مقصود (لا استيراد) لأنّ تلك الدالّة ليست exported وممنوع تعديل الملفّ.
 */
function buildMobileCompatibleFields(metadata, downloadUrl) {
	const normalized = metadata && typeof metadata === 'object' ? metadata : {};
	const contentType = String(normalized.content_type || 'document').trim().toLowerCase() || 'document';
	const sourceFields = {
		sourceUrl: downloadUrl,
		source_url: downloadUrl,
		file_url: downloadUrl
	};
	if (contentType === 'audio') sourceFields.audio_url = downloadUrl;
	if (contentType === 'video') sourceFields.video_url = downloadUrl;
	return {
		id: normalized.id || undefined,
		title: normalized.title || undefined,
		description: normalized.description || undefined,
		author: normalized.author || undefined,
		thumbnail: normalized.thumbnail || undefined,
		content_type: normalized.content_type || undefined,
		subsection: normalized.subsection,
		subsection_name: normalized.subsection_name || normalized.subsection_title || undefined,
		secondary_subsection: normalized.secondary_subsection,
		secondary_subsection_name:
			normalized.secondary_subsection_name || normalized.secondary_subsection_title || undefined,
		main_section: normalized.main_section,
		main_section_id: normalized.main_section_id,
		main_section_name: normalized.main_section_name,
		...sourceFields
	};
}

/**
 * ينزّل thumbnail خارجيّاً (من URL مكتبة نور مثلاً) ويرفعه إلى Nebras Storage.
 *
 * @param {string} thumbnailUrl
 * @param {string} fileId
 * @param {{ adminApp: import('firebase-admin/app').App, bucketName: string, uploaderUid: string }} ctx
 * @returns {Promise<string|null>} download URL على Firebase Storage (أو null عند الفشل)
 */
async function uploadExternalThumbnail(thumbnailUrl, fileId, ctx) {
	if (!thumbnailUrl) return null;
	let res;
	try {
		res = await fetch(thumbnailUrl, {
			headers: { 'User-Agent': 'NebrasDashboard/1.0' },
			redirect: 'follow'
		});
	} catch {
		return null;
	}
	if (!res.ok) return null;
	const ct = res.headers.get('content-type') || 'image/jpeg';
	if (!ct.startsWith('image/')) return null;
	const buf = Buffer.from(await res.arrayBuffer());
	if (buf.byteLength > 10 * 1024 * 1024) return null;

	const ext = ct.includes('png') ? 'png' : ct.includes('webp') ? 'webp' : 'jpg';
	const objectPath = `dashboard/content/${fileId}/thumbnail_${Date.now()}.${ext}`;
	const token = randomUUID();

	const bucket = getStorage(ctx.adminApp).bucket(ctx.bucketName);
	await bucket.file(objectPath).save(buf, {
		contentType: ct,
		resumable: false,
		metadata: {
			contentType: ct,
			metadata: {
				firebaseStorageDownloadTokens: token,
				uploadedByUid: ctx.uploaderUid || '',
				uploadedAt: new Date().toISOString(),
				source: 'noor-library'
			}
		}
	});
	return buildDownloadUrl(ctx.bucketName, objectPath, token);
}

/**
 * يرفع buffer إلى Storage ثمّ يكتب سجلَّيْن متطابقَيْن في RTDB:
 *   - dashboard_uploads/{fileId}            (أساسي)
 *   - content_unified/files/{fileId}        (mirror — حتى يقرأه تطبيق الموبايل
 *                                            من المسار التاريخيّ)
 *
 * @param {Object} args
 * @param {Buffer} args.buffer
 * @param {string} args.contentType         MIME من المصدر (مثل application/pdf)
 * @param {string} args.filename            اسم الملفّ الأصلي (للعرض)
 * @param {string} [args.thumbnailUrl]      رابط صورة الغلاف (سيُنسَخ إلى Storage)
 * @param {Object} args.metadata            metadata بنفس شكل moderator.js
 *   @param {string} args.metadata.title
 *   @param {string} [args.metadata.description]
 *   @param {string} [args.metadata.author]
 *   @param {string|number} args.metadata.subsection            معرّف القسم الفرعي (sub.id)
 *   @param {string|number} args.metadata.main_section          معرّف القسم الرئيسي (للـ mirror fields)
 *   @param {string|number} [args.metadata.secondary_subsection]
 *   @param {string} [args.metadata.subsection_name]
 *   @param {string} [args.metadata.main_section_name]
 *   @param {string} [args.metadata.secondary_subsection_name]
 *   @param {boolean} [args.metadata.is_listed]
 * @param {Object} args.uploader            { uid, email }
 * @param {Object} [args.source]            { provider, url, bookId } للمصدر الأصليّ
 *
 * @returns {Promise<{
 *   fileId: string,
 *   downloadUrl: string,
 *   storagePath: string,
 *   contentType: string,
 *   size: number,
 *   thumbnailUrl: string|null,
 *   payload: any
 * }>}
 */
export async function adminUploadAndRegister(args) {
	const { buffer, contentType, filename, thumbnailUrl, metadata, uploader, source } = args;

	if (!Buffer.isBuffer(buffer) || buffer.byteLength === 0) {
		throw Object.assign(new Error('buffer فارغ.'), { reason: 'empty_buffer', status: 400 });
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

	const adminApp = getNebrasAdminApp();
	assertNebrasApp(adminApp);
	const bucketName = adminApp.options?.storageBucket;
	if (!bucketName) {
		throw Object.assign(
			new Error(
				'NEBRAS_STORAGE_BUCKET (أو FIREBASE_STORAGE_BUCKET) غير مضبوط في .env — مطلوب لرفع الملفّات.'
			),
			{ reason: 'storage_bucket_missing', status: 501 }
		);
	}

	const fileId = `noor_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
	const safeName = sanitizeSegment(filename || 'book.pdf');
	const objectPath = `dashboard/noor-library/${fileId}/${Date.now()}_${safeName}`;
	const token = randomUUID();

	// 1) رفع الـ thumbnail (إن وُجد) قبل الملفّ لكي ندمج رابطه في metadata.
	const ctx = { adminApp, bucketName, uploaderUid: uploader?.uid || '' };
	let resolvedThumbnail = null;
	if (thumbnailUrl) {
		resolvedThumbnail = await uploadExternalThumbnail(thumbnailUrl, fileId, ctx);
	}

	// 2) رفع الملفّ الفعليّ.
	const finalContentType = contentType || 'application/octet-stream';
	const bucket = getStorage(adminApp).bucket(bucketName);
	await bucket.file(objectPath).save(buffer, {
		contentType: finalContentType,
		resumable: false,
		metadata: {
			contentType: finalContentType,
			metadata: {
				firebaseStorageDownloadTokens: token,
				uploadedByUid: uploader?.uid || '',
				uploadedByEmail: uploader?.email || '',
				uploadedAt: new Date().toISOString(),
				source: source?.provider || 'noor-library',
				sourceUrl: source?.url || '',
				sourceBookId: source?.bookId || ''
			}
		}
	});

	const downloadUrl = buildDownloadUrl(bucketName, objectPath, token);

	// 3-5) بناء السجل وكتابته (مشترك مع مسار الرفع الموقَّع signed-URL).
	return writeBookRecord({
		fileId,
		objectPath,
		downloadUrl,
		filename,
		finalContentType,
		size: buffer.byteLength,
		resolvedThumbnail,
		metadata,
		source
	});
}

/**
 * يبني الحمولة المطابقة لـ storageUpload.js ويكتبها على مجموعتَي Firestore.
 * مشترك بين: adminUploadAndRegister (رفع buffer) و registerUploadedBook
 * (كائن مرفوع مسبقاً عبر رابط موقَّع). لا يرفع الملفّ — يفترض وجوده في Storage.
 */
async function writeBookRecord({
	fileId,
	objectPath,
	downloadUrl,
	filename,
	finalContentType,
	size,
	resolvedThumbnail,
	metadata,
	source
}) {
	const finalMetadata = {
		...metadata,
		thumbnail: resolvedThumbnail || metadata.thumbnail || null,
		content_type:
			metadata.content_type || inferContentTypeFromMime(finalContentType, 'document'),
		is_listed: metadata.is_listed ?? true,
		created_at: new Date().toISOString()
	};
	const compatible = buildMobileCompatibleFields(finalMetadata, downloadUrl);

	const payload = stripUndefinedDeep({
		fileId,
		id: fileId,
		downloadUrl,
		filename,
		fileType: finalContentType,
		fileSize: size,
		metadata: finalMetadata,
		storagePath: objectPath,
		createdAt: FieldValue.serverTimestamp(),
		__provider: source?.provider || 'noor-library',
		__sourceUrl: source?.url || '',
		__sourceBookId: source?.bookId || '',
		__source_provider: source?.provider || 'noor-library',
		__license_status: source?.licenseStatus || 'manual_confirmed',
		__license: source?.license || '',
		__license_url: source?.licenseUrl || '',
		__compliance_version: '2026.05',
		__verified_at: new Date().toISOString(),
		...compatible
	});

	await adminFsWriteFileMirrorBoth(fileId, payload);

	return {
		fileId,
		downloadUrl,
		storagePath: objectPath,
		contentType: finalContentType,
		size,
		thumbnailUrl: resolvedThumbnail,
		payload
	};
}

/**
 * ينشئ رابط رفع موقَّع (V4 signed URL) لكائن جديد في تخزين نبراس، لكي يرفع
 * إليه مُشغِّل الـ CI البايتات مباشرةً (تجنّباً لحدّ حجم الطلب على Vercel،
 * وإبقاءً لاعتمادات Firebase على الخادم فقط). يُعيد المسار والرمز اللازمَين
 * لاحقاً في registerUploadedBook.
 *
 * @param {{ filename?: string, contentType?: string }} args
 */
export async function createNoorSignedUpload({ filename, contentType } = {}) {
	const adminApp = getNebrasAdminApp();
	assertNebrasApp(adminApp);
	const bucketName = adminApp.options?.storageBucket;
	if (!bucketName) {
		throw Object.assign(new Error('NEBRAS_STORAGE_BUCKET غير مضبوط.'), {
			reason: 'storage_bucket_missing',
			status: 501
		});
	}
	const fileId = `noor_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
	const safeName = sanitizeSegment(filename || 'book.pdf');
	const objectPath = `dashboard/noor-library/${fileId}/${Date.now()}_${safeName}`;
	const token = randomUUID();
	const finalContentType = contentType || 'application/pdf';

	const file = getStorage(adminApp).bucket(bucketName).file(objectPath);
	const [uploadUrl] = await file.getSignedUrl({
		version: 'v4',
		action: 'write',
		expires: Date.now() + 15 * 60 * 1000,
		contentType: finalContentType
	});

	return {
		fileId,
		objectPath,
		token,
		uploadUrl,
		downloadUrl: buildDownloadUrl(bucketName, objectPath, token),
		contentType: finalContentType
	};
}

/**
 * يسجّل كتاباً **رُفع مسبقاً** عبر رابط موقَّع: يضبط رمز التنزيل + بيانات
 * المصدر على الكائن (لكي يعمل رابط التنزيل العامّ للتطبيق)، يرفع الغلاف إن
 * وُجد، ثمّ يكتب سجلَّي Firestore. لا يرفع الملفّ الأساسيّ (موجود أصلاً).
 *
 * @param {{
 *   fileId: string, objectPath: string, downloadUrl: string, token: string,
 *   size: number, contentType: string, filename?: string,
 *   thumbnailUrl?: string|null, metadata: any, source?: any
 * }} args
 */
export async function registerUploadedBook(args) {
	const {
		fileId,
		objectPath,
		downloadUrl,
		token,
		size,
		contentType,
		filename,
		thumbnailUrl,
		metadata,
		source
	} = args;

	if (!fileId || !objectPath || !downloadUrl || !token) {
		throw Object.assign(new Error('بيانات الكائن المرفوع ناقصة.'), {
			reason: 'invalid_uploaded_object',
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

	const adminApp = getNebrasAdminApp();
	assertNebrasApp(adminApp);
	const bucketName = adminApp.options?.storageBucket;
	const bucket = getStorage(adminApp).bucket(bucketName);
	const finalContentType = contentType || 'application/pdf';

	// اضبط رمز التنزيل + بيانات المصدر على الكائن المرفوع (رابط PUT الموقَّع لا
	// يضبط الـ metadata المخصّص، ورمز التنزيل ضروريّ لعمل رابط التطبيق العامّ).
	await bucket.file(objectPath).setMetadata({
		contentType: finalContentType,
		metadata: {
			firebaseStorageDownloadTokens: token,
			uploadedByUid: 'noor_library_engine',
			uploadedAt: new Date().toISOString(),
			source: source?.provider || 'noor-library',
			sourceUrl: source?.url || '',
			sourceBookId: source?.bookId || ''
		}
	});

	// ارفع الغلاف (إن وُجد) إلى تخزين نبراس ودمج رابطه.
	let resolvedThumbnail = null;
	if (thumbnailUrl) {
		resolvedThumbnail = await uploadExternalThumbnail(thumbnailUrl, fileId, {
			adminApp,
			bucketName,
			uploaderUid: 'noor_library_engine'
		}).catch(() => null);
	}

	return writeBookRecord({
		fileId,
		objectPath,
		downloadUrl,
		filename: filename || 'book.pdf',
		finalContentType,
		size: Number(size) || 0,
		resolvedThumbnail,
		metadata,
		source
	});
}

/**
 * يكتب/يحدّث سجلّ مهمّة جلب (job) في `noor_library_jobs/{jobId}` لكي يستطيع
 * الـ UI تتبّع الحالة (queued → fetching → classifying → uploading → done | failed).
 *
 * @param {string} jobId
 * @param {Record<string, unknown>} patch
 */
export async function writeJobPatch(jobId, patch) {
	const ref = getAdminDatabase().ref(`noor_library_jobs/${jobId}`);
	const sanitized = stripUndefinedDeep({
		...patch,
		updatedAt: { '.sv': 'timestamp' }
	});
	await ref.update(sanitized);
}

export async function readJob(jobId) {
	const snap = await getAdminDatabase().ref(`noor_library_jobs/${jobId}`).get();
	return snap.exists() ? snap.val() : null;
}

export async function listRecentJobs(limit = 30) {
	const snap = await getAdminDatabase()
		.ref('noor_library_jobs')
		.orderByChild('startedAt')
		.limitToLast(limit)
		.get();
	if (!snap.exists()) return [];
	return Object.entries(snap.val() || {})
		.map(([id, v]) => ({ id, ...(v || {}) }))
		.sort((a, b) => Number(b.startedAt || 0) - Number(a.startedAt || 0));
}
