/**
 * search.js — بحث Internet Archive عبر Scraping API الرسمي.
 *
 * نختار Scraping API على حساب Advanced Search لأنّ:
 *   1) لا حدّ صلب عند 10,000 — يدعم استخراج مجموعات كاملة عبر cursor.
 *   2) يضمن **عدم تكرار** النتائج عبر pagination — مهمّ لأنّ المستخدم
 *      اشترط: "كلّ تصنيف يجلب محتواه بالكامل لا جزءًا منه".
 *   3) JSON نظيف بدون JS/CSS — أخفّ على الذاكرة.
 *
 * المرجع: https://archive.org/services/search/v1/scrape
 *
 * هذه الوحدة:
 *   - تبني استعلام Lucene من seed (mediatype/collection/language/q free)
 *   - تنفّذ الجولة الواحدة (صفحة واحدة من cursor)
 *   - تُرجع identifiers + cursor التالي + إشارة "exhausted" عند نهاية النتائج
 *
 * لا تكتب أيّ شيء في DB. الكاتب الوحيد هو engine.js.
 */

const SCRAPE_ENDPOINT = 'https://archive.org/services/search/v1/scrape';
// User-Agent مع contact email — توصية رسميّة من Internet Archive
// (https://archive.org/developers/index-apis.html). يساعد فريق الـ Archive
// على التواصل إن سبّب bot ضغطاً عاليّاً.
const USER_AGENT =
	'NebrasDashboard/1.0 (https://nebras.app; contact: dashboard@nebras.app) NebrasIAEngine';

/**
 * Sleep utility (لتطبيق backoff).
 * @param {number} ms
 */
function sleep(ms) {
	return new Promise((r) => setTimeout(r, ms));
}

/**
 * fetch مع retry تلقائي على 429/503/504 — backoff تصاعدي حسب توصية IA
 * (https://archive.org/developers/index-apis.html: "double wait time on 503").
 *
 * @param {string} url
 * @param {RequestInit} init
 * @param {{ maxRetries?: number, baseDelayMs?: number, label?: string }} [opts]
 */
async function fetchWithRetry(url, init, opts = {}) {
	const maxRetries = Math.max(0, Math.min(5, opts.maxRetries ?? 3));
	const baseDelay = Math.max(200, opts.baseDelayMs ?? 800);
	let lastError = null;

	for (let attempt = 0; attempt <= maxRetries; attempt += 1) {
		try {
			const res = await fetch(url, init);
			// 429 (too many requests) / 503 (service unavailable) / 504 (gateway timeout)
			if (res.status === 429 || res.status === 503 || res.status === 504) {
				if (attempt === maxRetries) return res;
				const retryAfterHeader = Number(res.headers.get('retry-after')) || 0;
				const wait = retryAfterHeader > 0
					? retryAfterHeader * 1000
					: baseDelay * Math.pow(2, attempt);
				await sleep(Math.min(wait, 30_000));
				continue;
			}
			return res;
		} catch (err) {
			lastError = err;
			if (attempt === maxRetries) throw err;
			await sleep(baseDelay * Math.pow(2, attempt));
		}
	}
	if (lastError) throw lastError;
	throw new Error(`fetchWithRetry exhausted retries for ${url}`);
}

/**
 * الحقول التي نطلب IA إرجاعها — قاصرة على ما يحتاجه المعالج التالي،
 * لتخفيف الـ payload.
 */
const DEFAULT_FIELDS = Object.freeze([
	'identifier',
	'title',
	'creator',
	'mediatype',
	'collection',
	'language',
	'description',
	'subject',
	'date',
	'licenseurl',
	'rights'
]);

/**
 * أنواع وسائط IA المسموح بحثها (نوع نبراس → IA mediatype).
 */
const MEDIATYPE_MAP = Object.freeze({
	document: 'texts',
	audio: 'audio',
	video: 'movies'
});

/** يضيّق نتائج IA إلى تراخيص آمنة للنشر في التطبيق (لا NC/ND). */
const LICENSE_SAFE_LUCENE = Object.freeze(
	'(licenseurl:*publicdomain* OR licenseurl:*creativecommons.org/publicdomain* OR licenseurl:*creativecommons.org/licenses/by/* OR licenseurl:*creativecommons.org/licenses/by-sa/*)'
);

/**
 * يبني سلسلة Lucene query من قطع نظيفة. النمط:
 *   (q) AND mediatype:(texts OR audio OR movies) AND language:Arabic AND collection:(a OR b)
 *
 * @param {{
 *   q?: string,
 *   nebrasTypes?: Array<'document'|'audio'|'video'>,
 *   languages?: string[],
 *   collections?: string[],
 *   creators?: string[],
 *   licenseSafe?: boolean
 * }} parts
 * @returns {string}
 */
export function buildLuceneQuery(parts = {}) {
	const segments = [];

	const free = String(parts.q || '').trim();
	if (free) segments.push(`(${escapeLuceneFree(free)})`);

	const mediatypes = (parts.nebrasTypes || [])
		.map((t) => MEDIATYPE_MAP[t])
		.filter(Boolean);
	if (mediatypes.length > 0) {
		segments.push(`mediatype:(${mediatypes.join(' OR ')})`);
	}

	const langs = (parts.languages || []).map(quoteField).filter(Boolean);
	if (langs.length > 0) segments.push(`language:(${langs.join(' OR ')})`);

	const cols = (parts.collections || []).map(quoteField).filter(Boolean);
	if (cols.length > 0) segments.push(`collection:(${cols.join(' OR ')})`);

	const creators = (parts.creators || []).map(quoteField).filter(Boolean);
	if (creators.length > 0) segments.push(`creator:(${creators.join(' OR ')})`);

	if (parts.licenseSafe !== false) segments.push(LICENSE_SAFE_LUCENE);

	return segments.join(' AND ');
}

/**
 * يُهرّب نصاً حرّاً قبل وضعه في عبارة Lucene. لا نسمح بحروف لها معنى
 * تركيبي (`:`, `(`, `)`, `[`, `]`) أن تسرّب من المستخدم.
 */
function escapeLuceneFree(s) {
	return String(s)
		.replace(/[\\+\-!(){}\[\]^"~*?:\\/]/g, ' ')
		.replace(/\s+/g, ' ')
		.trim();
}

function quoteField(v) {
	const s = String(v || '').trim();
	if (!s) return '';
	if (/[\s"]/.test(s)) return `"${s.replace(/"/g, '\\"')}"`;
	return s;
}

/**
 * طلب صفحة واحدة من Scraping API.
 *
 * @param {{
 *   query: string,
 *   count?: number,        افتراضي 100 (الحدّ الأقصى لكلّ نداء = 10000، لكنّنا نُبقيه صغيراً للسيطرة على الذاكرة).
 *   cursor?: string,       null على أوّل نداء
 *   fields?: string[],
 *   sorts?: string[]       افتراضي ['publicdate desc']
 * }} args
 * @returns {Promise<{
 *   items: Array<Record<string, any>>,
 *   nextCursor: string|null,
 *   total: number,
 *   exhausted: boolean
 * }>}
 */
export async function scrapeOnePage({
	query,
	count = 100,
	cursor = null,
	fields = DEFAULT_FIELDS,
	sorts = ['publicdate desc']
}) {
	if (!String(query || '').trim()) {
		throw Object.assign(new Error('query فارغ.'), { reason: 'empty_query', status: 400 });
	}

	const params = new URLSearchParams();
	params.set('q', query);
	// IA Scraping API يفرض حداً أدنى 100 (وإلا HTTP 400).
	params.set('count', String(Math.max(100, Math.min(1000, Number(count) || 100))));
	params.set('fields', (fields || DEFAULT_FIELDS).join(','));
	for (const s of sorts || []) params.append('sorts', s);
	if (cursor) params.set('cursor', cursor);

	const url = `${SCRAPE_ENDPOINT}?${params.toString()}`;
	const res = await fetchWithRetry(
		url,
		{
			method: 'GET',
			headers: { 'User-Agent': USER_AGENT, Accept: 'application/json' },
			redirect: 'follow'
		},
		{ label: 'ia_scrape' }
	);

	if (!res.ok) {
		const body = await res.text().catch(() => '');
		throw Object.assign(
			new Error(`IA scrape HTTP ${res.status}: ${body.slice(0, 240)}`),
			{ reason: 'scrape_http_error', status: res.status }
		);
	}

	let json;
	try {
		json = await res.json();
	} catch (e) {
		throw Object.assign(new Error('IA scrape: استجابة ليست JSON.'), {
			reason: 'scrape_invalid_json',
			status: 502
		});
	}

	const items = Array.isArray(json?.items) ? json.items : [];
	const nextCursor = typeof json?.cursor === 'string' && json.cursor ? json.cursor : null;
	const total = Number(json?.total || 0);

	return {
		items,
		nextCursor,
		total,
		// IA يُرسل cursor مفقوداً عند نهاية النتائج (أو يُرسل items فارغة).
		exhausted: !nextCursor || items.length === 0
	};
}

/**
 * يطلب metadata الكامل لعنصر IA (يشمل قائمة الملفّات).
 * https://archive.org/metadata/{identifier}
 *
 * @param {string} identifier
 * @returns {Promise<{
 *   metadata: Record<string, any>,
 *   files: Array<Record<string, any>>,
 *   server: string,
 *   dir: string
 * }>}
 */
export async function fetchItemMetadata(identifier) {
	const id = String(identifier || '').trim();
	if (!id) throw Object.assign(new Error('identifier فارغ.'), { reason: 'empty_identifier' });

	const url = `https://archive.org/metadata/${encodeURIComponent(id)}`;
	const res = await fetchWithRetry(
		url,
		{
			headers: { 'User-Agent': USER_AGENT, Accept: 'application/json' },
			redirect: 'follow'
		},
		{ label: 'ia_metadata' }
	);
	if (!res.ok) {
		throw Object.assign(new Error(`IA metadata HTTP ${res.status}`), {
			reason: 'metadata_http_error',
			status: res.status
		});
	}
	const json = await res.json();
	return {
		metadata: json?.metadata || {},
		files: Array.isArray(json?.files) ? json.files : [],
		server: String(json?.server || 'archive.org'),
		dir: String(json?.dir || `/${id}`)
	};
}

/**
 * يبني رابط التنزيل المباشر لملفّ ضمن عنصر IA.
 * نستعمل المسار الإعتيادي: https://archive.org/download/{identifier}/{filename}
 * (الـ server المختصّ يخدّمه بـ 302 إن لزم).
 *
 * @param {string} identifier
 * @param {string} filename
 * @returns {string}
 */
export function buildDownloadUrl(identifier, filename) {
	const id = encodeURIComponent(String(identifier || ''));
	const fn = String(filename || '')
		.split('/')
		.map((seg) => encodeURIComponent(seg))
		.join('/');
	return `https://archive.org/download/${id}/${fn}`;
}
