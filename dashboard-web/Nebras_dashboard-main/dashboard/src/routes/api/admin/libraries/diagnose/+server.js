/**
 * GET /api/admin/libraries/diagnose?source=noor|hindawi
 *
 * تشخيص حيّ لسبب عدم عمل محرّكَي مكتبة نور / مؤسسة هنداوي:
 *   1) هل crawl4ai مضبوطة وتستجيب (/health)؟
 *   2) هل تجلب HTML لصفحة فهرسة فعليّة (وليس تحدّي Cloudflare)؟
 *   3) هل تُستخرج روابط كتب من تلك الصفحة؟
 *
 * يُرجع verdict واضحاً + الخطوة التالية المقترَحة. للمالك/المشرف فقط.
 */
import { json } from '@sveltejs/kit';
import { isAdminConfigured } from '$lib/server/firebaseAdmin.js';
import { crawl4aiHealth, crawl4aiFetchHtml, crawl4aiConfigured } from '$lib/server/crawl4aiClient.js';
import { extractBookLinks as noorExtract, DEFAULT_SEED_URLS } from '$lib/server/noorLibrary/crawler.js';
import { extractBookLinks as hindawiExtract, buildCategoryUrl } from '$lib/server/hindawi/crawler.js';

function looksLikeCloudflare(html) {
	const s = String(html || '').toLowerCase();
	return (
		s.includes('just a moment') ||
		s.includes('challenge-platform') ||
		s.includes('cf-mitigated') ||
		s.includes('attention required')
	);
}

/** @type {import('@sveltejs/kit').RequestHandler} */
export async function GET(event) {
	const auth = event.locals?.auth;
	if (!auth) return json({ error: 'unauthenticated' }, { status: 401 });
	if (auth.role !== 'owner' && auth.role !== 'supervisor') {
		return json({ error: 'forbidden', reason: 'role_not_allowed' }, { status: 403 });
	}
	if (!isAdminConfigured()) return json({ error: 'not_configured' }, { status: 501 });

	const source = String(event.url.searchParams.get('source') || 'noor').toLowerCase();
	const sampleUrl =
		source === 'hindawi' ? buildCategoryUrl('history', 1) : DEFAULT_SEED_URLS[0];

	const steps = [];
	let verdict = '';
	let nextStep = '';

	const UA =
		'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
		'(KHTML, like Gecko) Chrome/124.0 Safari/537.36 NebrasDashboard/1.0';

	// 1) صحّة crawl4ai (معلوماتيّة فقط — ليست شرطاً؛ هنداوي تعمل بـ fetch عاديّ).
	const health = await crawl4aiHealth();
	steps.push({ step: 'crawl4ai_health', ...health });

	// 2) جلب صفحة الفهرسة بنفس منطق المحرّك: crawl4ai أولاً (إن وُجد) ثمّ fetch عاديّ.
	let html = '';
	let fetchOk = false;
	let method = '';
	let fetchDetail = '';
	if (health.configured && health.reachable) {
		try {
			const r = await crawl4aiFetchHtml(sampleUrl, { timeoutMs: 60000 });
			if (r && r.html) { html = r.html; fetchOk = true; method = 'crawl4ai'; }
		} catch (e) {
			fetchDetail = `crawl4ai: ${e?.message || String(e)}`;
		}
	}
	if (!fetchOk) {
		// fallback: طلب HTTP مباشر (يكفي لهنداوي؛ نور غالباً يُحجب بـ Cloudflare).
		try {
			const res = await fetch(sampleUrl, {
				headers: { 'User-Agent': UA, Accept: 'text/html,*/*;q=0.8', 'Accept-Language': 'ar,en;q=0.7' },
				redirect: 'follow'
			});
			const body = await res.text();
			if (res.ok && body && body.length >= 200) { html = body; fetchOk = true; method = 'plain_fetch'; }
			else fetchDetail = `fetch: HTTP ${res.status}, طول ${body?.length || 0}`;
		} catch (e) {
			fetchDetail = `fetch: ${e?.message || String(e)}`;
		}
	}
	const cf = looksLikeCloudflare(html);
	steps.push({ step: 'fetch_listing', url: sampleUrl, ok: fetchOk, method, cloudflareChallenge: cf, detail: fetchDetail || `طول HTML = ${html.length}` });

	// 3) استخراج روابط الكتب (الحَكَم الفعليّ): إن استُخرجت روابط فالجلب ناجح،
	//    بصرف النظر عن إشارة Cloudflare الاستدلاليّة (قد تكون إيجابيّة كاذبة).
	const links = fetchOk ? (source === 'hindawi' ? hindawiExtract(html) : noorExtract(html, sampleUrl)) : [];
	steps.push({ step: 'extract_book_links', count: links.length, sample: links.slice(0, 3) });

	if (links.length > 0) {
		verdict = `✅ سليم: الصفحة تُجلب (الطريقة: ${method || '—'}) واستُخرج ${links.length} رابط كتاب. اضغط «دورة الآن» لبدء الجلب.`;
		nextStep = 'شغّل «دورة الآن» وراقب السجلّ. الـ cron سيواصل تلقائياً.';
		return json({ ok: true, source, sampleUrl, steps, verdict, nextStep });
	}

	// لا روابط: فرّق بين حجب فعليّ وتغيّر بنية.
	if (!fetchOk || cf) {
		if (source === 'hindawi') {
			verdict = '⛔ تعذّر جلب صفحة هنداوي فعلاً.';
			nextStep = 'أعد المحاولة بعد دقيقة؛ إن تكرّر بلّغني بنصّ هذا التشخيص.';
		} else {
			verdict = '⚠ نور محجوبة بـ Cloudflare للطلب المباشر — تحتاج وسيطاً.';
			nextStep = 'اضبط SCRAPER_API_URL_TEMPLATE في Vercel (مفتاح خدمة scraping) أو انشر crawl4ai.';
		}
	} else {
		verdict = '⚠ جُلِبت الصفحة لكن لم تُستخرج روابط كتب (تغيّر بنية الموقع؟).';
		nextStep = 'بلّغني — أحدّث أنماط الاستخراج (regex).';
	}
	return json({ ok: true, source, sampleUrl, steps, verdict, nextStep });
}
