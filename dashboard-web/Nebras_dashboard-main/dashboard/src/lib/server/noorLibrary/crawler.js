/**
 * crawler.js — استكشاف روابط الكتب من مكتبة نور برمجيّاً.
 *
 * يأخذ قائمة "بذور" (Seed URLs) — صفحات أقسام/مؤلفين/فهارس — ثمّ:
 *   1) يجلب HTML الصفحة الحاليّة.
 *   2) يستخرج كلّ روابط الكتب (`/book/...` أو `/كتاب-...`).
 *   3) يحسب رابط الصفحة التاليّة (Pagination) ويُعيده مع المجموعة.
 *
 * ╔══════════════════════════════════════════════════════════════════╗
 * ║  لا اعتماد على Mshcat/OldApp. يقرأ من Noor فقط.                  ║
 * ╚══════════════════════════════════════════════════════════════════╝
 *
 * مكتبة نور لا توفّر API، لكنّ صفحات الأقسام لها بنية يمكن التنبّؤ بها:
 *   https://www.noor-book.com/category/<slug>            (الصفحة 1)
 *   https://www.noor-book.com/category/<slug>?page=2     (تالية)
 *   https://www.noor-book.com/category/<slug>/page/2     (نمط بديل)
 *
 * نُحاول كلا النمطين عند توليد رابط الصفحة التاليّة، ونعتمد ما يُرجع HTML
 * يحوي روابط كتب جديدة.
 */

import { isPuppeteerEnabled, fetchHtmlViaBrowser } from './noorBrowser.js';
import { crawl4aiFetchHtml } from '$lib/server/crawl4aiClient.js';
import { scraperFetchHtml } from '$lib/server/scraperProxy.js';

const USER_AGENT =
	'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
	'(KHTML, like Gecko) Chrome/124.0 Safari/537.36 NebrasDashboard/1.0';

const NOOR_HOST = 'https://www.noor-book.com';

/**
 * يفحص ما إذا كانت استجابة HTML تطابق صفحة تحدّي Cloudflare. هذا
 * استدلاليّ: نتحقّق من عدّة marker شائعة. إن كانت موجودة، نسقط لاستعمال
 * Puppeteer الذي يجتاز التحدّي.
 */
function looksLikeCloudflareChallenge(html) {
	if (!html || html.length < 200) return true;
	const lower = html.toLowerCase();
	return (
		lower.includes('just a moment') ||
		lower.includes('checking your browser') ||
		lower.includes('cf-browser-verification') ||
		lower.includes('challenge-platform') ||
		lower.includes('cf-mitigated') ||
		lower.includes('attention required! | cloudflare')
	);
}

/**
 * بذور افتراضيّة لمحتوى **معرفيّ عامّ** يناسب نبراس (ليس دينياً فقط): روايات،
 * تاريخ، علم نفس، فلسفة، علوم، تطوير ذات، أطفال، طبّ، لغات — إضافةً إلى
 * صفحتَي «الأحدث» و«الأكثر رواجاً» لالتقاط الجديد باستمرار، وبعض أقسام
 * المعرفة الإسلاميّة ضمن الطيف العامّ. المستخدم يقدر يبدّلها من الواجهة
 * (POST /api/admin/noor-library/engine/seed). كلّها مُتحقَّق أنّها تُرجِع
 * روابط كتب فعليّة بنمط /ebook-.
 */
export const DEFAULT_SEED_URLS = [
	// عامّ ومتجدّد
	'https://www.noor-book.com/en/latest?landing=false',
	'https://www.noor-book.com/en/popular_all_days?landing=false',
	// معرفة عامّة
	'https://www.noor-book.com/category/روايات-عالمية',
	'https://www.noor-book.com/category/كتب-الروايات-والقصص',
	'https://www.noor-book.com/category/كتب-في-التاريخ',
	'https://www.noor-book.com/category/كتب-علم-النفس',
	'https://www.noor-book.com/category/كتب-الفلسفة-والمنطق',
	'https://www.noor-book.com/category/كتب-العلوم',
	'https://www.noor-book.com/category/كتب-تطوير-الذات',
	'https://www.noor-book.com/category/كتب-الاطفال',
	'https://www.noor-book.com/category/كتب-في-الطب',
	'https://www.noor-book.com/category/كتب-تعلم-اللغات',
	'https://www.noor-book.com/category/كتب-في-اللغة-العربية',
	// معرفة إسلاميّة (ضمن الطيف العامّ)
	'https://www.noor-book.com/category/كتب-اسلامية',
	'https://www.noor-book.com/category/كتب-في-التفسير-وعلوم-القرآن',
	'https://www.noor-book.com/category/كتب-في-الحديث-وعلومه',
	'https://www.noor-book.com/category/كتب-في-السيرة-النبوية',
	'https://www.noor-book.com/category/كتب-في-الفقه-وأصوله',
	'https://www.noor-book.com/category/كتب-في-العقيدة',
	'https://www.noor-book.com/category/كتب-في-التزكية-والأخلاق',
	// أدب وفنون وعلوم إنسانيّة
	'https://www.noor-book.com/category/كتب-ادب-وشعر',
	'https://www.noor-book.com/category/كتب-في-الادب',
	'https://www.noor-book.com/category/كتب-الشعر',
	'https://www.noor-book.com/category/كتب-فلسفة',
	'https://www.noor-book.com/category/كتب-الفنون',
	'https://www.noor-book.com/category/كتب-التنمية-البشرية',
	// علوم اجتماعيّة وسياسة واقتصاد وقانون
	'https://www.noor-book.com/category/كتب-الاقتصاد',
	'https://www.noor-book.com/category/كتب-السياسة',
	'https://www.noor-book.com/category/كتب-الاجتماع',
	'https://www.noor-book.com/category/كتب-التربية-والتعليم',
	'https://www.noor-book.com/category/كتب-القانون',
	// علوم بحتة وتطبيقيّة وتقنية
	'https://www.noor-book.com/category/كتب-في-الرياضيات',
	'https://www.noor-book.com/category/كتب-الفيزياء',
	'https://www.noor-book.com/category/كتب-الكيمياء',
	'https://www.noor-book.com/category/كتب-الاحياء',
	'https://www.noor-book.com/category/كتب-الجغرافيا',
	'https://www.noor-book.com/category/كتب-الحاسب',
	'https://www.noor-book.com/category/كتب-هندسة',
	'https://www.noor-book.com/category/كتب-في-الطبخ',
	// معرفة إسلاميّة متنوّعة إضافيّة
	'https://www.noor-book.com/category/كتب-اسلامية-متنوعة'
];

function makeError(message, reason, status = 0, cause = null) {
	const err = /** @type {any} */ (new Error(message));
	err.reason = reason;
	err.status = status;
	if (cause) err.cause = cause;
	return err;
}

/**
 * يجلب HTML بطلب fetch عاديّ. إن أرجع Cloudflare challenge أو 403،
 * يسقط تلقائياً لاستعمال Puppeteer (إن كان مفعّلاً).
 *
 * هذه الاستراتيجيّة "fetch-first" أرخص بـ ~100x من Puppeteer لكلّ صفحة،
 * فنُجرّبها أوّلاً ثمّ نعتمد على المتصفّح فقط عند الرفض.
 */
async function fetchHtml(url) {
	// 0) crawl4ai sidecar أولاً — متصفّح حقيقي يُصيّر JS ويجتاز تحدّي
	//    Cloudflare، ويعمل على الخادم/serverless (Puppeteer لا يعمل على Vercel).
	//    إن لم تكن الخدمة مضبوطة (CRAWL4AI_SERVICE_URL) يُعيد null فنُكمل للبدائل.
	try {
		const viaCrawl4ai = await crawl4aiFetchHtml(url, { timeoutMs: 60000 });
		if (viaCrawl4ai && !looksLikeCloudflareChallenge(viaCrawl4ai.html)) {
			return { html: viaCrawl4ai.html, finalUrl: viaCrawl4ai.finalUrl };
		}
	} catch {
		// فشل crawl4ai؟ نسقط للبدائل.
	}

	// وسيط API خارجيّ (إن ضُبط SCRAPER_API_URL_TEMPLATE) — يجتاز Cloudflare بمفتاح.
	try {
		const viaScraper = await scraperFetchHtml(url);
		if (viaScraper && !looksLikeCloudflareChallenge(viaScraper.html)) {
			return { html: viaScraper.html, finalUrl: viaScraper.finalUrl };
		}
	} catch {
		/* نسقط للبدائل */
	}

	const usePuppeteer = await isPuppeteerEnabled().catch(() => false);

	// إن كان Puppeteer متاحاً نُجرّبه مباشرةً للأمان (Noor خلف Cloudflare غالباً).
	if (usePuppeteer) {
		try {
			const r = await fetchHtmlViaBrowser(url, { waitForCloudflare: true });
			if (!looksLikeCloudflareChallenge(r.html)) {
				return { html: r.html, finalUrl: r.finalUrl };
			}
			throw makeError(
				'Cloudflare لم يُجتَز حتى مع Puppeteer (تحدّي مستمرّ).',
				'cloudflare_challenge_persistent',
				403
			);
		} catch (err) {
			if (err?.reason === 'cloudflare_challenge_persistent') throw err;
			// خطأ Puppeteer؟ نسقط لـ fetch العاديّ كاحتياط.
		}
	}

	let res;
	try {
		res = await fetch(url, {
			headers: {
				'User-Agent': USER_AGENT,
				Accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
				'Accept-Language': 'ar,en;q=0.7'
			},
			redirect: 'follow'
		});
	} catch (err) {
		throw makeError('تعذّر الاتصال بـ Noor Library.', 'crawler_network_error', 0, err);
	}
	if (!res.ok) {
		// 403/503 من Cloudflare → جرّب Puppeteer إن لم نكن جرّبناه أعلاه.
		if ((res.status === 403 || res.status === 503) && !usePuppeteer) {
			throw makeError(
				`Noor Library أرجعت ${res.status} لـ ${url} (يبدو Cloudflare). فعّل Puppeteer (NOOR_USE_PUPPETEER=true).`,
				'crawler_upstream_error',
				res.status
			);
		}
		throw makeError(
			`Noor Library أرجعت ${res.status} لـ ${url}`,
			'crawler_upstream_error',
			res.status
		);
	}
	const html = await res.text();
	if (looksLikeCloudflareChallenge(html)) {
		throw makeError(
			'استجابة Cloudflare تحدّي — يلزم Puppeteer لاجتيازها.',
			'cloudflare_challenge_detected',
			403
		);
	}
	return { html, finalUrl: res.url || url };
}

/**
 * استخراج كلّ روابط الكتب من HTML صفحة قائمة.
 * نقبل كلا النمطَيْن:
 *   - /book/review/<slug>
 *   - /book/<slug>
 *   - /كتاب-<slug>           (الـ Arabic-encoded path)
 *
 * @param {string} html
 * @param {string} baseUrl
 * @returns {Array<{ url: string, bookId: string }>}
 */
// أنماط slugs ليست كتباً (صفحات معلومات/سياسات يلتقطها نمط /كتاب-..).
// مثال من السجلّ: ".../كتاب-مه-نور-وحقوق-النشر-pdf" (صفحة حقوق النشر).
const NON_BOOK_SLUG_PATTERNS = [
	/حقوق.?النشر/, // copyright
	/سياسة|الخصوصية|privacy|policy/i,
	/اتصل|تواصل|contact|about|من-نحن/i,
	/شروط|terms|اتفاقية/i,
	/تسجيل|login|register|signup/i
];

function isLikelyBookSlug(slug) {
	const s = decodeURIComponent(String(slug || ''));
	if (!s) return false;
	for (const re of NON_BOOK_SLUG_PATTERNS) {
		if (re.test(s)) return false;
	}
	return true;
}

export function extractBookLinks(html, baseUrl) {
	const out = new Map(); // bookId → url (de-dup)

	// نمط 1: /book/review/SLUG — أكثر استعمالاً
	const re1 = /href=["']([^"']*\/book\/review\/[^"'?#]+)["']/gi;
	let m;
	while ((m = re1.exec(html))) {
		try {
			const abs = new URL(m[1], baseUrl).toString();
			const slug = decodeURIComponent(abs.split('/').filter(Boolean).pop() || '');
			if (slug && isLikelyBookSlug(slug) && !out.has(slug)) out.set(slug, abs);
		} catch {
			// تجاهل
		}
	}

	// نمط 2: /book/SLUG (لكن نتجنّب /book/review/...)
	const re2 = /href=["']([^"']*\/book\/(?!review\/)[^"'?#]+)["']/gi;
	while ((m = re2.exec(html))) {
		try {
			const abs = new URL(m[1], baseUrl).toString();
			const slug = decodeURIComponent(abs.split('/').filter(Boolean).pop() || '');
			if (slug && isLikelyBookSlug(slug) && !out.has(slug)) out.set(slug, abs);
		} catch {
			// تجاهل
		}
	}

	// نمط 3: /كتاب-SLUG (الـ Arabic-encoded path)
	const re3 = /href=["']([^"']*\/(?:كتاب|%D9%83%D8%AA%D8%A7%D8%A8)-[^"'?#]+)["']/gi;
	while ((m = re3.exec(html))) {
		try {
			const abs = new URL(m[1], baseUrl).toString();
			const slug = decodeURIComponent(abs.split('/').filter(Boolean).pop() || '');
			if (slug && isLikelyBookSlug(slug) && !out.has(slug)) out.set(slug, abs);
		} catch {
			// تجاهل
		}
	}

	// نمط 4: /ebook-SLUG (النمط الحاليّ الأكثر شيوعاً في نور، مع بادئة لغة
	//        اختياريّة مثل /en/ أو /ar/). هذا هو الشكل الفعليّ لروابط الكتب
	//        على الموقع الآن — بدونه لا يلتقط المستكشِف أيّ كتاب.
	const re4 = /href=["']([^"']*\/(?:[a-z]{2}\/)?ebook-[^"'?#]+)["']/gi;
	while ((m = re4.exec(html))) {
		try {
			const abs = new URL(m[1], baseUrl).toString();
			const slug = decodeURIComponent(abs.split('/').filter(Boolean).pop() || '');
			if (slug && isLikelyBookSlug(slug) && !out.has(slug)) out.set(slug, abs);
		} catch {
			// تجاهل
		}
	}

	return Array.from(out.entries()).map(([bookId, url]) => ({ bookId, url }));
}

/**
 * يحسب رابط الصفحة التالية لـ pagination على بذرة معيّنة.
 * يُجرّب نمط `?page=N` (الأكثر شيوعاً عند Noor).
 *
 * @param {string} seedUrl — رابط البذرة الأصلي (page 1)
 * @param {number} pageNumber — رقم الصفحة المستهدف (>=2)
 * @returns {string}
 */
export function buildPaginationUrl(seedUrl, pageNumber) {
	const n = Math.max(1, Math.floor(Number(pageNumber) || 1));
	if (n === 1) return seedUrl;

	let u;
	try {
		u = new URL(seedUrl);
	} catch {
		return seedUrl;
	}
	u.searchParams.set('page', String(n));
	return u.toString();
}

/**
 * يجلب صفحة بذرة (أو صفحة من نفس البذرة) ويعيد روابط الكتب الموجودة فيها.
 *
 * @param {string} seedUrl
 * @param {number} [page=1]
 * @returns {Promise<{
 *   sourceUrl: string,
 *   page: number,
 *   bookLinks: Array<{ url: string, bookId: string }>,
 *   nextPage: number | null
 * }>}
 */
export async function discoverBooksOnSeedPage(seedUrl, page = 1) {
	const url = buildPaginationUrl(seedUrl, page);
	const { html, finalUrl } = await fetchHtml(url);
	const bookLinks = extractBookLinks(html, finalUrl);

	// إن وجدنا روابط كتب → نفترض احتمال وجود صفحة تالية. إن لم نجد → نتوقّف.
	const nextPage = bookLinks.length > 0 ? page + 1 : null;

	return {
		sourceUrl: finalUrl,
		page,
		bookLinks,
		nextPage
	};
}

/**
 * نُجرّب جلب صفحات متتالية من البذرة الحاليّة حتى نجد batchSize كتاباً
 * **جديداً** (غير موجود في `knownIds`) أو نستهلك maxPages.
 *
 * @param {{
 *   seedUrl: string,
 *   startPage: number,
 *   batchSize: number,
 *   maxPagesPerCall: number,
 *   knownIds: Set<string>
 * }} args
 *
 * @returns {Promise<{
 *   newBooks: Array<{ url: string, bookId: string }>,
 *   pagesScanned: number,
 *   nextPage: number | null,
 *   exhausted: boolean
 * }>}
 */
export async function discoverNewBooks({
	seedUrl,
	startPage = 1,
	batchSize = 5,
	maxPagesPerCall = 4,
	knownIds = new Set()
}) {
	const collected = new Map();
	// كلّ معرّفات الكتب التي رأيناها في هذا النداء (بصرف النظر عن معرفتها
	// مسبقاً). تُستعمل لكشف الصفحات المتطابقة: كثير من صفحات نور من نوع
	// /category لا تُرقّم فعلاً (page=2 يُعيد نفس محتوى page=1)، فإن لم تُضِف
	// الصفحة أيّ معرّف جديد لهذا المسح نعتبر البذرة مُستنفدة ونتوقّف.
	const pageSeenIds = new Set();
	let page = Math.max(1, startPage);
	let pagesScanned = 0;
	let nextPage = null;
	let exhausted = false;

	while (pagesScanned < maxPagesPerCall && collected.size < batchSize) {
		let result;
		try {
			result = await discoverBooksOnSeedPage(seedUrl, page);
		} catch (err) {
			// خطأ صفحة معيّنة لا يجب أن يُنهي الجولة الكاملة — نسجّل ونتقدّم.
			pagesScanned++;
			page++;
			if (pagesScanned >= maxPagesPerCall) break;
			continue;
		}
		pagesScanned++;

		let newToScan = 0;
		for (const link of result.bookLinks) {
			if (!pageSeenIds.has(link.bookId)) {
				pageSeenIds.add(link.bookId);
				newToScan += 1;
			}
			if (knownIds.has(link.bookId)) continue;
			if (collected.has(link.bookId)) continue;
			collected.set(link.bookId, link);
			if (collected.size >= batchSize) break;
		}

		// صفحة لم تُضِف أيّ كتاب جديد لهذا المسح (وليست الأولى) = صفحة مكرّرة
		// (لا ترقيم فعليّ) ⇒ البذرة مُستنفدة، ننتقل للبذرة التاليّة.
		if (newToScan === 0 && pagesScanned > 1) {
			exhausted = true;
			break;
		}

		if (result.nextPage === null) {
			exhausted = true;
			break;
		}
		nextPage = result.nextPage;
		page = result.nextPage;
	}

	return {
		newBooks: Array.from(collected.values()),
		pagesScanned,
		nextPage: exhausted ? null : nextPage || page,
		exhausted
	};
}

/**
 * يتحقّق أنّ رابط البذرة ينتمي لمكتبة نور (أمان أساسي).
 * @param {string} url
 */
export function isValidSeedUrl(url) {
	try {
		const u = new URL(String(url || '').trim());
		return /(^|\.)noor-book\.com$/i.test(u.hostname) && u.protocol.startsWith('http');
	} catch {
		return false;
	}
}
