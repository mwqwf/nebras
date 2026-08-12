/**
 * noor-ci-ingest.mjs — مُشغِّل الجلب الآليّ لمكتبة نور داخل GitHub Actions.
 *
 * لماذا هنا؟ استخراج رابط تنزيل نور يحتاج **متصفّحاً حقيقياً** (جدار نور يبني
 * الرابط عبر JS بعد مصافحة تحقّق). Vercel/serverless لا يشغّل متصفّحاً، لكن
 * GitHub Actions يشغّله مجّاناً. فنُقسّم العمل:
 *   • هذا المُشغِّل (CI + Puppeteer): يزحف البذور، يفتح كلّ كتاب جديد، يستدعي
 *     دالّة الموقع نفسها go_gownload() فيظهر رابط internal_download العامّ،
 *     ويقرأ الميتاداتا (og:*)، ثمّ يرسلها إلى الخادم.
 *   • الخادم (Vercel، endpoint /api/cron/noor-library-ingest): يجلب البايتات
 *     بـ fetch عاديّ (الرابط عامّ)، يصنّف محليّاً بلا AI، يرفع لتخزين نبراس،
 *     ويكتب Firestore — بإعادة استخدام مسار المحرّك ذاته.
 *
 * لا يحتاج أيّ سرّ جديد: يستعمل CRON_SECRET إن وُجد (وإلا يعمل مفتوحاً مثل بقية
 * مسارات الـ cron). الكتب «المحفوظة/متابعة النشر» تُستبعَد طبيعياً: إن لم يظهر
 * رابط internal_download فالكتاب غير عامّ ⇒ يُتخطّى.
 *
 * متغيّرات البيئة:
 *   VERCEL_BASE     قاعدة عنوان اللوحة (افتراضي https://nebras-dashboard-main.vercel.app)
 *   CRON_SECRET     (اختياري) للمصادقة على /ingest
 *   NOOR_MAX_BOOKS  حدّ الكتب لكلّ تشغيل (افتراضي 12)
 *   NOOR_MAX_MS     ميزانية زمنيّة إجماليّة بالمللي (افتراضي 900000 = 15د)
 */

import puppeteerExtra from 'puppeteer-extra';
import Stealth from 'puppeteer-extra-plugin-stealth';
import { INGEST_FROZEN } from '../src/lib/server/ingestFreeze.js';

puppeteerExtra.use(Stealth());

// ❄️ مُجمَّد (2026-07-23): جلب نور مُوقَف نهائياً بطلب المالك. نخرج فوراً قبل
//    تشغيل المتصفّح أو ضرب أيّ منفذ. لإعادة التفعيل: اجعل INGEST_FROZEN=false.
if (INGEST_FROZEN) {
	console.log('❄️ INGEST_FROZEN=true — جلب نور مُجمّد. خروج دون أيّ جلب.');
	process.exit(0);
}

const BASE = String(process.env.VERCEL_BASE || 'https://nebras-dashboard-main.vercel.app').replace(/\/+$/, '');
const CRON_SECRET = String(process.env.CRON_SECRET || '').trim();
const MAX_BOOKS = Math.max(1, Number(process.env.NOOR_MAX_BOOKS || 30));
const MAX_MS = Math.max(60000, Number(process.env.NOOR_MAX_MS || 2400000));
const UA =
	'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

const FALLBACK_SEEDS = [
	'https://www.noor-book.com/en/latest?landing=false',
	'https://www.noor-book.com/en/popular_all_days?landing=false',
	'https://www.noor-book.com/category/روايات-عالمية',
	'https://www.noor-book.com/category/كتب-في-التاريخ',
	'https://www.noor-book.com/category/كتب-علم-النفس',
	'https://www.noor-book.com/category/كتب-العلوم'
];

function authHeaders(extra = {}) {
	return {
		'User-Agent': 'NebrasNoorCI/1.0',
		...(CRON_SECRET ? { Authorization: `Bearer ${CRON_SECRET}` } : {}),
		...extra
	};
}

const NON_BOOK = [
	/حقوق.?النشر/,
	/سياسة|الخصوصية|privacy|policy/i,
	/اتصل|تواصل|contact|about|من-نحن/i,
	/شروط|terms|اتفاقية/i,
	/تسجيل|login|register|signup/i
];
function isLikelyBookSlug(slug) {
	const s = decodeURIComponent(String(slug || ''));
	if (!s) return false;
	return !NON_BOOK.some((re) => re.test(s));
}

/** استخراج روابط الكتب (/ebook-<slug>) من HTML صفحة قائمة — نفس منطق crawler.js. */
function extractBookLinks(html, baseUrl) {
	const out = new Map();
	const add = (raw) => {
		try {
			const abs = new URL(raw, baseUrl).toString();
			const slug = decodeURIComponent(abs.split('/').filter(Boolean).pop() || '');
			if (slug && isLikelyBookSlug(slug) && !out.has(slug)) out.set(slug, abs);
		} catch {
			/* ignore */
		}
	};
	const patterns = [
		/href=["']([^"']*\/(?:[a-z]{2}\/)?ebook-[^"'?#]+)["']/gi,
		/href=["']([^"']*\/book\/review\/[^"'?#]+)["']/gi
	];
	for (const re of patterns) {
		let m;
		while ((m = re.exec(html))) add(m[1]);
	}
	return [...out.entries()].map(([bookId, url]) => ({ bookId, url }));
}

async function fetchText(url) {
	const res = await fetch(url, {
		headers: { 'User-Agent': UA, 'Accept-Language': 'ar,en;q=0.7' },
		redirect: 'follow'
	});
	if (!res.ok) throw new Error(`GET ${url} → ${res.status}`);
	return res.text();
}

function looksLikeCf(html) {
	const h = String(html || '').toLowerCase();
	return (
		h.length < 200 ||
		h.includes('just a moment') ||
		h.includes('challenge-platform') ||
		h.includes('cf-browser-verification') ||
		h.includes('checking your browser')
	);
}

/**
 * يجلب HTML صفحة قائمة عبر المتصفّح الحقيقي (يجتاز Cloudflare). عناوين
 * GitHub Actions (مراكز بيانات) يحجبها Cloudflare على fetch العاديّ بـ403،
 * فلا بدّ من المتصفّح حتى لصفحات القوائم لا التنزيل فقط.
 */
async function fetchListingHtmlViaBrowser(browser, url) {
	const page = await browser.newPage();
	try {
		await page.setUserAgent(UA);
		await page.setExtraHTTPHeaders({ 'Accept-Language': 'ar-EG,ar;q=0.9,en;q=0.7' });
		await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });
		for (let i = 0; i < 8; i++) {
			const html = await page.content().catch(() => '');
			if (!looksLikeCf(html)) return html;
			await new Promise((r) => setTimeout(r, 2000));
		}
		return await page.content().catch(() => '');
	} finally {
		await page.close().catch(() => {});
	}
}

/** يجمع مرشّحين جدداً من البذور عبر المتصفّح (يجتاز Cloudflare). */
async function collectCandidatesViaBrowser(browser, seeds, known, limit) {
	const seen = new Set();
	const candidates = [];
	for (const seed of seeds) {
		if (candidates.length >= limit) break;
		let html;
		try {
			html = await fetchListingHtmlViaBrowser(browser, seed);
		} catch (e) {
			console.log(`  ⚠ seed failed: ${seed} — ${e.message}`);
			continue;
		}
		let added = 0;
		for (const link of extractBookLinks(html, seed)) {
			if (known.has(link.bookId) || seen.has(link.bookId)) continue;
			seen.add(link.bookId);
			candidates.push(link);
			added++;
			if (candidates.length >= limit) break;
		}
		console.log(`  • seed +${added} (total ${candidates.length}) ${seed.split('/').pop()}`);
	}
	return candidates;
}

/**
 * يفتح صفحة كتاب بمتصفّح حقيقي، يستدعي go_gownload، يستخرج رابط
 * internal_download، **ثمّ يُنزّل البايتات داخل جلسة المتصفّح نفسها**
 * (fetch داخل الصفحة يستعمل كوكيز Cloudflare فينجح حيث يفشل fetch الخادم).
 * يعيد الميتاداتا + بايتات base64 (أو fileUrl=null لغير العامّة).
 */
async function resolveAndDownload(browser, bookUrl) {
	const page = await browser.newPage();
	try {
		await page.setUserAgent(UA);
		await page.setExtraHTTPHeaders({ 'Accept-Language': 'ar-EG,ar;q=0.9,en;q=0.7' });
		await page.goto(bookUrl, { waitUntil: 'domcontentloaded', timeout: 60000 });

		// انتظر مصافحة check_user (تضبط csrf_token=osf).
		for (let i = 0; i < 20; i++) {
			const ready = await page
				.evaluate(() => typeof is_logged_replied !== 'undefined' && is_logged_replied === true)
				.catch(() => false);
			if (ready) break;
			await new Promise((r) => setTimeout(r, 1000));
		}

		// اقرأ الميتاداتا من og:* قبل فتح المودال.
		const meta = await page
			.evaluate(() => {
				const g = (p) => {
					const el =
						document.querySelector(`meta[property="${p}"]`) ||
						document.querySelector(`meta[name="${p}"]`);
					return el ? (el.getAttribute('content') || '').trim() : '';
				};
				// تلميحات التصنيف: فتات المسار + وسوم الكتاب (تُمكّن الخادم من
				// وضع الكتاب في قسم موضوعيّ مناسب بدل «كتب عامة» العامّة).
				const hints = [];
				document
					.querySelectorAll('ol.breadcrumb li a, .breadcrumb a, a.tag_btn, .tags a, a[href*="/tag/"], a[href*="/category/"]')
					.forEach((a) => {
						const t = (a.textContent || '').replace(/\s+/g, ' ').trim();
						if (t) hints.push(t);
					});
				const categoryHints = [
					...new Set(hints.filter((t) => t && !/^(الرئيسية|home|كتب|noor library|مكتبة نور|download)$/i.test(t)))
				].slice(0, 12);
				return {
					title: g('og:title') || (document.title || '').replace(/\s*\|\s*.*$/, '').trim(),
					description: g('og:description') || g('description'),
					author: g('book:author') || g('author'),
					thumbnail: g('og:image'),
					categoryHints
				};
			})
			.catch(() => ({}));

		// استدعِ resolver الموقع (يتخطّى العدّاد الوهميّ).
		await page
			.evaluate(() => {
				try {
					if (typeof go_gownload === 'function') go_gownload();
					else if (typeof set_download_timer === 'function') set_download_timer();
				} catch {
					/* ignore */
				}
			})
			.catch(() => {});

		// استطلع ظهور رابط internal_download (حتى ~30s).
		let fileUrl = null;
		for (let i = 0; i < 20; i++) {
			fileUrl = await page
				.evaluate(() => {
					const a = document.querySelector('a[href*="internal_download"]');
					return a ? a.href : null;
				})
				.catch(() => null);
			if (fileUrl) break;
			await new Promise((r) => setTimeout(r, 1500));
		}
		if (!fileUrl) return { fileUrl: null, meta };

		// نزّل البايتات داخل الصفحة (base64 على دفعات لتفادي RangeError).
		const dl = await page
			.evaluate(async (u) => {
				try {
					const r = await fetch(u, { credentials: 'include', redirect: 'follow', headers: { Accept: '*/*' } });
					if (!r.ok) return { ok: false, status: r.status };
					const bytes = new Uint8Array(await r.arrayBuffer());
					const ct = r.headers.get('content-type') || 'application/pdf';
					let bin = '';
					const chunk = 0x8000;
					for (let i = 0; i < bytes.length; i += chunk) {
						bin += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
					}
					return { ok: true, status: r.status, contentType: ct, base64: btoa(bin), size: bytes.length };
				} catch (e) {
					return { ok: false, err: String(e) };
				}
			}, fileUrl)
			.catch((e) => ({ ok: false, err: String(e) }));

		return { fileUrl, meta, dl };
	} finally {
		await page.close().catch(() => {});
	}
}

async function postStep(payload) {
	const res = await fetch(`${BASE}/api/cron/noor-library-ingest`, {
		method: 'POST',
		headers: authHeaders({ 'Content-Type': 'application/json' }),
		body: JSON.stringify(payload)
	});
	const data = await res.json().catch(() => ({}));
	return { status: res.status, data };
}

/** يرفع البايتات إلى رابط GCS الموقَّع بـ PUT (نوع المحتوى يجب أن يطابق التوقيع). */
async function putToSignedUrl(uploadUrl, buffer, contentType) {
	const res = await fetch(uploadUrl, {
		method: 'PUT',
		headers: { 'Content-Type': contentType },
		body: buffer
	});
	if (res.ok) return { ok: true };
	return { ok: false, status: res.status, text: await res.text().catch(() => '') };
}

function filenameFromUrl(u, fallback) {
	try {
		const name = decodeURIComponent(new URL(u).pathname.split('/').filter(Boolean).pop() || '');
		return name && name.length > 2 ? name : fallback;
	} catch {
		return fallback;
	}
}

async function main() {
	const startedAt = Date.now();
	console.log(`▶ Noor CI ingest — base=${BASE} max=${MAX_BOOKS}`);

	// 1) اجلب البذور + المعروف من الخادم (مصدر واحد للحقيقة).
	let seeds = FALLBACK_SEEDS;
	const known = new Set();
	try {
		const res = await fetch(`${BASE}/api/cron/noor-library-ingest`, { headers: authHeaders() });
		if (res.ok) {
			const j = await res.json();
			if (Array.isArray(j.seeds) && j.seeds.length) seeds = j.seeds;
			for (const id of j.knownIds || []) known.add(String(id));
			console.log(`  seeds=${seeds.length} known=${known.size}`);
		} else {
			console.log(`  ⚠ GET /ingest → ${res.status}; using fallback seeds`);
		}
	} catch (e) {
		console.log(`  ⚠ GET /ingest failed (${e.message}); using fallback seeds`);
	}

	// 2) افتح المتصفّح مبكّراً (نستعمله للقوائم والتنزيل معاً).
	//    protocolTimeout مرتفع لأنّ ترميز الكتب الكبيرة (100MB+) إلى base64
	//    داخل الصفحة قد يتجاوز مهلة CDP الافتراضيّة (180s).
	const browser = await puppeteerExtra.launch({
		headless: 'new',
		protocolTimeout: 240000,
		args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-blink-features=AutomationControlled', '--lang=ar-EG,ar']
	});
	let ok = 0;
	let skipped = 0;
	let failed = 0;
	try {
		// 3) اجمع مرشّحين جدداً **عبر المتصفّح** (Cloudflare يحجب fetch العاديّ
		//    من عناوين مراكز البيانات مثل GitHub Actions بـ403).
		const candidates = await collectCandidatesViaBrowser(browser, seeds, known, MAX_BOOKS * 3);
		console.log(`  candidates=${candidates.length}`);
		if (!candidates.length) {
			console.log('لا مرشّحين جدداً — انتهى.');
			return;
		}

		for (const cand of candidates) {
			if (ok >= MAX_BOOKS || Date.now() - startedAt > MAX_MS) break;
			// حصانة: أيّ خطأ (خصوصاً أعطال الشبكة العابرة مثل ECONNRESET) في
			// معالجة كتاب واحد يجب ألّا يُسقط الدفعة كلّها — نعدّه فشلاً ونكمل.
			try {

			// 0) استخرج الرابط ونزّل البايتات داخل المتصفّح.
			let resolved;
			try {
				resolved = await resolveAndDownload(browser, cand.url);
			} catch (e) {
				failed++;
				console.log(`  ✗ resolve ${cand.bookId} — ${e.message}`);
				continue;
			}
			if (!resolved.fileUrl) {
				// لا رابط عامّ ⇒ كتاب محفوظ/متابعة نشر ⇒ تخطٍّ.
				skipped++;
				console.log(`  ↷ not public (no link): ${cand.bookId}`);
				continue;
			}
			if (!resolved.dl?.ok || !resolved.dl.base64) {
				failed++;
				console.log(`  ✗ download ${cand.bookId} — status=${resolved.dl?.status || ''} ${resolved.dl?.err || ''}`);
				continue;
			}
			const contentType = String(resolved.dl.contentType || 'application/pdf');
			const filename = filenameFromUrl(cand.url, `${cand.bookId}.pdf`);
			const buffer = Buffer.from(resolved.dl.base64, 'base64');

			// 1) اطلب رابط رفع موقَّعاً.
			const sign = await postStep({
				step: 'signurl',
				bookUrl: cand.url,
				bookId: cand.bookId,
				filename,
				contentType
			});
			if (sign.data?.skipped) {
				skipped++;
				console.log(`  ↷ ${cand.bookId}: ${sign.data.reason}`);
				continue;
			}
			if (!sign.data?.uploadUrl) {
				failed++;
				console.log(`  ✗ signurl ${cand.bookId} → ${sign.status} ${sign.data?.reason || ''}`);
				continue;
			}

			// 2) ارفع البايتات مباشرةً إلى تخزين نبراس (بلا حدّ حجم Vercel).
			const put = await putToSignedUrl(sign.data.uploadUrl, buffer, sign.data.contentType || contentType);
			if (!put.ok) {
				failed++;
				console.log(`  ✗ put ${cand.bookId} → ${put.status} ${(put.text || '').slice(0, 80)}`);
				continue;
			}

			// 3) إنهاء — تصنيف محليّ + إنشاء أقسام + كتابة Firestore.
			const fin = await postStep({
				step: 'finalize',
				bookUrl: cand.url,
				bookId: cand.bookId,
				fileId: sign.data.fileId,
				objectPath: sign.data.objectPath,
				token: sign.data.token,
				downloadUrl: sign.data.downloadUrl,
				size: buffer.length,
				contentType: sign.data.contentType || contentType,
				filename,
				title: resolved.meta.title || cand.bookId,
				author: resolved.meta.author || '',
				description: resolved.meta.description || '',
				thumbnail: resolved.meta.thumbnail || '',
				categoryHints: resolved.meta.categoryHints || []
			});
			if (fin.data?.ok && !fin.data.skipped) {
				ok++;
				console.log(`  ✓ ${fin.data.title || cand.bookId} → ${fin.data.fileId} (${(buffer.length / 1048576).toFixed(1)}MB)`);
			} else if (fin.data?.skipped) {
				skipped++;
				console.log(`  ↷ ${cand.bookId}: ${fin.data.reason}`);
			} else {
				failed++;
				console.log(`  ✗ finalize ${cand.bookId} → ${fin.status} ${fin.data?.reason || ''} ${fin.data?.message || ''}`);
			}

			} catch (e) {
				failed++;
				console.log(`  ✗ ${cand.bookId} — ${e?.message || String(e)} (متابعة)`);
			}
		}
	} finally {
		await browser.close().catch(() => {});
	}
	console.log(`✅ done — imported=${ok} skipped=${skipped} failed=${failed} elapsed=${Date.now() - startedAt}ms`);
}

main().catch((e) => {
	console.error('fatal:', e);
	process.exit(1);
});
