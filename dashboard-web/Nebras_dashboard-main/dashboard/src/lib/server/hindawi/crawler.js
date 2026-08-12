/**
 * crawler.js — استكشاف كتب هنداوي **حسب التصنيف الحقيقيّ**.
 *
 * هنداوي تصنّف كتبها في صفحات: https://www.hindawi.org/books/categories/{slug}/{page}/
 * (تحقّقنا حيّاً: كل صفحة 20 كتاباً، والترقيم بالشكل /{page}/).
 *
 * نزحف كل تصنيف على حدة، فيُعرف تصنيف كل كتاب بالبناء (من الصفحة التي جاء
 * منها) — وبهذا نُنشئ قسماً حقيقياً لكل تصنيف (فلسفة/تاريخ/أدب…) بلا تخمين.
 *
 * هنداوي بلا Cloudflare → fetch عاديّ يكفي (crawl4ai احتياط فقط).
 */

import { crawl4aiFetchHtml } from '$lib/server/crawl4aiClient.js';

const USER_AGENT =
	'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
	'(KHTML, like Gecko) Chrome/124.0 Safari/537.36 NebrasDashboard/1.0';

/**
 * تصنيفات هنداوي (slug على الموقع → الاسم العربيّ للقسم في نبراس).
 * مستخرَجة حيّاً من تنقّل /books/categories/ على الموقع.
 */
export const HINDAWI_CATEGORIES = Object.freeze([
	{ slug: 'literature', name: 'الأدب' },
	{ slug: 'novels', name: 'الروايات' },
	{ slug: 'history', name: 'التاريخ' },
	{ slug: 'philosophy', name: 'الفلسفة' },
	{ slug: 'poetry', name: 'الشعر' },
	{ slug: 'plays', name: 'المسرحيات' },
	{ slug: 'linguistics', name: 'اللغة واللغويات' },
	{ slug: 'literary.criticism', name: 'النقد الأدبي' },
	{ slug: 'biographies', name: 'السير والتراجم' },
	{ slug: 'politics', name: 'السياسة' },
	{ slug: 'economics', name: 'الاقتصاد' },
	{ slug: 'social.sciences', name: 'العلوم الاجتماعية' },
	{ slug: 'psychology', name: 'علم النفس' },
	{ slug: 'philosophy', name: 'الفلسفة' },
	{ slug: 'religions', name: 'الأديان' },
	{ slug: 'science', name: 'العلوم' },
	{ slug: 'science.fiction', name: 'الخيال العلمي' },
	{ slug: 'detective.fiction', name: 'الروايات البوليسية' },
	{ slug: 'children.stories', name: 'قصص الأطفال' },
	{ slug: 'arts', name: 'الفنون' },
	{ slug: 'geography', name: 'الجغرافيا' },
	{ slug: 'travel.literature', name: 'أدب الرحلات' },
	{ slug: 'health', name: 'الصحة' },
	{ slug: 'environmental.sciences', name: 'علوم البيئة' },
	{ slug: 'technology', name: 'التكنولوجيا' },
	{ slug: 'business', name: 'الأعمال والإدارة' }
].filter((c, i, arr) => arr.findIndex((x) => x.slug === c.slug) === i)); // إزالة التكرار

export const MAX_CATEGORY_PAGES = 60; // سقف صفحات لكل تصنيف قبل اللفّ

function makeError(message, reason, status = 0, cause = null) {
	const err = /** @type {any} */ (new Error(message));
	err.reason = reason;
	err.status = status;
	if (cause) err.cause = cause;
	return err;
}

/** يبني رابط صفحة تصنيف. الصفحة 1 = الجذر، وما بعدها = /{page}/. */
export function buildCategoryUrl(slug, page = 1) {
	const n = Math.max(1, Math.floor(Number(page) || 1));
	const base = `https://www.hindawi.org/books/categories/${slug}/`;
	return n === 1 ? base : `${base}${n}/`;
}

async function fetchHtml(url) {
	try {
		const viaCrawl4ai = await crawl4aiFetchHtml(url, { timeoutMs: 45000 });
		if (viaCrawl4ai && viaCrawl4ai.html.length >= 200) {
			return { html: viaCrawl4ai.html, finalUrl: viaCrawl4ai.finalUrl };
		}
	} catch {
		/* fallback */
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
		throw makeError('تعذّر الاتصال بمؤسسة هنداوي.', 'crawler_network_error', 0, err);
	}
	if (!res.ok) {
		throw makeError(`هنداوي أرجعت ${res.status} لـ ${url}`, 'crawler_upstream_error', res.status);
	}
	return { html: await res.text(), finalUrl: res.url || url };
}

/**
 * يستخرج معرّفات الكتب من HTML صفحة تصنيف (متين: لا يشترط href).
 * @param {string} html
 * @returns {Array<{ bookId:string, url:string }>}
 */
export function extractBookLinks(html) {
	const out = new Map();
	const re = /\/books\/(\d{4,})(?:\/[^"'\s<>]*)?/gi;
	let m;
	while ((m = re.exec(html))) {
		const bookId = m[1];
		if (!out.has(bookId)) out.set(bookId, `https://www.hindawi.org/books/${bookId}/`);
	}
	return Array.from(out.entries()).map(([bookId, url]) => ({ bookId, url }));
}

/**
 * يكتشف كتباً جديدة داخل تصنيف معيّن (يجمع batchSize كتاباً جديداً عبر صفحات
 * متتالية أو يستهلك maxPagesPerCall).
 *
 * @param {{ slug:string, startPage:number, batchSize:number, maxPagesPerCall:number, knownIds:Set<string> }} args
 * @returns {Promise<{ newBooks:Array<{bookId:string,url:string}>, pagesScanned:number, nextPage:number|null, exhausted:boolean }>}
 */
export async function discoverNewBooksInCategory({
	slug,
	startPage = 1,
	batchSize = 4,
	maxPagesPerCall = 3,
	knownIds = new Set()
}) {
	const collected = new Map();
	let page = Math.max(1, startPage);
	let pagesScanned = 0;
	let nextPage = null;
	let exhausted = false;

	while (pagesScanned < maxPagesPerCall && collected.size < batchSize) {
		if (page > MAX_CATEGORY_PAGES) {
			exhausted = true;
			break;
		}
		let result;
		try {
			result = await fetchHtml(buildCategoryUrl(slug, page));
		} catch {
			pagesScanned++;
			page++;
			continue;
		}
		pagesScanned++;
		const links = extractBookLinks(result.html);
		if (links.length === 0) {
			exhausted = true;
			break;
		}
		for (const link of links) {
			if (knownIds.has(link.bookId)) continue;
			if (collected.has(link.bookId)) continue;
			collected.set(link.bookId, link);
			if (collected.size >= batchSize) break;
		}
		nextPage = page + 1;
		page += 1;
	}

	return {
		newBooks: Array.from(collected.values()),
		pagesScanned,
		nextPage: exhausted ? null : nextPage || page,
		exhausted
	};
}
