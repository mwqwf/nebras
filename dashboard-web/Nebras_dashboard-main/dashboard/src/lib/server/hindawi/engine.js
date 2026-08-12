/**
 * engine.js — المحرّك الذاتيّ لمكتبة مؤسسة هنداوي.
 *
 * ╔══════════════════════════════════════════════════════════════════╗
 * ║  🔒 Nebras Only. كتب PDF حرّة الترخيص (CC) من هنداوي حصراً.       ║
 * ╚══════════════════════════════════════════════════════════════════╝
 *
 * يطابق معماريّة محرّكَيْ Internet Archive / مكتبة نور:
 *   • Singleton في globalThis + علامة enabled في RTDB.
 *   • كلّ tick: يكتشف صفحة فهرسة → يجلب PDF → يصنّف → يرفع → يسجّل.
 *   • على serverless الـ cron هو المُحرّك (runCronTick).
 *
 * مسارات RTDB:
 *   hindawi_library_engine/config  — { enabled, tickIntervalMs, batchSize, maxPagesPerCall }
 *   hindawi_library_engine/cursor  — { page }
 *   hindawi_library_engine/stats   — { totalFetched, sectionsCreated, lastRunAt, lastError, runsCount }
 *   hindawi_library_engine/log/{id}— آخر 60 إدخال
 *
 * يعيد استخدام المنطق العامّ لمحرّك نور (تصنيف/شجرة/إنشاء أقسام) لأنّه
 * مستقلّ عن المصدر.
 */

import {
	getAdminDatabase,
	getNebrasFirestoreAdmin,
	isAdminConfigured,
	sendTopicMessage
} from '$lib/server/firebaseAdmin.js';
import { adminFsBulkDeleteFileMirrorIds } from '$lib/server/nebrasUnifiedFirestoreAdmin.js';
import { NEBRAS_FS_UPLOADS, NEBRAS_FS_CONTENT_FILES } from '$lib/firebase/nebrasUnifiedPaths.js';
import { createMainSectionAdmin, createSubSectionAdmin } from '../noorLibrary/sectionsCreator.js';
import { fetchBookMetadata, downloadBookFile } from './fetcher.js';
import { HINDAWI_CATEGORIES, discoverNewBooksInCategory } from './crawler.js';
import { isBookImported, partitionKnownBooks, recordImported, recordFailure } from './registry.js';
import { adminUploadAndRegister } from './adminUploader.js';
import { INGEST_FROZEN } from '../ingestFreeze.js';

// القسم الفرعيّ الموحَّد تحت كل تصنيف رئيسيّ (يميّز مصدر هنداوي ويُسهّل الفصل).
const HINDAWI_SUB_NAME = 'كتب هنداوي';

const ENGINE_ROOT = 'hindawi_library_engine';
const CONFIG_PATH = `${ENGINE_ROOT}/config`;
const CURSOR_PATH = `${ENGINE_ROOT}/cursor`;
const STATS_PATH = `${ENGINE_ROOT}/stats`;
const LOG_PATH = `${ENGINE_ROOT}/log`;
const LOG_MAX_ENTRIES = 60;

const FAILURES_BEFORE_BACKOFF = 5;
const BACKOFF_MULTIPLIER = 3;
const MAX_BACKOFF_MS = 5 * 60 * 1000;

const DEFAULT_CONFIG = Object.freeze({
	enabled: true,
	tickIntervalMs: 8000,
	batchSize: 4,
	maxPagesPerCall: 3
});

const GLOBAL_KEY = '__NEBRAS_HINDAWI_ENGINE__';
function getGlobalState() {
	if (!globalThis[GLOBAL_KEY]) {
		globalThis[GLOBAL_KEY] = {
			running: false,
			currentTickInFlight: false,
			timer: null,
			lastTickStartedAt: null,
			lastTickEndedAt: null,
			autoBootAttempted: false
		};
	}
	return globalThis[GLOBAL_KEY];
}

// ── RTDB helpers ─────────────────────────────────────────────────────
async function readConfig() {
	const snap = await getAdminDatabase().ref(CONFIG_PATH).get();
	if (!snap.exists()) return { ...DEFAULT_CONFIG };
	const v = snap.val() || {};
	return {
		enabled: v.enabled === undefined ? true : Boolean(v.enabled),
		tickIntervalMs: Math.max(2000, Number(v.tickIntervalMs) || DEFAULT_CONFIG.tickIntervalMs),
		batchSize: Math.max(1, Math.min(20, Number(v.batchSize) || DEFAULT_CONFIG.batchSize)),
		maxPagesPerCall: Math.max(1, Math.min(15, Number(v.maxPagesPerCall) || DEFAULT_CONFIG.maxPagesPerCall))
	};
}

async function writeConfig(patch) {
	const current = await readConfig();
	await getAdminDatabase().ref(CONFIG_PATH).set({ ...current, ...patch });
	return { ...current, ...patch };
}

async function readCursor() {
	const snap = await getAdminDatabase().ref(CURSOR_PATH).get();
	if (!snap.exists()) return { categoryIndex: 0, pages: {} };
	const v = snap.val() || {};
	return {
		categoryIndex: Math.max(0, Number(v.categoryIndex) || 0),
		pages: v.pages && typeof v.pages === 'object' ? v.pages : {}
	};
}

async function writeCursor(cursor) {
	await getAdminDatabase().ref(CURSOR_PATH).set({
		categoryIndex: Math.max(0, Number(cursor.categoryIndex) || 0),
		pages: cursor.pages && typeof cursor.pages === 'object' ? cursor.pages : {},
		updatedAt: { '.sv': 'timestamp' }
	});
}

async function readStats() {
	const snap = await getAdminDatabase().ref(STATS_PATH).get();
	const v = snap.exists() ? snap.val() || {} : {};
	return {
		totalFetched: Number(v.totalFetched) || 0,
		sectionsCreated: Number(v.sectionsCreated) || 0,
		lastRunAt: v.lastRunAt || null,
		lastError: v.lastError || null,
		runsCount: Number(v.runsCount) || 0,
		consecutiveEmptyRuns: Number(v.consecutiveEmptyRuns) || 0
	};
}

async function bumpStats(patch) {
	const ref = getAdminDatabase().ref(STATS_PATH);
	await ref.transaction((current) => {
		const c = current || {};
		return {
			totalFetched: Number(c.totalFetched ?? 0) + Number(patch.totalFetchedDelta ?? 0),
			sectionsCreated: Number(c.sectionsCreated ?? 0) + Number(patch.sectionsCreatedDelta ?? 0),
			runsCount: Number(c.runsCount ?? 0) + Number(patch.runsDelta ?? 0),
			lastRunAt: patch.touchLastRun ? Date.now() : (c.lastRunAt ?? null),
			lastError: patch.lastError !== undefined ? (patch.lastError ?? null) : (c.lastError ?? null),
			consecutiveEmptyRuns: Number(c.consecutiveEmptyRuns ?? 0)
		};
	});
}

async function appendLog(entry) {
	const db = getAdminDatabase();
	const id = `${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
	await db.ref(`${LOG_PATH}/${id}`).set({ ...entry, ts: Date.now() });
	const all = await db.ref(LOG_PATH).orderByChild('ts').get().catch(() => null);
	if (!all || !all.exists()) return;
	const entries = Object.entries(all.val() || {}).sort(
		(a, b) => Number(b[1]?.ts || 0) - Number(a[1]?.ts || 0)
	);
	if (entries.length > LOG_MAX_ENTRIES) {
		const updates = {};
		for (const [k] of entries.slice(LOG_MAX_ENTRIES)) updates[`${LOG_PATH}/${k}`] = null;
		await db.ref().update(updates);
	}
}

async function readLog(limit = 30) {
	const snap = await getAdminDatabase()
		.ref(LOG_PATH)
		.orderByChild('ts')
		.limitToLast(Math.max(1, Math.min(LOG_MAX_ENTRIES, Number(limit) || 30)))
		.get();
	if (!snap.exists()) return [];
	return Object.entries(snap.val() || {})
		.map(([id, v]) => ({ id, ...(v || {}) }))
		.sort((a, b) => Number(b.ts || 0) - Number(a.ts || 0));
}

// ── FCM ──────────────────────────────────────────────────────────────
const FCM_DEFAULT_TOPIC = 'nebras_all_users';
function fcmTopic() {
	return String(process?.env?.FCM_BROADCAST_TOPIC || '').trim() || FCM_DEFAULT_TOPIC;
}
function idToString(value) {
	return value === null || value === undefined ? '' : String(value).trim();
}
async function notifyFcmContentAdded(info) {
	if (!isAdminConfigured()) return;
	const chain = [info?.mainSectionName, info?.subSectionName, info?.secondarySectionName]
		.map((s) => (s || '').trim())
		.filter(Boolean);
	try {
		await sendTopicMessage({
			topic: fcmTopic(),
			title: 'محتوى جديد في نبراس',
			body: `تمت إضافة "${(info?.title || '').trim()}"${chain.length ? ` في ${chain.join(' › ')}` : ''}`,
			data: {
				type: 'content_added',
				source: 'hindawi_library_engine',
				contentType: 'document',
				// الاسم الحقيقيّ للمحتوى — يقرأه التطبيق ليعرض العنوان الصحيح
				// بدل عنوان العرض العامّ ("محتوى جديد في نبراس") عند فتح المحتوى من الإشعار.
				contentTitle: (info?.title || '').trim(),
				contentId: idToString(info?.contentId),
				mainSectionId: idToString(info?.mainSectionId),
				subSectionId: idToString(info?.subSectionId),
				secondarySectionId: idToString(info?.secondarySectionId),
				mainSectionName: info?.mainSectionName || '',
				subSectionName: info?.subSectionName || '',
				secondarySectionName: info?.secondarySectionName || '',
				sourceUrl: info?.sourceUrl || ''
			}
		});
	} catch (err) {
		await appendLog({
			level: 'warn',
			message: `إشعار FCM فشل: ${err?.message || String(err)}`,
			reason: 'fcm_send_failed'
		}).catch(() => {});
	}
}

// ── Core: process one book → قسم تصنيفه الحقيقيّ ──────────────────────
// categoryName = الاسم العربيّ لتصنيف هنداوي (التاريخ/الفلسفة/الأدب…) الذي
// جاء منه الكتاب. يصبح القسم الرئيسيّ، وتحته فرعيّ موحَّد «كتب هنداوي».
async function processBook({ url, bookId, categoryName }) {
	// 1) metadata (رابط PDF يُبنى من المعرّف)
	const meta = await fetchBookMetadata(url);
	if (!meta.fileUrl) {
		throw Object.assign(new Error(`لا رابط PDF لـ "${meta.title || bookId}".`), {
			reason: 'no_file_url',
			status: 422
		});
	}

	// 2) تنزيل الـ PDF فعلياً قبل أيّ كتابة (تحقّق magic bytes داخل الجالب)
	const downloaded = await downloadBookFile(meta.fileUrl, {
		refererUrl: meta.source?.url || url
	});
	if (!downloaded?.buffer || downloaded.buffer.byteLength === 0) {
		throw Object.assign(new Error('PDF فارغ.'), { reason: 'empty_download', status: 422 });
	}

	// 3) ضمان قسم التصنيف: رئيسيّ = اسم التصنيف، فرعيّ = «كتب هنداوي».
	const createdSectionsIds = [];
	let sectionsCreatedDelta = 0;

	const createdMain = await createMainSectionAdmin(categoryName);
	const mainId = String(createdMain.id);
	if (!createdMain.alreadyExisted) {
		createdSectionsIds.push(mainId);
		sectionsCreatedDelta += 1;
		await bumpStats({ sectionsCreatedDelta: 1 }).catch(() => {});
	}
	const createdSub = await createSubSectionAdmin(mainId, HINDAWI_SUB_NAME);
	const subId = String(createdSub.id);
	if (!createdSub.alreadyExisted) {
		createdSectionsIds.push(subId);
		sectionsCreatedDelta += 1;
		await bumpStats({ sectionsCreatedDelta: 1 }).catch(() => {});
	}

	const finalMetadata = {
		title: String(meta.title || '').trim(),
		description: String(meta.description || '').trim(),
		author: String(meta.author || '').trim(),
		thumbnail: meta.thumbnail || null,
		is_listed: true,
		content_type: 'document',
		main_section: mainId,
		main_section_id: mainId,
		main_section_name: String(createdMain.name || categoryName),
		subsection: subId,
		subsection_name: HINDAWI_SUB_NAME,
		secondary_subsection: null
	};

	const result = await adminUploadAndRegister({
		buffer: downloaded.buffer,
		contentType: downloaded.contentType,
		filename: downloaded.filename,
		thumbnailUrl: meta.thumbnail || null,
		metadata: finalMetadata,
		uploader: { uid: 'hindawi_library_engine', email: 'engine@nebras.local' },
		source: {
			provider: 'hindawi',
			url: meta.source?.url || url,
			bookId: meta.source?.bookId || bookId,
			license: 'creative_commons'
		}
	});

	await recordImported(bookId, {
		fileId: result.fileId,
		title: meta.title,
		url: meta.source?.url || url,
		hierarchy: { mainId, subId, secondaryId: null },
		createdSectionsIds
	});

	await notifyFcmContentAdded({
		title: meta.title,
		contentId: result.fileId,
		mainSectionId: mainId,
		subSectionId: subId,
		secondarySectionId: '',
		mainSectionName: String(createdMain.name || categoryName),
		subSectionName: HINDAWI_SUB_NAME,
		secondarySectionName: '',
		// نُرسل رابط التشغيل الفعليّ (Firebase Storage PDF) لا صفحة هنداوي
		// (`meta.source.url`): صفحة الهبوط HTML غير قابلة للتشغيل، وكان
		// التطبيق إن لجأ إلى رابط الحمولة يفتحها في مشغّل الفيديو فتفشل.
		sourceUrl: result.downloadUrl || ''
	});

	return {
		fileId: result.fileId,
		title: meta.title,
		hierarchy: {
			main: { id: mainId, name: String(createdMain.name || categoryName) },
			sub: { id: subId, name: HINDAWI_SUB_NAME },
			secondary: null
		},
		createdSectionsIds,
		sectionsCreatedDelta
	};
}

// ── Tick — يتنقّل بين تصنيفات هنداوي ──────────────────────────────────
export async function runEngineTick() {
	// ❄️ تجميد شامل: لا دورة جلب.
	if (INGEST_FROZEN) return { processed: 0, created: 0, skipped: 0, failed: 0, frozen: true };
	const cfg = await readConfig();
	const cats = HINDAWI_CATEGORIES;
	let cursor = await readCursor();
	if (cursor.categoryIndex >= cats.length) cursor.categoryIndex = 0;
	const category = cats[cursor.categoryIndex];
	const pages = { ...(cursor.pages || {}) };
	// مفاتيح RTDB لا تقبل . # $ / [ ] — وبعض الـ slugs فيها نقطة
	// (literary.criticism, science.fiction…). نُرمّز المفتاح بأمان.
	const pk = category.slug.replace(/[.#$/[\]]/g, '_');
	const startPage = Math.max(1, Number(pages[pk]) || 1);
	// round-robin: ننتقل لتصنيف مختلف في كل دورة → تتنوّع الأقسام بسرعة.
	const nextCat = (cursor.categoryIndex + 1) % cats.length;

	let knownIds;
	try {
		knownIds = (await partitionKnownBooks([])).knownIds;
	} catch {
		knownIds = new Set();
	}

	const discovery = await discoverNewBooksInCategory({
		slug: category.slug,
		startPage,
		batchSize: cfg.batchSize,
		maxPagesPerCall: cfg.maxPagesPerCall,
		knownIds
	});

	// إن نفد التصنيف الحاليّ أو لا جديد فيه → نُصفّر صفحته وننتقل للتالي.
	if (discovery.newBooks.length === 0 || discovery.exhausted) {
		pages[pk] = 1;
		await writeCursor({ categoryIndex: nextCat, pages });
		await appendLog({
			level: 'info',
			message: `تصنيف «${category.name}» استُنفد/لا جديد — الانتقال إلى «${cats[nextCat].name}».`,
			category: category.slug
		});
		return { processed: 0, created: 0, skipped: 0, failed: 0, category: category.name, cursor: { categoryIndex: nextCat }, sample: [] };
	}

	const sample = [];
	let processed = 0;
	let createdSectionsTotal = 0;
	let skipped = 0;
	let failed = 0;

	for (const link of discovery.newBooks) {
		if (await isBookImported(link.bookId).catch(() => false)) {
			skipped += 1;
			sample.push({ title: link.bookId, url: link.url, status: 'skip' });
			continue;
		}
		try {
			const r = await processBook({ url: link.url, bookId: link.bookId, categoryName: category.name });
			processed += 1;
			createdSectionsTotal += r.sectionsCreatedDelta;
			sample.push({ fileId: r.fileId, title: r.title, url: link.url, status: 'ok', hierarchy: r.hierarchy });
			await appendLog({
				level: 'success',
				message: `جُلِب: ${r.title} → ${r.hierarchy.main.name} › ${r.hierarchy.sub.name}`,
				url: link.url,
				bookId: link.bookId,
				fileId: r.fileId
			});
		} catch (err) {
			failed += 1;
			const reason = err?.reason || 'unknown';
			sample.push({ title: link.bookId, url: link.url, status: 'fail', error: err?.message || String(err) });
			await recordFailure(link.bookId, { reason, message: err?.message || String(err), url: link.url }).catch(() => {});
			await appendLog({ level: 'error', message: err?.message || String(err), url: link.url, bookId: link.bookId, reason });
		}
	}

	const nextPage = discovery.nextPage || startPage + 1;
	pages[pk] = nextPage;
	await writeCursor({ categoryIndex: nextCat, pages });

	await bumpStats({
		totalFetchedDelta: processed,
		runsDelta: 1,
		touchLastRun: true,
		lastError: failed > 0 ? `${failed} كتاب فشل في هذه الدورة.` : null
	});

	const stats = await readStats().catch(() => null);
	if (stats && processed === 0) {
		await getAdminDatabase()
			.ref(`${STATS_PATH}/consecutiveEmptyRuns`)
			.set(Number(stats.consecutiveEmptyRuns || 0) + 1)
			.catch(() => {});
	} else if (processed > 0) {
		await getAdminDatabase().ref(`${STATS_PATH}/consecutiveEmptyRuns`).set(0).catch(() => {});
	}

	return { processed, created: createdSectionsTotal, skipped, failed, category: category.name, cursor: { categoryIndex: cursor.categoryIndex, page: nextPage }, sample };
}

/** نقطة دخول Cron — تحترم إيقاف المستخدم الصريح. */
export async function runCronTick() {
	// ❄️ تجميد شامل: نُرجع skipped ليتوقّف حلقة الـ cron فوراً.
	if (INGEST_FROZEN) return { processed: 0, created: 0, skipped: true, failed: 0, frozen: true };
	const snap = await getAdminDatabase().ref(`${CONFIG_PATH}/enabled`).get().catch(() => null);
	const explicitlyDisabled = snap && snap.exists() && snap.val() === false;
	if (explicitlyDisabled) return { ok: true, skipped: true, reason: 'engine_stopped_by_user' };
	if (!snap || !snap.exists()) await writeConfig({ enabled: true });
	try {
		const result = await runEngineTick();
		return { ok: true, cron: true, ...result };
	} catch (err) {
		await bumpStats({ lastError: err?.message || String(err), touchLastRun: true }).catch(() => {});
		await appendLog({ level: 'error', message: `cron tick فشل: ${err?.message || String(err)}`, reason: err?.reason || 'cron_tick_failed' }).catch(() => {});
		return { ok: false, error: 'tick_failed', reason: err?.reason || 'unknown', message: err?.message || String(err) };
	}
}

// ── Background loop ──────────────────────────────────────────────────
async function tickLoop() {
	const state = getGlobalState();
	if (!state.running || state.currentTickInFlight) return;
	state.currentTickInFlight = true;
	state.lastTickStartedAt = Date.now();
	try {
		const cfg = await readConfig();
		if (!cfg.enabled) {
			state.running = false;
			if (state.timer) { clearTimeout(state.timer); state.timer = null; }
			await appendLog({ level: 'info', message: 'إيقاف المحرّك (enabled=false).' });
			return;
		}
		await runEngineTick();
	} catch (err) {
		await appendLog({ level: 'error', message: `tick فشل: ${err?.message || String(err)}`, reason: err?.reason || 'tick_failed' }).catch(() => {});
		await bumpStats({ lastError: err?.message || String(err), touchLastRun: true }).catch(() => {});
	} finally {
		state.currentTickInFlight = false;
		state.lastTickEndedAt = Date.now();
		if (state.running) {
			const cfg = await readConfig().catch(() => DEFAULT_CONFIG);
			const stats = await readStats().catch(() => null);
			let nextDelay = cfg.tickIntervalMs;
			if (Number(stats?.consecutiveEmptyRuns || 0) >= FAILURES_BEFORE_BACKOFF) {
				nextDelay = Math.min(cfg.tickIntervalMs * BACKOFF_MULTIPLIER, MAX_BACKOFF_MS);
			}
			state.timer = setTimeout(() => { tickLoop().catch(() => {}); }, nextDelay);
		}
	}
}

export async function startEngine() {
	// ❄️ تجميد شامل: لا تشغيل للمحرّك.
	if (INGEST_FROZEN) return { ok: false, frozen: true, reason: 'ingest_frozen' };
	const state = getGlobalState();
	const cfg = await writeConfig({ enabled: true });
	if (state.running) {
		await appendLog({ level: 'info', message: 'المحرّك يعمل بالفعل.' });
		return { running: true, alreadyRunning: true, config: cfg };
	}
	state.running = true;
	await appendLog({ level: 'info', message: 'بدء محرّك هنداوي.' });
	state.timer = setTimeout(() => { tickLoop().catch(() => {}); }, 100);
	return { running: true, alreadyRunning: false, config: cfg };
}

export async function stopEngine() {
	const state = getGlobalState();
	state.running = false;
	if (state.timer) { clearTimeout(state.timer); state.timer = null; }
	const cfg = await writeConfig({ enabled: false });
	await appendLog({ level: 'info', message: 'إيقاف المحرّك بطلب صريح.' });
	return { running: false, config: cfg };
}

export async function autoBootIfNeeded() {
	// ❄️ تجميد شامل: لا إقلاع تلقائي.
	if (INGEST_FROZEN) return { booted: false, reason: 'ingest_frozen', frozen: true };
	const state = getGlobalState();
	if (state.autoBootAttempted) return;
	state.autoBootAttempted = true;
	const cfg = await readConfig();
	if (cfg.enabled && !state.running) {
		state.running = true;
		await appendLog({ level: 'info', message: 'إعادة تشغيل تلقائي بعد إقلاع الخادم.' });
		state.timer = setTimeout(() => { tickLoop().catch(() => {}); }, 500);
	}
}

export async function resetCursor() {
	await writeCursor({ categoryIndex: 0, page: 1 });
	await appendLog({ level: 'info', message: 'إعادة المؤشّر إلى أوّل تصنيف/صفحة 1.' });
	return { categoryIndex: 0, page: 1 };
}

/**
 * Factory reset لمحتوى هنداوي فقط: يحذف كلّ سجلّ بعلامة __provider==='hindawi'
 * + يمسح registry/cursor. لا يلمس الأقسام (taxonomy مشتركة) ولا محتوى مصادر أخرى.
 */
export async function factoryReset() {
	const db = getAdminDatabase();
	const fs = getNebrasFirestoreAdmin();
	try { await stopEngine(); } catch { /* ignore */ }

	const [uploadsSnap, contentFilesSnap] = await Promise.all([
		fs.collection(NEBRAS_FS_UPLOADS).get(),
		fs.collection(NEBRAS_FS_CONTENT_FILES).get()
	]);

	const fileIds = new Set();
	let uploads = 0;
	let contentFiles = 0;
	if (!uploadsSnap.empty) {
		for (const d of uploadsSnap.docs) {
			if (d.data()?.__provider === 'hindawi') { fileIds.add(d.id); uploads += 1; }
		}
	}
	if (!contentFilesSnap.empty) {
		for (const d of contentFilesSnap.docs) {
			if (d.data()?.__provider === 'hindawi') { fileIds.add(d.id); contentFiles += 1; }
		}
	}

	await db.ref().update({
		hindawi_library_registry: null,
		hindawi_library_failures: null,
		[`${ENGINE_ROOT}/cursor`]: null,
		[`${ENGINE_ROOT}/stats`]: {
			totalFetched: 0,
			sectionsCreated: 0,
			runsCount: 0,
			lastRunAt: null,
			lastError: 'factory_reset',
			consecutiveEmptyRuns: 0
		}
	});
	await adminFsBulkDeleteFileMirrorIds([...fileIds]);
	await appendLog({ level: 'warn', message: `إعادة ضبط: حُذف ${uploads + contentFiles} كتاب هنداوي.`, reason: 'factory_reset' }).catch(() => {});
	return { ok: true, cleared: { uploads, content_files: contentFiles } };
}

export async function getEngineStatus({ logLimit = 30 } = {}) {
	await autoBootIfNeeded();
	const state = getGlobalState();
	const [cfg, cursor, stats, log] = await Promise.all([readConfig(), readCursor(), readStats(), readLog(logLimit)]);
	return {
		processRunning: state.running,
		currentTickInFlight: state.currentTickInFlight,
		lastTickStartedAt: state.lastTickStartedAt,
		lastTickEndedAt: state.lastTickEndedAt,
		config: cfg,
		cursor,
		stats,
		log
	};
}
