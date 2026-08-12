/**
 * scraperProxy.js — وسيط تجاوز Cloudflare عبر خدمة API خارجيّة (اختياريّة).
 *
 * لماذا؟ مواقع مثل noor-book محميّة بـ Cloudflare؛ الخادم العاديّ يُحجب.
 * بدل تشغيل متصفّح (crawl4ai على Cloud Run، يحتاج نشراً)، يكفي **مفتاح API**
 * من أي خدمة scraping (ScraperAPI / ScrapingBee / ZenRows…) تُلصق في Vercel
 * — بلا أوامر ولا تسجيل دخول CLI.
 *
 * الإعداد (متغيّر بيئة واحد على الأقلّ):
 *   SCRAPER_API_URL_TEMPLATE = "https://api.scraperapi.com/?api_key=KEY&render=true&url={url}"
 *   (اختياريّ) SCRAPER_API_DOWNLOAD_TEMPLATE للملفّات الثنائيّة (render=false غالباً).
 * يُستبدل {url} بعنوان الهدف مُرمَّزاً. إن غاب القالب، الدوال تُعيد null
 * فيُكمل المحرّك ببدائله (crawl4ai/fetch) بأمان.
 */
import { env } from '$env/dynamic/private';

function htmlTemplate() {
	return String(env.SCRAPER_API_URL_TEMPLATE || '').trim();
}
function downloadTemplate() {
	return String(env.SCRAPER_API_DOWNLOAD_TEMPLATE || env.SCRAPER_API_URL_TEMPLATE || '').trim();
}

/** @returns {boolean} */
export function scraperConfigured() {
	return Boolean(htmlTemplate());
}

function buildUrl(template, targetUrl) {
	const enc = encodeURIComponent(targetUrl);
	if (template.includes('{url}')) return template.replaceAll('{url}', enc);
	// لو لم يحوِ القالب {url}، نُلحق url=<target> (نمط ScraperAPI الشائع).
	const sep = template.includes('?') ? '&' : '?';
	return `${template}${sep}url=${enc}`;
}

const TIMEOUT_MS = Number(env.SCRAPER_API_TIMEOUT_MS || '90000') || 90000;

async function withTimeout(promiseFactory) {
	const ac = new AbortController();
	const timer = setTimeout(() => ac.abort(), TIMEOUT_MS);
	try {
		return await promiseFactory(ac.signal);
	} finally {
		clearTimeout(timer);
	}
}

/**
 * يجلب HTML صفحة عبر الوسيط (يُصيّر JS ويجتاز Cloudflare حسب الخدمة).
 * @param {string} targetUrl
 * @returns {Promise<{ html:string, finalUrl:string } | null>} null إن لم يُضبط الوسيط
 */
export async function scraperFetchHtml(targetUrl) {
	const tpl = htmlTemplate();
	if (!tpl) return null;
	const url = buildUrl(tpl, targetUrl);
	const res = await withTimeout((signal) => fetch(url, { signal, redirect: 'follow' }));
	if (!res.ok) {
		throw Object.assign(new Error(`scraper /html ${res.status}`), {
			reason: 'scraper_fetch_failed',
			status: res.status
		});
	}
	const html = await res.text();
	if (!html || html.length < 100) {
		throw Object.assign(new Error('scraper أعاد HTML فارغاً.'), {
			reason: 'scraper_empty',
			status: 502
		});
	}
	return { html, finalUrl: targetUrl };
}

/**
 * ينزّل ملفّاً ثنائياً (PDF) عبر الوسيط.
 * @param {string} targetUrl
 * @returns {Promise<{ buffer:Buffer, contentType:string } | null>} null إن لم يُضبط الوسيط
 */
export async function scraperDownloadBuffer(targetUrl) {
	const tpl = downloadTemplate();
	if (!tpl) return null;
	const url = buildUrl(tpl, targetUrl);
	const res = await withTimeout((signal) => fetch(url, { signal, redirect: 'follow' }));
	if (!res.ok) {
		throw Object.assign(new Error(`scraper /download ${res.status}`), {
			reason: 'scraper_download_failed',
			status: res.status
		});
	}
	const buffer = Buffer.from(await res.arrayBuffer());
	if (!buffer || buffer.byteLength === 0) {
		throw Object.assign(new Error('scraper أعاد ملفّاً فارغاً.'), {
			reason: 'scraper_download_empty',
			status: 502
		});
	}
	return { buffer, contentType: res.headers.get('content-type') || 'application/octet-stream' };
}
