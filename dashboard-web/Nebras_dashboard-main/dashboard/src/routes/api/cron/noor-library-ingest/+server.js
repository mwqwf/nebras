/**
 * POST /api/cron/noor-library-ingest
 *
 * (تحت /api/cron كي لا يعترضه حارس الجلسة في hooks.server.js الذي يحمي
 *  /api/admin/* فقط — يُصادَق بـ CRON_SECRET مثل بقية مسارات الـ cron.)
 *
 * مسار الجلب الآليّ «المُقسَّم»: متصفّح GitHub Action (CI) يستخرج رابط
 * `internal_download` العامّ لكتاب من مكتبة نور (هذا وحده يحتاج متصفّحاً لتجاوز
 * جدار نور)، ثمّ يرسله هنا. الخادم يجلب البايتات بـ fetch عاديّ (الرابط عامّ)،
 * يصنّف محليّاً بلا أيّ ذكاء اصطناعي، يرفع إلى تخزين نبراس، ويكتب Firestore —
 * كلّه بإعادة استخدام نفس مسار المحرّك (`ingestResolvedBook`). يعمل على Vercel
 * لأنّ الجلب لا يحتاج متصفّحاً.
 *
 * المصادقة: `Bearer $CRON_SECRET` إن ضُبط، وإلا مسموح (secure-by-configuration،
 * نفس نمط مسارات الـ cron). حماية إضافيّة ضدّ إساءة الاستخدام: نقبل **فقط**
 * روابط `noor-book.com/.../book/internal_download/...` كملفّ، وروابط كتب نور
 * كمصدر — فلا يمكن تخزين ملفّات عشوائيّة عبر هذا المنفذ حتى لو كان مفتوحاً.
 *
 * Body (JSON):
 *   {
 *     bookUrl: string,       // رابط صفحة الكتاب على noor-book.com
 *     bookId: string,        // معرّف الكتاب (slug) لمنع التكرار
 *     fileUrl: string,       // رابط internal_download العامّ (استخرجه الـ CI)
 *     title: string,
 *     author?: string,
 *     description?: string,
 *     thumbnail?: string,
 *     categoryHints?: string[]
 *   }
 *
 * Response: { ok, skipped?, reason?, fileId?, title?, hierarchy? }
 */

import { json } from '@sveltejs/kit';
import { env } from '$env/dynamic/private';
import { isAdminConfigured } from '$lib/server/firebaseAdmin.js';
import { ingestResolvedBook } from '$lib/server/noorLibrary/engine.js';
import {
	isBookImported,
	recordFailure,
	partitionKnownBooks
} from '$lib/server/noorLibrary/registry.js';
import { parseNoorUrl } from '$lib/server/noorLibrary/fetcher.js';
import { DEFAULT_SEED_URLS } from '$lib/server/noorLibrary/crawler.js';
import { createNoorSignedUpload } from '$lib/server/noorLibrary/adminUploader.js';
import { INGEST_FROZEN, FROZEN_RESPONSE } from '$lib/server/ingestFreeze.js';

export const config = { maxDuration: 60 };

function authorize(event) {
	const secret = String(env.CRON_SECRET || '').trim();
	if (!secret) return { ok: true, unauthenticated: true };
	const header =
		event.request.headers.get('authorization') ||
		event.request.headers.get('Authorization') ||
		'';
	const m = /^Bearer\s+(.+)$/i.exec(header.trim());
	const token = m ? m[1].trim() : '';
	if (!token || token !== secret) return { ok: false, reason: 'invalid_cron_secret' };
	return { ok: true };
}

/**
 * GET — يزوّد مُشغِّل الـ CI بما يلزمه: قائمة البذور المشتركة + معرّفات الكتب
 * المعروفة (مجلوبة + blacklisted) لتفادي إعادة فتح المتصفّح لها.
 */
export async function GET(event) {
	const auth = authorize(event);
	if (!auth.ok) return json({ error: 'unauthorized', reason: auth.reason }, { status: 401 });
	let knownIds = [];
	try {
		const { knownIds: set } = await partitionKnownBooks([]);
		knownIds = [...set];
	} catch {
		knownIds = [];
	}
	return json({ ok: true, seeds: DEFAULT_SEED_URLS, knownIds });
}

function isNoorInternalDownloadUrl(u) {
	try {
		const url = new URL(String(u || ''));
		return (
			/(?:^|\.)noor-book\.com$/i.test(url.hostname) &&
			/\/book\/internal_download\//i.test(url.pathname)
		);
	} catch {
		return false;
	}
}

/** @type {import('@sveltejs/kit').RequestHandler} */
export async function POST(event) {
	// ❄️ الجلب مُجمّد بطلب المالك — لا نستوعب أيّ كتاب (2026-07-23).
	if (INGEST_FROZEN) return json(FROZEN_RESPONSE, { status: 200 });
	const auth = authorize(event);
	if (!auth.ok) return json({ error: 'unauthorized', reason: auth.reason }, { status: 401 });
	if (!isAdminConfigured()) return json({ error: 'not_configured' }, { status: 501 });

	let body;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'bad_request', reason: 'invalid_json' }, { status: 400 });
	}

	const step = String(body?.step || 'full').trim();
	const bookUrl = String(body?.bookUrl || '').trim();
	const parsed = parseNoorUrl(bookUrl);
	const bookId = String(body?.bookId || parsed?.bookId || '').trim();

	if (!parsed) {
		return json({ error: 'bad_request', reason: 'invalid_noor_url' }, { status: 400 });
	}
	if (!bookId) {
		return json({ error: 'bad_request', reason: 'book_id_required' }, { status: 400 });
	}

	// ═══ الخطوة 1: طلب رابط رفع موقَّع ═══════════════════════════════════
	// المُشغِّل نزّل البايتات بمتصفّحه (الرابط يحتاج جلسة Cloudflare)، ويحتاج
	// وجهةً يرفع إليها دون اعتمادات Firebase ولا حدّ حجم Vercel. نصدر رابط PUT
	// موقَّعاً لكائن في تخزين نبراس.
	if (step === 'signurl') {
		if (await isBookImported(bookId).catch(() => false)) {
			return json({ ok: true, skipped: true, reason: 'already_imported', bookId });
		}
		try {
			const su = await createNoorSignedUpload({
				filename: String(body?.filename || 'book.pdf'),
				contentType: String(body?.contentType || 'application/pdf')
			});
			return json({ ok: true, ...su });
		} catch (err) {
			return json(
				{ error: 'signurl_failed', reason: err?.reason || 'signurl_failed', message: err?.message || String(err) },
				{ status: err?.status || 500 }
			);
		}
	}

	// ═══ الخطوة 2: إنهاء — تصنيف محليّ + إنشاء أقسام + كتابة Firestore ════
	// الكائن مرفوع مسبقاً عبر الرابط الموقَّع؛ نمرّره كـ __preUploaded.
	if (step === 'finalize') {
		const objectPath = String(body?.objectPath || '').trim();
		const token = String(body?.token || '').trim();
		const downloadUrl = String(body?.downloadUrl || '').trim();
		const fileId = String(body?.fileId || '').trim();
		if (!fileId || !objectPath || !token || !downloadUrl) {
			return json({ error: 'bad_request', reason: 'missing_upload_fields' }, { status: 400 });
		}
		// حارس: الكائن يجب أن يكون ضمن مجلد نور في تخزيننا.
		if (!/^dashboard\/noor-library\//.test(objectPath)) {
			return json({ error: 'bad_request', reason: 'object_path_not_allowed' }, { status: 400 });
		}
		if (await isBookImported(bookId).catch(() => false)) {
			return json({ ok: true, skipped: true, reason: 'already_imported', bookId });
		}

		const meta = {
			title: String(body?.title || '').trim(),
			description: String(body?.description || '').trim(),
			author: String(body?.author || '').trim(),
			thumbnail: body?.thumbnail || null,
			categoryHints: Array.isArray(body?.categoryHints) ? body.categoryHints.slice(0, 12) : [],
			availability: { public: true, statusCode: '1', reason: 'ci_resolved' },
			source: { url: parsed.canonicalUrl, finalUrl: parsed.canonicalUrl, bookId, provider: 'noor-book.com' },
			__preUploaded: {
				fileId,
				objectPath,
				downloadUrl,
				token,
				size: Number(body?.size) || 0,
				contentType: String(body?.contentType || 'application/pdf'),
				filename: String(body?.filename || 'book.pdf')
			}
		};
		try {
			const r = await ingestResolvedBook({ url: parsed.canonicalUrl, bookId, meta });
			return json({
				ok: true,
				fileId: r.fileId,
				title: r.title,
				downloadUrl: r.downloadUrl,
				hierarchy: r.hierarchy,
				createdSectionsIds: r.createdSectionsIds
			});
		} catch (err) {
			const reason = err?.reason || 'finalize_failed';
			await recordFailure(bookId, { reason, message: err?.message || String(err), url: parsed.canonicalUrl }).catch(() => {});
			return json(
				{ error: 'finalize_failed', reason, message: err?.message || String(err) },
				{ status: err?.status || 500 }
			);
		}
	}

	// ═══ المسار الكامل (fallback): الخادم يجلب البايتات بنفسه ═════════════
	// يعمل فقط حين لا يُحجَب fetch العاديّ (نادر لروابط internal_download من
	// عناوين مراكز البيانات). يبقى مفيداً للاستدعاء اليدويّ/الاختبار.
	const fileUrl = String(body?.fileUrl || '').trim();
	if (!isNoorInternalDownloadUrl(fileUrl)) {
		return json({ error: 'bad_request', reason: 'file_url_not_allowed' }, { status: 400 });
	}
	if (await isBookImported(bookId).catch(() => false)) {
		return json({ ok: true, skipped: true, reason: 'already_imported', bookId });
	}
	const meta = {
		title: String(body?.title || '').trim(),
		description: String(body?.description || '').trim(),
		author: String(body?.author || '').trim(),
		thumbnail: body?.thumbnail || null,
		categoryHints: Array.isArray(body?.categoryHints) ? body.categoryHints.slice(0, 12) : [],
		availability: { public: true, statusCode: '1', reason: 'ci_resolved' },
		fileUrl,
		source: { url: parsed.canonicalUrl, finalUrl: parsed.canonicalUrl, bookId, provider: 'noor-book.com' }
	};
	try {
		const r = await ingestResolvedBook({ url: parsed.canonicalUrl, bookId, meta });
		return json({
			ok: true,
			fileId: r.fileId,
			title: r.title,
			downloadUrl: r.downloadUrl,
			hierarchy: r.hierarchy,
			createdSectionsIds: r.createdSectionsIds
		});
	} catch (err) {
		const reason = err?.reason || 'ingest_failed';
		await recordFailure(bookId, { reason, message: err?.message || String(err), url: parsed.canonicalUrl }).catch(() => {});
		return json(
			{ error: 'ingest_failed', reason, message: err?.message || String(err) },
			{ status: err?.status || 500 }
		);
	}
}
