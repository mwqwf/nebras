/**
 * POST /api/admin/noor-library/import
 *
 * يُنفّذ التدفّق الكامل: تنزيل الملفّ من مكتبة نور → رفعه إلى Firebase
 * Storage Admin → كتابة السجلّ في dashboard_uploads/{fileId} **و**
 * content_unified/files/{fileId}، مع تحديث سجلّ المهمّة في
 * noor_library_jobs/{jobId} لتتبّع التقدّم لحظيّاً من الواجهة.
 *
 * 🔒 Target Isolation: يكتب حصراً إلى مشروع نبراس الأساسي. لا يلمس
 *    Mshcat/OldApp إطلاقاً (راجع adminUploader.js للتفاصيل).
 *
 * Body:
 *   {
 *     url: string,                            // رابط صفحة الكتاب
 *     metadata: { title, description?, author?, thumbnail? },
 *     hierarchy: { mainId, subId, secondaryId? },     // المسار الذهبي المُختار
 *     overrideFileUrl?: string,               // (نادر) لو أراد المستخدم تجاوز الكشف الآلي
 *     listed?: boolean
 *   }
 *
 * Response (200):
 *   { ok, jobId, fileId, downloadUrl, path, recordPath }
 *
 * Response (4xx/5xx):
 *   { error, reason, message, jobId? }
 *
 * تصميم Long-running:
 *   نُنشئ jobId فوراً ثمّ نشغّل العملية sync (التنزيل ≤ 50–100MB غالباً).
 *   مستقبلاً يمكن جعل العملية async و الواجهة تستعلم عبر /jobs/{id}.
 */

import { json } from '@sveltejs/kit';
import { buildSectionsTree, validateHierarchyPath } from '$lib/server/noorLibrary/sectionsTree.js';
import { fetchBookMetadata, downloadBookFile, parseNoorUrl } from '$lib/server/noorLibrary/fetcher.js';
import { adminUploadAndRegister, writeJobPatch } from '$lib/server/noorLibrary/adminUploader.js';
import { isAdminConfigured } from '$lib/server/firebaseAdmin.js';

// زيادة حدّ الـ body حتى لا يرفض SvelteKit الطلب رغم أنّنا لا نرسل ملفّاً
// (الملفّ يُجلَب من خادم خارجي). الـ JSON صغير، لكن نرفع لأمان.
export const config = {
	bodySizeLimit: 5 * 1024 * 1024
};

function makeJobId() {
	return `job_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
}

/** @type {import('@sveltejs/kit').RequestHandler} */
export async function POST(event) {
	const auth = event.locals?.auth;
	if (!auth) return json({ error: 'unauthenticated' }, { status: 401 });
	if (auth.role !== 'owner' && auth.role !== 'supervisor') {
		return json({ error: 'forbidden', reason: 'role_not_allowed' }, { status: 403 });
	}

	if (!isAdminConfigured()) {
		return json(
			{
				error: 'not_configured',
				reason: 'admin_service_account_missing',
				message:
					'سكريبت الجلب يحتاج NEBRAS_SERVICE_ACCOUNT_PATH/JSON في .env و ملف خدمة صالح في secrets/.'
			},
			{ status: 501 }
		);
	}

	let body;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'bad_request', reason: 'invalid_json' }, { status: 400 });
	}

	const url = String(body?.url || '').trim();
	if (!parseNoorUrl(url)) {
		return json({ error: 'bad_request', reason: 'invalid_noor_url' }, { status: 400 });
	}

	const hierarchy = body?.hierarchy || {};
	const userMetadata = body?.metadata || {};
	const overrideFileUrl = String(body?.overrideFileUrl || '').trim();
	const listed = body?.listed !== false;

	const jobId = makeJobId();
	const startedAt = Date.now();

	// 0) إنشاء سجلّ المهمّة
	await writeJobPatch(jobId, {
		jobId,
		status: 'started',
		startedAt,
		url,
		uploaderUid: auth.uid,
		uploaderEmail: auth.email
	}).catch(() => {});

	try {
		// 1) قراءة شجرة الأقسام والتحقّق من المسار الذهبي
		await writeJobPatch(jobId, { status: 'reading_sections' }).catch(() => {});
		const sections = await buildSectionsTree();
		const validation = validateHierarchyPath(
			{
				mainId: hierarchy.mainId,
				subId: hierarchy.subId,
				secondaryId: hierarchy.secondaryId || null
			},
			sections.index
		);
		if (!validation.valid) {
			await writeJobPatch(jobId, { status: 'failed', failedReason: validation.reason }).catch(() => {});
			return json(
				{
					error: 'invalid_hierarchy',
					reason: validation.reason,
					message: 'المسار المُختار لا يحترم القاعدة الذهبيّة [main → sub → secondary].',
					jobId
				},
				{ status: 422 }
			);
		}
		const { main, sub, secondary } = validation.resolved;

		// 2) جلب metadata من مكتبة نور (نُعيد التأكّد منها لكي نضمن fileUrl).
		await writeJobPatch(jobId, { status: 'fetching_metadata' }).catch(() => {});
		const fetched = await fetchBookMetadata(url);

		// كتب عامّة فقط: نرفض المحفوظة/متابعة النشر (غير متاحة للتحميل في نور).
		// يتجاوزها المستخدم فقط بتمرير overrideFileUrl (رابط مباشر يعرفه).
		if (fetched.availability && fetched.availability.public === false && !overrideFileUrl) {
			await writeJobPatch(jobId, {
				status: 'failed',
				failedReason: 'book_not_public',
				bookTitle: fetched.title
			}).catch(() => {});
			return json(
				{
					error: 'book_not_public',
					reason: 'book_not_public',
					message:
						'هذا الكتاب «محفوظ / متابعة نشر» في مكتبة نور وغير متاح للتحميل — يُجلب فقط الكتب العامّة.',
					jobId,
					metadata: fetched
				},
				{ status: 422 }
			);
		}

		const fileUrl = overrideFileUrl || fetched.fileUrl;
		if (!fileUrl) {
			await writeJobPatch(jobId, {
				status: 'failed',
				failedReason: 'no_file_url',
				bookTitle: fetched.title
			}).catch(() => {});
			return json(
				{
					error: 'no_file_url',
					reason: 'no_file_url',
					message:
						'لم نستطع استخراج رابط الملفّ من صفحة مكتبة نور. مرّر overrideFileUrl يدوياً إن كان لديك الرابط المباشر.',
					jobId,
					metadata: fetched
				},
				{ status: 422 }
			);
		}

		// 3) تنزيل الملفّ
		await writeJobPatch(jobId, {
			status: 'downloading_file',
			bookTitle: fetched.title,
			fileUrl
		}).catch(() => {});
		const downloaded = await downloadBookFile(fileUrl);

		// 4) رفع الملفّ + كتابة سجلّيْ RTDB في عمليّة واحدة
		await writeJobPatch(jobId, {
			status: 'uploading',
			fileSize: downloaded.size,
			contentType: downloaded.contentType
		}).catch(() => {});

		const finalMetadata = {
			title: String(userMetadata.title || fetched.title || '').trim(),
			description: String(userMetadata.description || fetched.description || '').trim(),
			author: String(userMetadata.author || fetched.author || '').trim(),
			thumbnail: userMetadata.thumbnail || fetched.thumbnail || null,
			is_listed: listed,

			// الهيكلية الذهبيّة — نمرّر IDs والأسماء لتطبيق الموبايل.
			main_section: String(main.id),
			main_section_id: String(main.id),
			main_section_name: String(main.name || ''),
			subsection: String(sub.id),
			subsection_name: String(sub.name || ''),
			...(secondary
				? {
						secondary_subsection: String(secondary.id),
						secondary_subsection_name: String(secondary.name || '')
					}
				: { secondary_subsection: null })
		};

		const result = await adminUploadAndRegister({
			buffer: downloaded.buffer,
			contentType: downloaded.contentType,
			filename: downloaded.filename,
			thumbnailUrl: finalMetadata.thumbnail,
			metadata: finalMetadata,
			uploader: { uid: auth.uid, email: auth.email },
			source: {
				provider: 'noor-library',
				url: fetched.source.url,
				bookId: fetched.source.bookId
			}
		});

		// 5) ختام المهمّة بنجاح
		await writeJobPatch(jobId, {
			status: 'completed',
			completedAt: Date.now(),
			fileId: result.fileId,
			downloadUrl: result.downloadUrl,
			storagePath: result.storagePath,
			thumbnailUrl: result.thumbnailUrl || null,
			elapsedMs: Date.now() - startedAt
		}).catch(() => {});

		return json({
			ok: true,
			jobId,
			fileId: result.fileId,
			downloadUrl: result.downloadUrl,
			storagePath: result.storagePath,
			thumbnailUrl: result.thumbnailUrl,
			recordPaths: {
				primary: `dashboard_uploads/${result.fileId}`,
				mirror: `content_unified/files/${result.fileId}`
			},
			hierarchy: {
				main: { id: main.id, name: main.name },
				sub: { id: sub.id, name: sub.name },
				secondary: secondary ? { id: secondary.id, name: secondary.name } : null
			},
			elapsedMs: Date.now() - startedAt
		});
	} catch (err) {
		const reason = err?.reason || 'import_failed';
		const status = err?.status || 500;
		await writeJobPatch(jobId, {
			status: 'failed',
			failedReason: reason,
			failedMessage: err?.message || String(err)
		}).catch(() => {});
		return json(
			{
				error: 'import_failed',
				reason,
				message: err?.message || 'فشل غير متوقع أثناء الجلب.',
				jobId
			},
			{ status }
		);
	}
}
