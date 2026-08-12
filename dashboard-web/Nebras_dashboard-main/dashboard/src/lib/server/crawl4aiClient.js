import { env } from '$env/dynamic/private';

/**
 * @returns {string}
 */
function baseUrl() {
	return String(env.CRAWL4AI_SERVICE_URL || '')
		.trim()
		.replace(/\/+$/, '');
}

/**
 * @returns {boolean}
 */
export function crawl4aiConfigured() {
	return Boolean(baseUrl());
}

/**
 * Forward a request to the Crawl4AI sidecar (server-side only).
 * @param {string} path - e.g. `/status`
 * @param {RequestInit} [init]
 * @returns {Promise<Response|null>} null if not configured
 */
export async function crawl4aiFetch(path, init = {}) {
	const base = baseUrl();
	if (!base) return null;

	const secret = String(env.CRAWL4AI_SERVICE_SECRET || '').trim();
	const url = `${base}${path.startsWith('/') ? path : `/${path}`}`;

	/** @type {Headers} */
	const headers = new Headers(/** @type {any} */ (init.headers || {}));
	if (secret) headers.set('X-Crawl4AI-Secret', secret);

	const timeoutMs = Number(env.CRAWL4AI_FETCH_TIMEOUT_MS || '120000') || 120000;
	const ac = new AbortController();
	const timer = setTimeout(() => ac.abort(), timeoutMs);

	try {
		return await fetch(url, {
			...init,
			headers,
			signal: ac.signal
		});
	} finally {
		clearTimeout(timer);
	}
}

/**
 * Health probe for the crawl4ai sidecar. Never throws — returns a verdict
 * the dashboard can show directly.
 * @returns {Promise<{ configured: boolean, reachable: boolean, status: number|null, detail: string }>}
 */
export async function crawl4aiHealth() {
	if (!crawl4aiConfigured()) {
		return { configured: false, reachable: false, status: null, detail: 'CRAWL4AI_SERVICE_URL غير مضبوط في بيئة الخادم.' };
	}
	try {
		const res = await crawl4aiFetch('/health', { method: 'GET' });
		if (!res) return { configured: true, reachable: false, status: null, detail: 'لا استجابة (غير مضبوط؟).' };
		const text = await res.text().catch(() => '');
		return {
			configured: true,
			reachable: res.ok,
			status: res.status,
			detail: res.ok ? `الخدمة تعمل: ${text.slice(0, 120)}` : `حالة ${res.status}: ${text.slice(0, 160)}`
		};
	} catch (e) {
		return { configured: true, reachable: false, status: null, detail: `تعذّر الوصول: ${e?.message || String(e)}` };
	}
}

/**
 * Synchronously fetch a page's rendered HTML through the crawl4ai sidecar
 * (real browser → defeats JS/Cloudflare challenges). Returns null when the
 * sidecar is not configured so callers can fall back to plain fetch/Puppeteer.
 *
 * @param {string} pageUrl
 * @param {{ timeoutMs?: number }} [opts]
 * @returns {Promise<{ html: string, finalUrl: string } | null>}
 */
export async function crawl4aiFetchHtml(pageUrl, opts = {}) {
	if (!crawl4aiConfigured()) return null;
	const timeoutMs = Math.max(5000, Math.min(180000, Number(opts.timeoutMs) || 60000));
	const res = await crawl4aiFetch('/fetch', {
		method: 'POST',
		headers: { 'Content-Type': 'application/json' },
		body: JSON.stringify({ url: pageUrl, timeout_ms: timeoutMs })
	});
	if (!res) return null;
	if (!res.ok) {
		const text = await res.text().catch(() => '');
		throw Object.assign(new Error(`crawl4ai /fetch ${res.status}: ${text}`), {
			reason: 'crawl4ai_fetch_failed',
			status: res.status
		});
	}
	const data = await res.json().catch(() => null);
	if (!data || data.ok !== true || !data.html) {
		throw Object.assign(
			new Error(`crawl4ai /fetch returned no html: ${data?.error || 'unknown'}`),
			{ reason: data?.error || 'crawl4ai_fetch_empty', status: 502 }
		);
	}
	return { html: String(data.html), finalUrl: String(data.final_url || pageUrl) };
}

/**
 * Download a binary file (PDF/audio/...) through the crawl4ai sidecar's real
 * browser context, establishing Cloudflare clearance via the referer page.
 * Returns null when the sidecar is not configured.
 *
 * @param {string} fileUrl
 * @param {{ referer?: string|null, timeoutMs?: number }} [opts]
 * @returns {Promise<{ buffer: Buffer, contentType: string, filename: string, size: number } | null>}
 */
export async function crawl4aiDownload(fileUrl, opts = {}) {
	if (!crawl4aiConfigured()) return null;
	const timeoutMs = Math.max(5000, Math.min(180000, Number(opts.timeoutMs) || 90000));
	const res = await crawl4aiFetch('/download', {
		method: 'POST',
		headers: { 'Content-Type': 'application/json' },
		body: JSON.stringify({
			url: fileUrl,
			referer: opts.referer || null,
			timeout_ms: timeoutMs
		})
	});
	if (!res) return null;
	if (!res.ok) {
		const text = await res.text().catch(() => '');
		throw Object.assign(new Error(`crawl4ai /download ${res.status}: ${text}`), {
			reason: 'crawl4ai_download_failed',
			status: res.status
		});
	}
	const data = await res.json().catch(() => null);
	if (!data || data.ok !== true || !data.base64) {
		throw Object.assign(
			new Error(`crawl4ai /download returned no data: ${data?.error || 'unknown'}`),
			{ reason: data?.error || 'crawl4ai_download_empty', status: data?.status || 502 }
		);
	}
	const buffer = Buffer.from(String(data.base64), 'base64');
	return {
		buffer,
		contentType: String(data.content_type || 'application/octet-stream'),
		filename: String(data.filename || ''),
		size: Number(data.size) || buffer.byteLength
	};
}
