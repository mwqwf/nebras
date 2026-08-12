/**
 * noorBrowser.js — متصفّح Chromium خفيّ (Puppeteer + stealth) لاختراق
 * حماية Cloudflare وغيرها من فحوص "أنا لست روبوتاً" على noor-book.com.
 *
 * ╔══════════════════════════════════════════════════════════════════╗
 * ║  لماذا Puppeteer؟                                                 ║
 * ╠══════════════════════════════════════════════════════════════════╣
 * ║  مكتبة نور تستعمل Cloudflare تحدّياً (5 ثوانٍ + JS challenge). أيّ   ║
 * ║  fetch() عاديّ يُرجع HTML "Just a moment..." بدل الصفحة الفعليّة.   ║
 * ║  Puppeteer مع stealth-plugin يُلصّق Chromium حقيقي، يمرّر التحدّي،  ║
 * ║  ثمّ نقرأ DOM النهائيّ. أبطأ بكثير من fetch، لكنّه يعمل.            ║
 * ╚══════════════════════════════════════════════════════════════════╝
 *
 * المعمارية:
 *   • Singleton على مستوى الـ Node process (محفوظ في globalThis لتجاوز HMR).
 *   • متصفّح واحد + N صفحات على حسب الحاجة. كلّ صفحة تُغلَق بعد الاستعمال
 *     لتفادي تسرّب الذاكرة (لا context pooling لتبسيط الإدارة).
 *   • Puppeteer + plugins يُحمَّلان عبر **dynamic import lazy** لكي لا
 *     تنكسر بناءات serverless (Vercel) عند غيابهم.
 *   • متغيّرات بيئة:
 *       NOOR_USE_PUPPETEER=true|false  — تفعيل/تعطيل Puppeteer (افتراضي
 *                                          true إن كانت الحزمة موجودة).
 *       PUPPETEER_HEADLESS=true|false  — تشغيل بدون واجهة (افتراضي true).
 *       PUPPETEER_EXECUTABLE_PATH      — مسار Chromium مخصّص (اختياري).
 *
 * الواجهة العامّة:
 *   - isPuppeteerEnabled() → boolean
 *   - fetchHtmlViaBrowser(url, opts) → { html, finalUrl, status }
 *   - downloadBufferViaBrowser(url, opts) → { buffer, contentType, filename }
 *   - shutdownBrowser() → Promise<void>      (تنظيف عند إيقاف الـ process)
 */

import { env } from '$env/dynamic/private';

const GLOBAL_KEY = '__NEBRAS_NOOR_BROWSER__';

function getGlobalState() {
	if (!globalThis[GLOBAL_KEY]) {
		globalThis[GLOBAL_KEY] = {
			browser: null,
			browserPromise: null,
			puppeteerModule: null,
			puppeteerEnabled: null, // unknown until first probe
			lastError: null
		};
	}
	return globalThis[GLOBAL_KEY];
}

const DEFAULT_USER_AGENT =
	'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
	'(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

function readBoolEnv(name, fallback) {
	const raw = String(env[name] ?? process.env[name] ?? '').trim().toLowerCase();
	if (raw === '') return fallback;
	if (['1', 'true', 'yes', 'on'].includes(raw)) return true;
	if (['0', 'false', 'no', 'off'].includes(raw)) return false;
	return fallback;
}

/**
 * يحاول تحميل puppeteer-extra + stealth plugin. إن لم تُثبَّت الحزم، يُرجع
 * null دون رمي خطأ. هذا يسمح للكود بالعمل على Vercel (بدون puppeteer).
 *
 * نُجرّب أوّلاً `puppeteer-extra` ثمّ نرجع لـ `puppeteer` العاديّ كاحتياط.
 */
async function loadPuppeteer() {
	const state = getGlobalState();
	if (state.puppeteerModule) return state.puppeteerModule;
	if (state.puppeteerEnabled === false) return null;

	try {
		// dynamic import لكي لا تنكسر البناءات حيث puppeteer غير مثبّت.
		const [{ default: puppeteerExtra }, { default: StealthPlugin }] = await Promise.all([
			import('puppeteer-extra'),
			import('puppeteer-extra-plugin-stealth')
		]);
		puppeteerExtra.use(StealthPlugin());
		state.puppeteerModule = puppeteerExtra;
		state.puppeteerEnabled = true;
		return puppeteerExtra;
	} catch (errExtra) {
		// retry with plain puppeteer (بدون stealth — لن يجتاز Cloudflare غالباً
		// لكن أفضل من لا شيء أثناء التطوير).
		try {
			const mod = await import('puppeteer');
			state.puppeteerModule = mod.default || mod;
			state.puppeteerEnabled = true;
			state.lastError =
				'puppeteer-extra غير مثبّت — استعمال puppeteer العاديّ بدون stealth (لن يجتاز Cloudflare).';
			return state.puppeteerModule;
		} catch (errPlain) {
			state.puppeteerEnabled = false;
			state.lastError =
				'لا puppeteer ولا puppeteer-extra مثبّتَيْن. شغّل: npm i -D puppeteer puppeteer-extra puppeteer-extra-plugin-stealth';
			return null;
		}
	}
}

/**
 * يفحص ما إذا كان Puppeteer مفعّلاً ومُهيّأً (حزمة مثبّتة + لم يُعطَّل بـ env).
 *
 * **ملاحظة**: هذا الفحص async لأنّه يُجرّب الـ import أوّل مرّة. النتيجة
 * مُخزَّنة لذا الاستدعاءات اللاحقة O(1).
 *
 * @returns {Promise<boolean>}
 */
export async function isPuppeteerEnabled() {
	// الافتراضي false: على Vercel/serverless لا يعمل Puppeteer (لا Chromium)،
	// ومحاولة تحميل puppeteer-extra-plugin-stealth تكسر بـ
	// "Cannot find module .../evasions/chrome.app" وتملأ السجلّ. المسار
	// المعتمد لتجاوز Cloudflare هو crawl4ai. فعّله صراحةً (NOOR_USE_PUPPETEER=true)
	// فقط على خادم طويل الأمد مثبَّت عليه Chromium.
	const enabledFlag = readBoolEnv('NOOR_USE_PUPPETEER', false);
	if (!enabledFlag) return false;
	const mod = await loadPuppeteer();
	return mod !== null;
}

async function getBrowser() {
	const state = getGlobalState();
	if (state.browser && state.browser.connected !== false) {
		try {
			// Puppeteer 21+: إذا انفصل الـ process، browser يصير غير متّصل.
			if (typeof state.browser.isConnected === 'function' && !state.browser.isConnected()) {
				state.browser = null;
			}
		} catch {
			state.browser = null;
		}
	}
	if (state.browser) return state.browser;

	if (state.browserPromise) return state.browserPromise;

	const puppeteer = await loadPuppeteer();
	if (!puppeteer) {
		throw Object.assign(new Error(state.lastError || 'puppeteer غير متاح.'), {
			reason: 'puppeteer_not_available',
			status: 501
		});
	}

	const headless = readBoolEnv('PUPPETEER_HEADLESS', true);
	const executablePath =
		String(env.PUPPETEER_EXECUTABLE_PATH || process.env.PUPPETEER_EXECUTABLE_PATH || '').trim() ||
		undefined;

	state.browserPromise = puppeteer
		.launch({
			headless: headless ? 'new' : false,
			executablePath,
			args: [
				'--no-sandbox',
				'--disable-setuid-sandbox',
				'--disable-blink-features=AutomationControlled',
				'--disable-features=IsolateOrigins,site-per-process',
				'--lang=ar-EG,ar',
				'--window-size=1366,900'
			],
			defaultViewport: { width: 1366, height: 900 }
		})
		.then((browser) => {
			state.browser = browser;
			state.browserPromise = null;

			browser.on('disconnected', () => {
				if (state.browser === browser) state.browser = null;
			});
			return browser;
		})
		.catch((err) => {
			state.browserPromise = null;
			throw err;
		});

	return state.browserPromise;
}

async function preparePage(page) {
	await page.setUserAgent(DEFAULT_USER_AGENT);
	await page.setExtraHTTPHeaders({
		'Accept-Language': 'ar-EG,ar;q=0.9,en;q=0.7',
		Accept: 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
	});
	// قلّل تحميل الموارد الثقيلة (صور/فيديو/خطوط) لتسريع الجلب — لكن أبقِ
	// سكريبتات وstylesheets لكي يجتاز تحدّي Cloudflare بشكل صحيح.
	await page.setRequestInterception(true);
	page.on('request', (req) => {
		const type = req.resourceType();
		if (type === 'image' || type === 'media' || type === 'font') {
			req.abort().catch(() => {});
		} else {
			req.continue().catch(() => {});
		}
	});
}

/**
 * يحاول اكتشاف صفحات تحدّي Cloudflare (الفاصل "Checking your browser…"
 * وعنوان "Just a moment..."). إن وُجدت، نُمدّد الانتظار حتى يختفي التحدّي.
 *
 * @param {import('puppeteer').Page} page
 * @param {{ maxWaitMs?: number }} [opts]
 */
async function waitForCloudflareIfNeeded(page, { maxWaitMs = 25000 } = {}) {
	const start = Date.now();
	const isChallenge = async () => {
		try {
			const html = await page.content();
			if (!html) return false;
			const lower = html.toLowerCase();
			return (
				lower.includes('just a moment') ||
				lower.includes('checking your browser') ||
				lower.includes('cf-browser-verification') ||
				lower.includes('challenge-platform') ||
				lower.includes('cf-mitigated')
			);
		} catch {
			return false;
		}
	};

	while (Date.now() - start < maxWaitMs) {
		if (!(await isChallenge())) return;
		// انتظر nav أو ms — تحدّي Cloudflare يُحدّث الصفحة عند انتهائه.
		await Promise.race([
			page
				.waitForNavigation({ waitUntil: 'domcontentloaded', timeout: 5000 })
				.catch(() => null),
			new Promise((r) => setTimeout(r, 2500))
		]);
	}
}

/**
 * يجلب HTML صفحة عبر متصفّح Chromium حقيقي يجتاز تحدّيات Cloudflare.
 *
 * @param {string} url
 * @param {{
 *   waitForSelector?: string,
 *   timeoutMs?: number,
 *   waitForCloudflare?: boolean
 * }} [opts]
 * @returns {Promise<{ html:string, finalUrl:string, status:number }>}
 */
export async function fetchHtmlViaBrowser(url, opts = {}) {
	const { waitForSelector = null, timeoutMs = 45000, waitForCloudflare = true } = opts;
	const browser = await getBrowser();
	const page = await browser.newPage();
	try {
		await preparePage(page);
		const response = await page.goto(url, {
			waitUntil: 'domcontentloaded',
			timeout: timeoutMs
		});

		if (waitForCloudflare) {
			await waitForCloudflareIfNeeded(page, { maxWaitMs: 25000 });
		}

		if (waitForSelector) {
			await page
				.waitForSelector(waitForSelector, { timeout: 10000 })
				.catch(() => null);
		}

		const html = await page.content();
		const finalUrl = page.url();
		const status = response?.status?.() ?? 200;

		return { html, finalUrl, status };
	} finally {
		await page.close().catch(() => {});
	}
}

/**
 * ينزّل buffer ملفّ (PDF/Audio/...) عبر متصفّح Chromium حقيقي. الاستراتيجيّة
 * الجديدة (مُختبرة على noor-book + Cloudflare):
 *
 *   1) إن أُعطي `refererUrl` (صفحة الكتاب المصدرية)، نزور تلك الصفحة أوّلاً
 *      لنحصل على cf_clearance + جميع كوكيز الجلسة المرتبطة بـ origin.
 *   2) ثمّ ننفّذ `fetch()` من **داخل سياق الصفحة** عبر `page.evaluate`. هذا
 *      الـ fetch يستعمل كلّ الكوكيز تلقائياً (لا حاجة لنقلها يدوياً) ولا
 *      يضربه Cloudflare لأنّه نابع من الـ origin نفسه بنفس الـ User-Agent.
 *   3) نُرجع الـ Buffer + content-type.
 *
 *   Bonus: لو لم يُعطَ refererUrl، نشتقّه من origin الـ url ذاته.
 *
 * @param {string} url
 * @param {{ timeoutMs?: number, refererUrl?: string|null }} [opts]
 * @returns {Promise<{ buffer: Buffer, contentType: string, filename: string }>}
 */
export async function downloadBufferViaBrowser(url, opts = {}) {
	const { timeoutMs = 90000, refererUrl = null } = opts;
	const browser = await getBrowser();
	const page = await browser.newPage();

	try {
		await page.setUserAgent(DEFAULT_USER_AGENT);
		await page.setExtraHTTPHeaders({
			'Accept-Language': 'ar-EG,ar;q=0.9,en;q=0.7'
		});

		// 1) زُر صفحة المرجع (أو على الأقل origin الـ url) أوّلاً ليحصل
		//    المتصفّح على cf_clearance + كوكيز نور للجلسة.
		let landingUrl = refererUrl;
		if (!landingUrl) {
			try {
				landingUrl = new URL(url).origin + '/';
			} catch {
				landingUrl = null;
			}
		}
		if (landingUrl && landingUrl !== url) {
			await page
				.goto(landingUrl, { waitUntil: 'domcontentloaded', timeout: timeoutMs })
				.catch(() => null);
			await waitForCloudflareIfNeeded(page, { maxWaitMs: 25000 });
		}

		// 2) نفّذ fetch داخل سياق الصفحة — يستعمل كلّ الكوكيز تلقائياً
		//    (cf_clearance + cf_bm + جلسة نور). نُرجع base64 لأنّ Puppeteer لا
		//    ينقل ArrayBuffer مباشرةً عبر CDP.
		const result = await page.evaluate(async (fileUrl) => {
			try {
				const r = await fetch(fileUrl, {
					credentials: 'include',
					redirect: 'follow',
					mode: 'cors',
					headers: { Accept: '*/*' }
				});
				if (!r.ok) {
					return { ok: false, status: r.status, contentType: '', base64: '' };
				}
				const buf = await r.arrayBuffer();
				const bytes = new Uint8Array(buf);
				const ct = r.headers.get('content-type') || 'application/octet-stream';
				// تحويل لـ base64 على دفعات (تجنّب RangeError على ملفّات كبيرة).
				let bin = '';
				const chunk = 0x8000;
				for (let i = 0; i < bytes.length; i += chunk) {
					bin += String.fromCharCode.apply(
						null,
						/** @type {any} */ (bytes.subarray(i, i + chunk))
					);
				}
				return {
					ok: true,
					status: r.status,
					contentType: ct,
					base64: btoa(bin),
					finalUrl: r.url
				};
			} catch (err) {
				return {
					ok: false,
					status: 0,
					contentType: '',
					base64: '',
					error: String(/** @type {Error} */ (err)?.message || err)
				};
			}
		}, url);

		if (!result.ok || !result.base64) {
			throw Object.assign(
				new Error(
					`فشل تنزيل الملفّ من داخل المتصفّح — HTTP ${result.status}${result.error ? ' — ' + result.error : ''}`
				),
				{
					reason: 'puppeteer_in_page_fetch_failed',
					status: result.status || 0
				}
			);
		}

		const buffer = Buffer.from(result.base64, 'base64');
		const contentType = result.contentType || 'application/octet-stream';

		// استخراج اسم الملفّ من URL (لا headers في in-page fetch بسهولة).
		let filename = 'book.pdf';
		try {
			const u = new URL(result.finalUrl || url);
			filename = decodeURIComponent(u.pathname.split('/').pop() || 'book.pdf');
		} catch {
			// تجاهل
		}
		if (!filename || filename.length < 3) filename = 'book.pdf';

		return { buffer, contentType, filename };
	} finally {
		await page.close().catch(() => {});
	}
}

/**
 * يفتح صفحة كتاب على noor-book.com عبر متصفّح حقيقي، ينتظر تنفيذ JS،
 * ثمّ يبحث في الـ DOM (وليس HTML الخام فقط) عن الرابط الفعليّ للكتاب.
 *
 * يجرّب كلّ الطرق المعروفة:
 *   • أزرار "تحميل" / "حمل" / "Download" — قد تظهر بـ JS بعد التحميل
 *   • أيّ <a href> ينتهي بامتداد ملفّ
 *   • زرّ "اقرأ" / "View" يفتح PDF embed
 *   • ينقر زرّ التنزيل (إن وُجد) ويلتقط رابط الـ navigation الناتج
 *
 * @param {string} bookPageUrl
 * @param {{ timeoutMs?: number, clickDownload?: boolean }} [opts]
 * @returns {Promise<{ url: string, source: string } | null>}
 */
export async function findBookFileUrlViaBrowser(bookPageUrl, opts = {}) {
	const { timeoutMs = 30000, clickDownload = true } = opts;
	const browser = await getBrowser();
	const page = await browser.newPage();

	try {
		await preparePage(page);
		await page.goto(bookPageUrl, {
			waitUntil: 'domcontentloaded',
			timeout: timeoutMs
		});
		await waitForCloudflareIfNeeded(page, { maxWaitMs: 25000 });

		// 0) 🥇 المسار الأوثق (مثبَّت تجريبياً على noor-book.com): استدعِ دالّة
		//    الموقع نفسه `go_gownload()` بعد اكتمال مصافحة التحقّق
		//    (is_logged_replied=true)، فتُنفَّذ get_download_links AJAX وتظهر
		//    وصلة `internal_download` الحقيقيّة داخل المودال — تعمل حتى لغير
		//    المسجَّلين وبلا نقر أزرار (يتجنّب النقر الخاطئ). الرابط الناتج عامّ.
		try {
			// انتظر مصافحة check_user (تضبط csrf_token=osf) حتى ~20s.
			for (let i = 0; i < 20; i++) {
				const ready = await page
					.evaluate(() => typeof is_logged_replied !== 'undefined' && is_logged_replied === true)
					.catch(() => false);
				if (ready) break;
				await new Promise((r) => setTimeout(r, 1000));
			}
			// استدعِ resolver الموقع مباشرةً (يتخطّى العدّاد الوهميّ).
			await page
				.evaluate(() => {
					try {
						if (typeof go_gownload === 'function') go_gownload();
						else if (typeof set_download_timer === 'function') set_download_timer();
					} catch {
						// تجاهل
					}
				})
				.catch(() => {});
			// استطلع ظهور رابط internal_download حتى ~30s.
			for (let i = 0; i < 20; i++) {
				const href = await page
					.evaluate(() => {
						const a = document.querySelector('a[href*="internal_download"]');
						return a ? a.href : null;
					})
					.catch(() => null);
				if (href) {
					return { url: href, source: 'go_gownload:internal_download' };
				}
				await new Promise((r) => setTimeout(r, 1500));
			}
		} catch {
			// نسقط للطرق الأدنى (DOM scan + نقر) أدناه.
		}

		// 1) ابحث في الـ DOM المُعالَج (بعد تنفيذ JS)
		const found = await page
			.evaluate(() => {
				const out = [];
				const push = (url, source) => {
					if (typeof url !== 'string') return;
					const trimmed = url.trim();
					if (!trimmed) return;
					out.push({ url: trimmed, source });
				};

				// iframes
				document.querySelectorAll('iframe[src]').forEach((el) => {
					push(el.getAttribute('src'), 'iframe');
				});

				// embed/object
				document.querySelectorAll('embed[src],object[data]').forEach((el) => {
					push(el.getAttribute('src') || el.getAttribute('data'), 'embed');
				});

				// كلّ <a> + data attributes
				document.querySelectorAll('a[href]').forEach((el) => {
					const href = el.getAttribute('href');
					const text = (el.textContent || '').trim();
					push(href, 'a:' + text.slice(0, 30));
				});

				document
					.querySelectorAll(
						'[data-download],[data-file],[data-url],[data-href],[data-src],[data-pdf]'
					)
					.forEach((el) => {
						for (const attr of [
							'data-download',
							'data-file',
							'data-url',
							'data-href',
							'data-src',
							'data-pdf'
						]) {
							const v = el.getAttribute(attr);
							if (v) push(v, attr);
						}
					});

				return out;
			})
			.catch(() => []);

		const baseUrl = page.url();
		const candidates = [];
		const seen = new Set();
		for (const f of found) {
			let abs;
			try {
				abs = new URL(f.url, baseUrl).toString();
			} catch {
				continue;
			}
			if (seen.has(abs)) continue;
			seen.add(abs);

			const lower = abs.toLowerCase();
			let score = 0;
			let hint = '';

			// أعلى أولويّة: روابط ملفّات مباشرة
			if (/\.(?:pdf|epub|mp3|mp4|m4a|wav|docx?)(?:\?|$|#)/i.test(lower)) {
				score = 100;
				hint = 'direct-file';
			} else if (
				/\/(download|file|files|book\/download)\//i.test(lower) ||
				/تحميل-كتاب|%D8%AA%D8%AD%D9%85%D9%8A%D9%84-%D9%83%D8%AA%D8%A7%D8%A8/i.test(
					lower
				)
			) {
				score = 70;
				hint = 'download-path';
			} else if (
				/تحميل|تنزيل|download|حمل/i.test(f.source) &&
				lower.startsWith('http')
			) {
				score = 50;
				hint = 'download-text-link';
			}

			if (score > 0) candidates.push({ url: abs, score, hint });
		}

		candidates.sort((a, b) => b.score - a.score);
		if (candidates.length > 0) {
			return { url: candidates[0].url, source: candidates[0].hint };
		}

		// 2) لم نجد في الـ DOM → جرّب النقر على زرّ التنزيل والتقاط:
		//    (أ) request لـ ملفّ معروف، أو
		//    (ب) response بـ content-type يدلّ على ملفّ (application/pdf …).
		//    نعتمد على كلتيهما لأنّ نور أحياناً تردّ بـ blob/octet-stream
		//    بدون امتداد .pdf في الـ URL، وأحياناً تستعمل intermediate page.
		if (clickDownload) {
			const FILE_URL_RE = /\.(?:pdf|epub|mp3|mp4|m4a|wav|docx?)(?:\?|$|#)/i;
			const FILE_PATH_RE = /\/(?:book-pdf|bk-pdf|download|dl|file|files|book\/download)\//i;
			const FILE_CT_RE =
				/^(?:application\/pdf|application\/epub\+zip|application\/octet-stream|audio\/|video\/|application\/msword|application\/vnd\.openxmlformats)/i;

			// أ) راقب الطلبات (سريع للـ direct PDFs)
			const reqP = page
				.waitForRequest(
					(req) => {
						try {
							const u = req.url();
							return (
								FILE_URL_RE.test(u) ||
								FILE_PATH_RE.test(u)
							);
						} catch {
							return false;
						}
					},
					{ timeout: 25000 }
				)
				.catch(() => null);

			// ب) راقب الردود بـ content-type (للحالات حيث الـ URL مبهم)
			const resP = page
				.waitForResponse(
					(res) => {
						try {
							const ct = (res.headers() || {})['content-type'] || '';
							const u = res.url();
							if (!FILE_CT_RE.test(ct)) return false;
							// تجاهل ردود تابع الصفحة الأصليّة (HTML)
							if (ct.toLowerCase().startsWith('text/html')) return false;
							// تجاهل assets ثابتة معروفة
							if (/\.(?:css|js|png|jpe?g|gif|svg|webp|woff2?)(?:\?|$)/i.test(u)) {
								return false;
							}
							return true;
						} catch {
							return false;
						}
					},
					{ timeout: 25000 }
				)
				.catch(() => null);

			// جرّب كلّ المرشّحين الذين يبدون كأزرار تنزيل، ليس أوّل واحد فقط.
			const clickedAny = await page
				.evaluate(() => {
					const labels = ['تحميل', 'تنزيل', 'حمل', 'download', 'Download', 'حمّل'];
					const classHints =
						/btn-download|downloadbutton|download-btn|btn-dl|dl-btn|btnDownload|download/i;

					const score = (el) => {
						let s = 0;
						const cls = (el.getAttribute('class') || '') + '';
						const id = (el.getAttribute('id') || '') + '';
						const href = (el.getAttribute('href') || '') + '';
						const txt = ((el.textContent || '') + '').trim();
						const alt =
							(el.querySelector?.('img')?.getAttribute('alt') || '').trim();
						if (classHints.test(cls)) s += 5;
						if (classHints.test(id)) s += 3;
						if (labels.some((l) => txt.includes(l))) s += 4;
						if (labels.some((l) => alt.includes(l))) s += 3;
						if (/تحميل|download|book-pdf|bk-pdf|\/dl\//i.test(href)) s += 6;
						return s;
					};

					const all = Array.from(
						document.querySelectorAll('a, button, [role="button"]')
					);
					const ranked = all
						.map((el) => ({ el, s: score(el) }))
						.filter((x) => x.s > 0)
						.sort((a, b) => b.s - a.s)
						.slice(0, 3); // جرّب أعلى 3 مرشّحين فقط

					if (ranked.length === 0) return 0;
					for (const { el } of ranked) {
						try {
							/** @type {HTMLElement} */ (el).click();
						} catch {
							// تجاهل أخطاء النقر الفرديّ، نواصل المرشّح التالي.
						}
					}
					return ranked.length;
				})
				.catch(() => 0);

			if (clickedAny > 0) {
				const [req, res] = await Promise.all([reqP, resP]);
				if (req) return { url: req.url(), source: 'click-download:request' };
				if (res) return { url: res.url(), source: 'click-download:response' };
			}
		}

		return null;
	} finally {
		await page.close().catch(() => {});
	}
}

/**
 * يُغلق المتصفّح والـ Singleton. يُستدعى عند shutdown مسرَّع للـ process
 * (ليس ضرورياً عادةً — Node ينظّفه عند الخروج).
 */
export async function shutdownBrowser() {
	const state = getGlobalState();
	if (state.browser) {
		try {
			await state.browser.close();
		} catch {
			// ignore
		}
		state.browser = null;
	}
}

/**
 * إن أردتَ احتساب آخر سبب لتعطيل Puppeteer (مثلاً لعرضه في UI).
 */
export function getPuppeteerLastError() {
	return getGlobalState().lastError;
}
