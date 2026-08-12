/**
 * fetcher.js — جلب بيانات كتاب من مؤسسة هنداوي (hindawi.org).
 *
 * ╔══════════════════════════════════════════════════════════════════╗
 * ║  لماذا هنداوي آمنة قانونياً:                                      ║
 * ║  مؤسسة هنداوي تنشر كتبها مجّاناً برخصة المشاع الإبداعي (Creative   ║
 * ║  Commons) — رسالتها إتاحة المعرفة العربية للجميع. التوزيع المجّاني  ║
 * ║  داخل تطبيق نبراس متوافق تماماً مع هذه الرخصة ومع سياسة Google     ║
 * ║  Play. لذا نَعُدّ كلّ كتاب هنداوي مصدراً موثوقاً مرخّصاً (CC).      ║
 * ╚══════════════════════════════════════════════════════════════════╝
 *
 * بنية الموقع (تحقّقنا منها):
 *   • صفحة الكتاب:   https://www.hindawi.org/books/{id}/
 *   • ملفّ الـ PDF:  https://downloads.hindawi.org/books/{id}.pdf   (CDN مفتوح)
 *
 * ⚠️ توافق التطبيق: التطبيق يعرض **PDF فقط** عبر syncfusion_pdfviewer.
 *    لذا نبني دائماً رابط PDF ونضع content_type='document'. لا EPUB إطلاقاً.
 */

import { crawl4aiFetchHtml, crawl4aiDownload } from '$lib/server/crawl4aiClient.js';

const USER_AGENT =
	'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
	'(KHTML, like Gecko) Chrome/124.0 Safari/537.36 NebrasDashboard/1.0';

const HOST_ALIASES = ['hindawi.org', 'www.hindawi.org'];

function makeError(message, reason, status = 0, cause = null) {
	const err = /** @type {any} */ (new Error(message));
	err.reason = reason;
	err.status = status;
	if (cause) err.cause = cause;
	return err;
}

/**
 * يحلّل رابط كتاب هنداوي ويستخرج المعرّف الرقميّ.
 * @param {string} input
 * @returns {{ canonicalUrl:string, bookId:string, pdfUrl:string } | null}
 */
export function parseHindawiUrl(input) {
	const raw = String(input || '').trim();
	if (!raw) return null;
	let u;
	try {
		u = new URL(raw);
	} catch {
		return null;
	}
	if (!HOST_ALIASES.includes(u.hostname.toLowerCase())) return null;
	const m = u.pathname.match(/\/books\/(\d+)\/?/);
	if (!m) return null;
	const bookId = m[1];
	return {
		bookId,
		canonicalUrl: `https://www.hindawi.org/books/${bookId}/`,
		pdfUrl: buildPdfUrl(bookId)
	};
}

/** يبني رابط PDF على CDN التنزيل (المسار الموثَّق). */
export function buildPdfUrl(bookId) {
	return `https://downloads.hindawi.org/books/${bookId}.pdf`;
}

// ── HTML helpers ─────────────────────────────────────────────────────

function decodeHtmlEntities(s) {
	return String(s || '')
		.replace(/&amp;/g, '&')
		.replace(/&lt;/g, '<')
		.replace(/&gt;/g, '>')
		.replace(/&quot;/g, '"')
		.replace(/&#39;/g, "'")
		.replace(/&nbsp;/g, ' ')
		.replace(/&#(\d+);/g, (_, c) => String.fromCharCode(Number(c)))
		.replace(/&#x([0-9a-fA-F]+);/g, (_, c) => String.fromCharCode(parseInt(c, 16)));
}

function extractMeta(html, property) {
	const re = new RegExp(
		`<meta[^>]*(?:property|name)=["']${property}["'][^>]*content=["']([^"']+)["']`,
		'i'
	);
	const m = html.match(re);
	if (m) return decodeHtmlEntities(m[1]).trim();
	const reAlt = new RegExp(
		`<meta[^>]*content=["']([^"']+)["'][^>]*(?:property|name)=["']${property}["']`,
		'i'
	);
	const m2 = html.match(reAlt);
	return m2 ? decodeHtmlEntities(m2[1]).trim() : '';
}

function extractTitle(html) {
	const og = extractMeta(html, 'og:title');
	if (og) return og.replace(/\s*\|\s*مؤسسة هنداوي.*$/u, '').trim();
	const m = html.match(/<title[^>]*>([\s\S]*?)<\/title>/i);
	if (m) return decodeHtmlEntities(m[1]).replace(/\s*\|\s*مؤسسة هنداوي.*$/u, '').trim();
	return '';
}

function extractAuthor(html) {
	const meta =
		extractMeta(html, 'book:author') ||
		extractMeta(html, 'author') ||
		extractMeta(html, 'article:author');
	if (meta) return meta;
	// نمط هنداوي: رابط المؤلف داخل الصفحة
	const m = html.match(/(?:تأليف|المؤلف)\s*[:\-]?\s*<a[^>]*>([^<]+)<\/a>/u);
	return m ? decodeHtmlEntities(m[1]).trim() : '';
}

/**
 * يستخرج معلومات ترخيص الكتاب من صفحة هنداوي. هنداوي تنشر كلّ كتبها تحت
 * Creative Commons، لكنّ تحديد المتغيِّر (CC-BY / CC-BY-SA / CC-BY-NC-ND…)
 * يفيد للإسناد الدقيق والاحتفاظ بإثبات لكلّ كتاب على حدة (defense-in-depth
 * إذا نُشر يوماً كتاب بدون CC).
 *
 * يعيد: { matched, name, url, confidence }
 *   • confidence='high' لو وجدنا رابط CC صريحاً في الصفحة.
 *   • confidence='medium' لو وجدنا نصّاً يذكر "creative commons" بلا رابط.
 *   • confidence='low' fallback لسياسة الناشر العامّة.
 *
 * إذا وجدنا رخصة **غير** CC صراحةً (مثل "all rights reserved") نُعيد
 * matched='rejected' فيتمّ تجاهل الكتاب.
 */
function extractLicenseInfo(html) {
	const lower = String(html || '').toLowerCase();

	// 1) رابط Creative Commons صريح في الصفحة أو الـ meta tags.
	const ccLink = html.match(
		/https?:\/\/creativecommons\.org\/(licenses\/[a-z\-]+\/[0-9.]+|publicdomain\/[a-z]+\/[0-9.]+)\/?/i
	);
	if (ccLink) {
		const url = ccLink[0];
		// استخرج المتغيّر من المسار: licenses/by-sa/4.0 → CC BY-SA 4.0
		const m = url.match(/licenses\/([a-z\-]+)\/([0-9.]+)/i)
			|| url.match(/publicdomain\/([a-z]+)\/([0-9.]+)/i);
		const name = m
			? `CC ${m[1].toUpperCase().replace(/-/g, '-')} ${m[2]}`
			: 'Creative Commons';
		return { matched: 'verified_open_license', name, url, confidence: 'high' };
	}

	// 2) رفض صريح لو ظهرت "all rights reserved" (نادر لكن دفاعيّ).
	if (/all rights reserved|كل الحقوق محفوظة/i.test(lower)) {
		return {
			matched: 'rejected',
			name: 'all_rights_reserved',
			url: '',
			confidence: 'high'
		};
	}

	// 3) نصّ يذكر "creative commons" بلا رابط مباشر.
	if (/creative commons|المشاع الإبداعي/i.test(lower)) {
		return {
			matched: 'verified_open_license',
			name: 'Creative Commons (variant unspecified)',
			url: 'https://creativecommons.org/',
			confidence: 'medium'
		};
	}

	// 4) Fallback لسياسة الناشر (هنداوي = CC).
	return {
		matched: 'verified_open_license',
		name: 'CC (hindawi publisher policy)',
		url: 'https://www.hindawi.org/',
		confidence: 'low'
	};
}

function extractCategoryHints(html) {
	const hints = [];
	const kw = extractMeta(html, 'keywords');
	if (kw) for (const part of kw.split(/[,،]/)) { const t = part.trim(); if (t) hints.push(t); }
	// breadcrumbs
	const bc = html.match(/<(?:ol|ul)[^>]*breadcrumb[^>]*>([\s\S]*?)<\/(?:ol|ul)>/i);
	if (bc) {
		const itemRe = />([^<>]{2,60})</g;
		let im;
		while ((im = itemRe.exec(bc[1]))) {
			const t = decodeHtmlEntities(im[1]).trim();
			if (t && !/^(الرئيسية|home|الكتب|كتب)$/i.test(t)) hints.push(t);
		}
	}
	return [...new Set(hints.filter(Boolean))].slice(0, 12);
}

/**
 * يجلب HTML صفحة الكتاب. هنداوي قد تحجب طلبات الخوادم (403)، لذا نُفضّل
 * crawl4ai (متصفّح حقيقي) ثمّ نسقط لـ fetch عاديّ.
 * @param {string} url
 */
async function fetchHtml(url) {
	try {
		const viaCrawl4ai = await crawl4aiFetchHtml(url, { timeoutMs: 45000 });
		if (viaCrawl4ai && viaCrawl4ai.html.length >= 200) {
			return { html: viaCrawl4ai.html, finalUrl: viaCrawl4ai.finalUrl };
		}
	} catch {
		// نسقط لـ fetch
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
		throw makeError('تعذّر الاتصال بمؤسسة هنداوي.', 'network_error', 0, err);
	}
	if (!res.ok) {
		throw makeError(`هنداوي أرجعت ${res.status} للرابط: ${url}`, 'upstream_error', res.status);
	}
	const html = await res.text();
	if (!html || html.length < 200) {
		throw makeError('استجابة فارغة من هنداوي.', 'empty_response', res.status);
	}
	return { html, finalUrl: res.url || url };
}

/**
 * الواجهة الرئيسيّة — metadata كاملة لكتاب هنداوي (PDF فقط).
 * @param {string} pageUrl
 */
export async function fetchBookMetadata(pageUrl) {
	const parsed = parseHindawiUrl(pageUrl);
	if (!parsed) {
		throw makeError('الرابط لا ينتمي إلى hindawi.org/books/{id}.', 'invalid_url', 400);
	}

	const { html, finalUrl } = await fetchHtml(parsed.canonicalUrl);
	const title = extractTitle(html);
	if (!title) {
		throw makeError('تعذّر استخراج عنوان الكتاب من صفحة هنداوي.', 'no_title', 422);
	}

	// فحص فعليّ لترخيص الكتاب من صفحة هنداوي نفسها (defense-in-depth).
	const licenseInfo = extractLicenseInfo(html);
	if (licenseInfo.matched === 'rejected') {
		throw makeError(
			`الكتاب يحمل ترخيصاً غير مفتوح (${licenseInfo.name}).`,
			'license_rejected',
			451
		);
	}

	return {
		title,
		description: extractMeta(html, 'og:description') || extractMeta(html, 'description') || '',
		author: extractAuthor(html),
		thumbnail: extractMeta(html, 'og:image') || '',
		categoryHints: extractCategoryHints(html),
		// PDF حصراً (توافق قارئ التطبيق).
		fileUrl: parsed.pdfUrl,
		fileType: 'application/pdf',
		license: {
			matched: licenseInfo.matched,
			name: licenseInfo.name,
			url: licenseInfo.url,
			confidence: licenseInfo.confidence,
			reason: 'hindawi_trusted_publisher',
			tier: 'verified'
		},
		source: {
			url: parsed.canonicalUrl,
			finalUrl,
			bookId: parsed.bookId,
			provider: 'hindawi',
			fetchedAt: new Date().toISOString()
		}
	};
}

/**
 * تنزيل ملفّ PDF من CDN هنداوي (مفتوح عادةً). fetch عاديّ أوّلاً ثمّ crawl4ai.
 * @param {string} fileUrl
 * @param {{ refererUrl?:string|null }} [opts]
 */
export async function downloadBookFile(fileUrl, opts = {}) {
	if (!fileUrl) throw makeError('لا يوجد رابط ملف للتنزيل.', 'no_file_url', 400);
	const refererUrl = opts?.refererUrl || null;

	// 1) fetch مباشر من CDN التنزيل (downloads.hindawi.org مفتوح غالباً).
	let res = null;
	try {
		res = await fetch(fileUrl, {
			headers: {
				'User-Agent': USER_AGENT,
				Accept: 'application/pdf,*/*',
				...(refererUrl ? { Referer: refererUrl } : {})
			},
			redirect: 'follow'
		});
	} catch {
		res = null;
	}
	if (res && res.ok) {
		const arrayBuf = await res.arrayBuffer();
		const buffer = Buffer.from(arrayBuf);
		if (buffer.byteLength > 0 && looksLikePdf(buffer)) {
			return {
				buffer,
				contentType: res.headers.get('content-type') || 'application/pdf',
				filename: filenameFromUrl(fileUrl),
				size: buffer.byteLength
			};
		}
	}

	// 2) احتياط: عبر crawl4ai (متصفّح حقيقي) إن حجب الـ CDN الطلب المباشر.
	try {
		const viaCrawl4ai = await crawl4aiDownload(fileUrl, { referer: refererUrl, timeoutMs: 90000 });
		if (viaCrawl4ai?.buffer && viaCrawl4ai.buffer.byteLength > 0 && looksLikePdf(viaCrawl4ai.buffer)) {
			return {
				buffer: viaCrawl4ai.buffer,
				contentType: viaCrawl4ai.contentType || 'application/pdf',
				filename: viaCrawl4ai.filename || filenameFromUrl(fileUrl),
				size: viaCrawl4ai.size
			};
		}
	} catch {
		// نسقط للخطأ النهائي أدناه
	}

	throw makeError(
		`تعذّر تنزيل PDF من هنداوي (${fileUrl}).`,
		'download_failed',
		res?.status || 502
	);
}

/** يتحقّق من توقيع PDF (magic bytes %PDF) لمنع حفظ صفحات HTML خطأً. */
function looksLikePdf(buffer) {
	if (!buffer || buffer.byteLength < 5) return false;
	return buffer.slice(0, 5).toString('latin1') === '%PDF-';
}

function filenameFromUrl(fileUrl) {
	try {
		return decodeURIComponent(new URL(fileUrl).pathname.split('/').pop() || 'book.pdf');
	} catch {
		return 'book.pdf';
	}
}
