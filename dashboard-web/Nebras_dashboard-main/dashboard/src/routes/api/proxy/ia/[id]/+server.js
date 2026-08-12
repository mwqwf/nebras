/**
 * GET|HEAD /api/proxy/ia/{fileId}[.ext][?t=thumb]
 *
 * ╔══════════════════════════════════════════════════════════════════╗
 * ║  الجسر الحقيقيّ بين تطبيق نبراس و Internet Archive.               ║
 * ║                                                                  ║
 * ║   • التطبيق يطلب هذا المسار (لا يعرف أنّ المصدر archive.org).      ║
 * ║   • نقرأ الوثيقة من Firestore (Admin) لنجلب __iaFileUrl المُخزَّن. ║
 * ║   • نجلب من IA server-to-server ونمرّر الـ stream مباشرةً —        ║
 * ║     لا تخزين، لا buffer كامل.                                      ║
 * ║   • نمرّر رأس Range (resumable للصوت/الفيديو، seek للـ PDF).       ║
 * ║                                                                  ║
 * ║  أمان (SSRF): لا نجلب إلا روابط مضيفها *.archive.org المُخزَّنة     ║
 * ║  بأنفسنا في وثيقة علامتها __provider='internet_archive'.           ║
 * ╚══════════════════════════════════════════════════════════════════╝
 */
import { error } from '@sveltejs/kit';
import { getNebrasFirestoreAdmin, isAdminConfigured } from '$lib/server/firebaseAdmin.js';
import { NEBRAS_FS_CONTENT_FILES } from '$lib/firebase/nebrasUnifiedPaths.js';

/** Vercel Pro: حتى 300s. مع تمرير Range يبقى كلّ طلب قصيراً عملياً. */
export const config = { maxDuration: 300 };

const USER_AGENT =
	'NebrasApp/1.0 (https://nebras.app; contact: app@nebras.app) NebrasIAProxy';

// امتدادات نضيفها للرابط لمساعدة مشغّلات التطبيق — نُجرّدها لاستخراج fileId.
const EXT_RE = /\.(pdf|mp3|m4a|aac|wav|ogg|opus|flac|mp4)$/i;

/** يتأكّد أنّ المضيف ينتمي لـ archive.org (حارس SSRF). */
function isArchiveOrgUrl(url) {
	try {
		const u = new URL(String(url));
		if (u.protocol !== 'https:') return false;
		return u.hostname === 'archive.org' || u.hostname.endsWith('.archive.org');
	} catch {
		return false;
	}
}

async function handle(event, headOnly) {
	if (!isAdminConfigured()) throw error(503, 'not_configured');

	const fileId = String(event.params.id || '').replace(EXT_RE, '');
	if (!fileId) throw error(404, 'not_found');

	const isThumb = event.url.searchParams.get('t') === 'thumb';

	const fs = getNebrasFirestoreAdmin();
	const snap = await fs.collection(NEBRAS_FS_CONTENT_FILES).doc(fileId).get();
	if (!snap.exists) throw error(404, 'not_found');
	const data = snap.data() || {};
	if (data.__provider !== 'internet_archive') throw error(404, 'not_found');

	const target = isThumb ? data.__iaThumbUrl : data.__iaFileUrl;
	if (!isArchiveOrgUrl(target)) throw error(404, 'not_found');

	const range = event.request.headers.get('range');
	const upstreamHeaders = { 'User-Agent': USER_AGENT, Accept: '*/*' };
	if (range) upstreamHeaders.Range = range;

	let upstream;
	try {
		upstream = await fetch(target, {
			method: headOnly ? 'HEAD' : 'GET',
			redirect: 'follow',
			headers: upstreamHeaders
		});
	} catch (err) {
		throw error(502, `upstream_fetch_failed: ${err?.message || err}`);
	}

	if (!upstream.ok && upstream.status !== 206) {
		try {
			await upstream.body?.cancel();
		} catch {
			/* ignore */
		}
		throw error(upstream.status === 404 ? 404 : 502, `upstream_${upstream.status}`);
	}

	const headers = new Headers();
	// نوع المحتوى: نُفضّل المُعلَن في الوثيقة (قاطع) إلا للصور (نتبع المنبع).
	const upstreamCt = upstream.headers.get('content-type') || '';
	if (isThumb) {
		headers.set('Content-Type', upstreamCt || 'image/jpeg');
	} else {
		const declared = String(data.fileType || '');
		headers.set('Content-Type', declared && declared !== 'application/octet-stream' ? declared : upstreamCt || 'application/octet-stream');
	}

	for (const h of ['content-length', 'content-range', 'accept-ranges', 'last-modified', 'etag']) {
		const v = upstream.headers.get(h);
		if (v) headers.set(h, v);
	}
	if (!headers.has('accept-ranges')) headers.set('Accept-Ranges', 'bytes');
	// CDN/متصفّح يُخزّن المشهور — يخفّف الضغط على IA وعلى الدالّة.
	headers.set('Cache-Control', 'public, max-age=86400, s-maxage=86400');

	return new Response(headOnly ? null : upstream.body, {
		status: upstream.status,
		headers
	});
}

/** @type {import('@sveltejs/kit').RequestHandler} */
export const GET = (event) => handle(event, false);

/** @type {import('@sveltejs/kit').RequestHandler} */
export const HEAD = (event) => handle(event, true);
