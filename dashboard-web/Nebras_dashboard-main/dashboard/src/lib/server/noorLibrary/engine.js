/**
 * engine.js — محرّك الجلب الآلي المستقلّ لمكتبة نور.
 *
 * ╔══════════════════════════════════════════════════════════════════╗
 * ║  🔒 Nebras Only — لا يلمس Mshcat/OldApp إطلاقاً.                  ║
 * ╚══════════════════════════════════════════════════════════════════╝
 *
 * المعمارية:
 *   • Singleton على مستوى الـ Node process (محفوظ في globalThis لتجاوز
 *     HMR في dev). يضمن وجود حلقة واحدة تعمل في كلّ لحظة.
 *   • العلامة `enabled` محفوظة في RTDB → يُعاد التشغيل عند start فقط من
 *     طلب صريح، أو يُلتقط عند أوّل status() بعد إقلاع الخادم لو enabled=true.
 *   • كلّ "tick" يجلب batch من البذرة الحاليّة، يصنّف، يرفع، يسجّل، ثمّ
 *     يقفز للبذرة التاليّة بعد استنفاد الحاليّة. الـ throttle بين الـ ticks
 *     يحدّده config.tickIntervalMs (افتراضي 8 ثوانٍ).
 *
 * مسارات RTDB المُستخدمة:
 *   noor_library_engine/config   — { enabled, seedUrls[], tickIntervalMs, batchSize, maxPagesPerCall }
 *   noor_library_engine/cursor   — { seedIndex, page }
 *   noor_library_engine/stats    — { totalFetched, sectionsCreated, lastRunAt, lastError, runsCount }
 *   noor_library_engine/log/{ts} — آخر 60 إدخال (إنجاز/خطأ/تخطّي)
 *   noor_library_registry/{id}   — السجلّ المركزي لمنع التكرار
 *
 * تحذير الإنتاج:
 *   على Vercel (serverless) لا تستمرّ الحلقة. للنشر هناك، نشغّل cron خارجي
 *   يطرق POST /api/admin/noor-library/engine/tick كلّ X دقيقة.
 *   داخل dev/Node adapter (long-running) الحلقة تعمل تلقائيّاً.
 */

import {
	getAdminDatabase,
	getNebrasFirestoreAdmin,
	isAdminConfigured,
	sendTopicMessage
} from '$lib/server/firebaseAdmin.js';
import {
	adminFsBulkDeleteSectionKeys,
	adminFsBulkDeleteFileMirrorIds
} from '$lib/server/nebrasUnifiedFirestoreAdmin.js';
import {
	NEBRAS_FS_SECTIONS,
	NEBRAS_FS_UPLOADS,
	NEBRAS_FS_CONTENT_FILES
} from '$lib/firebase/nebrasUnifiedPaths.js';
import { buildSectionsTree } from './sectionsTree.js';
import {
	DEFAULT_SEED_URLS,
	discoverNewBooks,
	isValidSeedUrl
} from './crawler.js';
import { fetchBookMetadata, downloadBookFile, parseNoorUrl } from './fetcher.js';
import { classifyAutonomous } from './classifier.js';
import {
	createMainSectionAdmin,
	createSubSectionAdmin,
	createSecondarySectionAdmin
} from './sectionsCreator.js';
import { adminUploadAndRegister, registerUploadedBook } from './adminUploader.js';
import { INGEST_FROZEN } from '../ingestFreeze.js';
import {
	isBookImported,
	partitionKnownBooks,
	recordImported,
	recordFailure
} from './registry.js';

// ملاحظة: لا يوجد إيقاف تلقائي للمحرّك — يستمرّ بالدوران أبداً حتى يطلب
// المستخدم الإيقاف صراحةً عبر /engine/stop. عند الفشل المتتالي نُسجِّل
// تحذيراً فقط ونزيد فترة الـ throttle تدريجياً (back-off) لتفادي ضرب
// المصدر، لكن لا نوقف المحرّك أبداً تلقائياً.
const FAILURES_BEFORE_BACKOFF = 5;
const BACKOFF_MULTIPLIER = 3; // tickInterval × 3 عند تجاوز العتبة
const MAX_BACKOFF_MS = 5 * 60 * 1000; // سقف 5 دقائق بين الدورات

const ENGINE_ROOT = 'noor_library_engine';
const CONFIG_PATH = `${ENGINE_ROOT}/config`;
const CURSOR_PATH = `${ENGINE_ROOT}/cursor`;
const STATS_PATH = `${ENGINE_ROOT}/stats`;
const LOG_PATH = `${ENGINE_ROOT}/log`;
const LOG_MAX_ENTRIES = 60;

const DEFAULT_CONFIG = Object.freeze({
	enabled: true,
	seedUrls: DEFAULT_SEED_URLS,
	tickIntervalMs: 8000,
	batchSize: 3,
	maxPagesPerCall: 4
});

// ╔══════════════════════════════════════════════════════════════════╗
// ║  🟢 محرّك «مكتبة نور» مُفعَّل — جلب آليّ بلا أيّ ذكاء اصطناعي.      ║
// ║                                                                    ║
// ║  أساس الامتثال (بدل الإيقاف الصارم السابق): نجلب **الكتب العامّة    ║
// ║  فقط** — أي القابلة للتحميل من مكتبة نور نفسها. الكتب «المحفوظة»     ║
// ║  و«متابعة النشر» غير متاحة للتحميل إطلاقاً في نور، فتُستبعَد آلياً:  ║
// ║    1) بوّابة توفّر مبكّرة (probeBookAvailability في fetcher.js) تقرأ ║
// ║       حالة الكتاب من نور (check_user) + وجود زرّ التحميل بالصفحة.    ║
// ║    2) بوّابة تنزيل فعليّ (GATE B): إن تعذّر تنزيل الملفّ فالكتاب غير  ║
// ║       عامّ ⇒ يُتخطّى بلا إنشاء أيّ قسم.                              ║
// ║  التصنيف heuristic محليّ بحت (classifier.js) — لا Gemini ولا أيّ     ║
// ║  خدمة خارجيّة.                                                      ║
// ║                                                                    ║
// ║  لإيقاف المحرّك مجدّداً عند الحاجة: اجعل القيمة true، وعلِّق سطر noor  ║
// ║  في .github/workflows/library-engines-cron.yml.                    ║
// ╚══════════════════════════════════════════════════════════════════╝
export const NOOR_ENGINE_HARD_DISABLED = false;

// ── Singleton state (per Node process) ───────────────────────────────
const GLOBAL_KEY = '__NEBRAS_NOOR_ENGINE__';
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
		// enabled غير محدّد = مُفعَّل (إقلاع تلقائي أوّل مثل IA/Hindawi).
		enabled: v.enabled === undefined ? true : Boolean(v.enabled),
		seedUrls:
			Array.isArray(v.seedUrls) && v.seedUrls.length > 0
				? v.seedUrls.filter(isValidSeedUrl)
				: DEFAULT_CONFIG.seedUrls,
		tickIntervalMs: Math.max(2000, Number(v.tickIntervalMs) || DEFAULT_CONFIG.tickIntervalMs),
		batchSize: Math.max(1, Math.min(20, Number(v.batchSize) || DEFAULT_CONFIG.batchSize)),
		maxPagesPerCall: Math.max(
			1,
			Math.min(15, Number(v.maxPagesPerCall) || DEFAULT_CONFIG.maxPagesPerCall)
		)
	};
}

async function writeConfig(patch) {
	const current = await readConfig();
	const next = { ...current, ...patch };
	if (Array.isArray(patch.seedUrls)) {
		next.seedUrls = patch.seedUrls.filter(isValidSeedUrl);
		if (next.seedUrls.length === 0) next.seedUrls = DEFAULT_CONFIG.seedUrls;
	}
	await getAdminDatabase().ref(CONFIG_PATH).set(next);
	return next;
}

async function readCursor() {
	const snap = await getAdminDatabase().ref(CURSOR_PATH).get();
	if (!snap.exists()) return { seedIndex: 0, page: 1 };
	const v = snap.val() || {};
	return {
		seedIndex: Math.max(0, Number(v.seedIndex) || 0),
		page: Math.max(1, Number(v.page) || 1)
	};
}

async function writeCursor(cursor) {
	await getAdminDatabase().ref(CURSOR_PATH).set({
		seedIndex: cursor.seedIndex,
		page: cursor.page,
		updatedAt: { '.sv': 'timestamp' }
	});
}

async function readStats() {
	const snap = await getAdminDatabase().ref(STATS_PATH).get();
	if (!snap.exists()) {
		return {
			totalFetched: 0,
			sectionsCreated: 0,
			lastRunAt: null,
			lastError: null,
			runsCount: 0
		};
	}
	const v = snap.val() || {};
	return {
		totalFetched: Number(v.totalFetched) || 0,
		sectionsCreated: Number(v.sectionsCreated) || 0,
		lastRunAt: v.lastRunAt || null,
		lastError: v.lastError || null,
		runsCount: Number(v.runsCount) || 0
	};
}

async function bumpStats(patch) {
	const ref = getAdminDatabase().ref(STATS_PATH);
	await ref.transaction((current) => {
		const c = current || {};
		// Firebase RTDB يرفض أيّ undefined داخل الـ transaction return.
		// لذا نحرص أن كلّ خاصيّة إمّا قيمة أو null (ليس undefined أبداً).
		const next = {
			totalFetched:
				Number(c.totalFetched ?? 0) + Number(patch.totalFetchedDelta ?? 0),
			sectionsCreated:
				Number(c.sectionsCreated ?? 0) + Number(patch.sectionsCreatedDelta ?? 0),
			runsCount: Number(c.runsCount ?? 0) + Number(patch.runsDelta ?? 0),
			lastRunAt: patch.touchLastRun ? Date.now() : (c.lastRunAt ?? null),
			lastError:
				patch.lastError !== undefined ? (patch.lastError ?? null) : (c.lastError ?? null),
			// نُبقي العدّاد المساعد لـ AUTO_STOP_AFTER_FAILED_RUNS بين العمليّات.
			consecutiveEmptyRuns: Number(c.consecutiveEmptyRuns ?? 0)
		};
		return next;
	});
}

async function appendLog(entry) {
	const db = getAdminDatabase();
	const id = `${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
	await db.ref(`${LOG_PATH}/${id}`).set({
		...entry,
		ts: Date.now()
	});
	// تنظيف ذاتي: نحتفظ فقط بآخر LOG_MAX_ENTRIES — نحذف ما زاد من القديم.
	const all = await db
		.ref(LOG_PATH)
		.orderByChild('ts')
		.get()
		.catch(() => null);
	if (!all || !all.exists()) return;
	const entries = Object.entries(all.val() || {}).sort(
		(a, b) => Number(b[1]?.ts || 0) - Number(a[1]?.ts || 0)
	);
	if (entries.length > LOG_MAX_ENTRIES) {
		const updates = {};
		for (const [k] of entries.slice(LOG_MAX_ENTRIES)) {
			updates[`${LOG_PATH}/${k}`] = null;
		}
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

// ── FCM notifications ────────────────────────────────────────────────
// نُرسل الإشعار من جانب الخادم مباشرةً (لا نمرّ عبر /api/notify لأنّ ذلك
// المسار يتطلّب طلباً خارجياً + auth). ندعم نفس الـ topic ونفس بنية الـ
// data payload التي تستعملها الواجهة عند الرفع اليدوي (notifyEvents.js)،
// حتى يستقبل تطبيق الموبايل المحتوى الآلي بنفس الشكل الذي يستقبل به اليدوي.
const FCM_DEFAULT_TOPIC = 'nebras_all_users';

function fcmTopic() {
	return (
		String(process?.env?.FCM_BROADCAST_TOPIC || '').trim() || FCM_DEFAULT_TOPIC
	);
}

function idToString(value) {
	if (value === null || value === undefined) return '';
	return String(value).trim();
}

async function notifyFcmContentAdded(info) {
	if (!isAdminConfigured()) return;
	const title = 'محتوى جديد في نبراس';
	const chain = [info?.mainSectionName, info?.subSectionName, info?.secondarySectionName]
		.map((s) => (s || '').trim())
		.filter(Boolean);
	const body = `تمت إضافة "${(info?.title || '').trim()}"${
		chain.length ? ` في ${chain.join(' › ')}` : ''
	}`;
	try {
		await sendTopicMessage({
			topic: fcmTopic(),
			title,
			body,
			data: {
				type: 'content_added',
				source: 'noor_library_engine',
				contentType: info?.contentType || 'document',
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
		// fire-and-forget: لا نُفشل الدورة بسبب خطأ FCM. نسجّل فقط.
		await appendLog({
			level: 'warn',
			message: `إشعار FCM (محتوى) فشل: ${err?.message || String(err)}`,
			reason: 'fcm_send_failed'
		}).catch(() => {});
	}
}

async function notifyFcmSectionCreated(info) {
	// 🔕 الإشعارات يجب أن تتعلّق بالمحتوى فقط لا الأقسام: عُطِّل إرسال إشعار
	// إنشاء القسم عمداً. إنشاء الأقسام نفسه يبقى يعمل بالكامل (الاستدعاءات
	// أدناه لم تُمسّ) — هذه الدالّة فقط لم تَعُد تُرسل أيّ إشعار.
	// للتراجع مستقبلاً: اجعل القيمة true.
	const NOTIFY_SECTION_CREATION = false;
	if (!NOTIFY_SECTION_CREATION) return;
	if (!isAdminConfigured()) return;
	const levelLabel =
		info?.level === 'main'
			? 'قسم رئيسي'
			: info?.level === 'sub'
				? 'قسم فرعي'
				: info?.level === 'secondary'
					? 'قسم ثانوي'
					: 'قسم';
	const name = (info?.name || '').trim();
	const parent = (info?.parentName || '').trim();
	const title = `${levelLabel} جديد في نبراس`;
	const body = parent
		? `تمّت إضافة ${levelLabel} "${name}" ضمن ${parent}`
		: `تمّت إضافة ${levelLabel} "${name}"`;
	const sectionId = idToString(info?.sectionId);
	const parentId = idToString(info?.parentId);
	const data = {
		type: 'section_created',
		source: 'noor_library_engine',
		level: info?.level || '',
		sectionName: name,
		parentName: parent,
		sectionId,
		parentId,
		mainSectionId: '',
		subSectionId: '',
		secondarySectionId: ''
	};
	if (info?.level === 'main') {
		data.mainSectionId = sectionId;
	} else if (info?.level === 'sub') {
		data.mainSectionId = parentId;
		data.subSectionId = sectionId;
	} else if (info?.level === 'secondary') {
		data.subSectionId = parentId;
		data.secondarySectionId = sectionId;
	}
	try {
		await sendTopicMessage({ topic: fcmTopic(), title, body, data });
	} catch (err) {
		await appendLog({
			level: 'warn',
			message: `إشعار FCM (قسم جديد) فشل: ${err?.message || String(err)}`,
			reason: 'fcm_send_failed'
		}).catch(() => {});
	}
}

// ── Core: process a single book end-to-end ──────────────────────────

/**
 * ينفّذ الدورة الكاملة لكتاب واحد بترتيب صارم يضمن **عدم إنشاء أيّ قسم**
 * إن لم يكن الكتاب قابلاً فعلاً للتنزيل والرفع. الترتيب:
 *
 *   1) metadata (يشمل استخراج fileUrl مع كلّ fallbacks Puppeteer)
 *   2) ✋ تحقُّق fileUrl — إن غاب، نرمي فوراً قبل أيّ كتابة (لا قسم، لا تصنيف)
 *   3) ✋ تنزيل الملفّ كـ Buffer في الذاكرة — إن فشل، نرمي قبل أيّ كتابة
 *   4) فقط الآن: تصنيف محليّ (مطابقة نصّيّة على شجرة الأقسام)
 *   5) فقط الآن: create sections إن لزم (نحن متأكّدون أنّ الكتاب جاهز)
 *   6) upload + write to RTDB
 *   7) register + FCM notify
 *
 * النتيجة: لا توجد أبداً أقسام يتيمة بلا كتب. الفشل في الخطوات 1-3 يُسجَّل
 * في registry فقط (blacklist تدريجي) دون أيّ أثر آخر في DB.
 */
async function processBook({ url, bookId, sections }) {
	// 1) جلب الميتاداتا + استخراج رابط الملفّ (مع Puppeteer fallback)، ثمّ
	//    نُكمل المسار المشترك (ingestResolvedBook).
	const meta = await fetchBookMetadata(url);
	return ingestResolvedBook({ url, bookId, meta, sections });
}

/**
 * المسار المشترك بعد توفّر الميتاداتا + رابط الملفّ: بوّابات (عامّ → رابط →
 * تنزيل فعليّ) ثمّ تصنيف محليّ ثمّ إنشاء الأقسام والرفع والتسجيل والإشعار.
 * يُستدعى من مكانين:
 *   • processBook — المحرّك الداخليّ (يجلب الميتاداتا بنفسه عبر متصفّح/الخادم).
 *   • endpoint `/api/admin/noor-library/ingest` — يمرّر ميتاداتا + رابط
 *     `internal_download` مُستخرَجاً بمتصفّح GitHub Action (CI)، والبايتات
 *     تُجلَب هنا بـ fetch عاديّ (الرابط عامّ) فيعمل حتى على Vercel.
 *
 * @param {{ url:string, bookId:string, meta:any, sections?:any }} args
 */
export async function ingestResolvedBook({ url, bookId, meta, sections }) {
	// ❄️ تجميد شامل: لا استيعاب لأيّ كتاب.
	if (INGEST_FROZEN) {
		const e = new Error('الجلب مُجمّد (INGEST_FROZEN) — لا يُقبل أيّ استيعاب.');
		e.reason = 'ingest_frozen';
		e.status = 503;
		throw e;
	}
	if (!sections) sections = await buildSectionsTree();

	// ─── GATE 0: كتب عامّة فقط (لا محفوظة/متابعة نشر) ────────────────────
	// مكتبة نور تتيح تحميل الكتب العامّة فقط؛ «المحفوظة» و«متابعة النشر»
	// غير قابلة للتحميل. نستبعدها هنا مبكّراً (قبل أيّ تصنيف/إنشاء قسم)
	// اعتماداً على فحص التوفّر (check_user + زرّ التحميل) في fetchBookMetadata.
	if (meta.availability && meta.availability.public === false) {
		throw Object.assign(
			new Error(
				`الكتاب "${meta.title || bookId}" غير عامّ (محفوظ/متابعة نشر) — غير متاح للتحميل في مكتبة نور، فتُخُطّي.`
			),
			{ reason: 'book_not_public', status: 422 }
		);
	}

	// حالة «مرفوع مسبقاً» (مسار الـ CI الموقَّع): البايتات في Storage فعلاً،
	// فلا نُنزّل ولا نحتاج fileUrl — نتخطّى GATE A/B ونمضي للتصنيف والتسجيل.
	const preUploaded = meta.__preUploaded || null;

	// ─── 2) GATE A: لا تتقدّم بدون رابط ملفّ (إلا إن رُفع مسبقاً) ─────────
	if (!preUploaded && !meta.fileUrl) {
		throw Object.assign(
			new Error(`لا يوجد رابط تنزيل قابل للاستخراج لـ "${meta.title || bookId}" — تخطّيناه قبل أيّ تعديل في DB.`),
			{ reason: 'no_file_url', status: 422 }
		);
	}

	// ─── 3) GATE B: نزّل الملفّ فعلياً قبل أيّ شيء آخر ───────────────────
	// إن فشل التنزيل (404/403/timeout)، نرمي بدون أن نُنشئ قسماً واحداً.
	// نمرّر refererUrl (صفحة الكتاب المصدرية) لكي يحصل المتصفّح على
	// كوكيز cf_clearance + Referer صحيح قبل تنزيل الـ PDF — هذا الذي
	// يفرق بين 403 ونجاح التنزيل عبر Cloudflare.
	let downloaded = null;
	if (!preUploaded) {
		downloaded = await downloadBookFile(meta.fileUrl, {
			refererUrl: meta.source?.url || meta.source?.finalUrl || url
		});
		if (!downloaded?.buffer || downloaded.buffer.byteLength === 0) {
			throw Object.assign(
				new Error('الملفّ المنزَّل فارغ — تخطّينا الكتاب قبل أيّ تعديل في DB.'),
				{ reason: 'empty_download', status: 422 }
			);
		}
	}

	// ─── 4) classify autonomously (الآن فقط — الكتاب في يدنا) ──────────
	const decision = await classifyAutonomous(sections, meta);

	// ─── 5) resolve final hierarchy (creating sections if needed) ─────
	let mainId = decision.mainId;
	let subId = decision.subId || null;
	let secondaryId = decision.secondaryId || null;
	const createdSectionsIds = [];
	let sectionsCreatedDelta = 0;

	if (decision.kind === 'create_main') {
		// أعلى مستوى من الإنشاء — main + sub أوّل تحته في عمليّة واحدة.
		const createdMain = await createMainSectionAdmin(decision.newMainName);
		mainId = String(createdMain.id);
		if (!createdMain.alreadyExisted) {
			createdSectionsIds.push(mainId);
			sectionsCreatedDelta += 1;
			await bumpStats({ sectionsCreatedDelta: 1 }).catch(() => {});
			await notifyFcmSectionCreated({
				level: 'main',
				name: createdMain.name,
				parentName: '',
				sectionId: createdMain.id,
				parentId: ''
			});
			await appendLog({
				level: 'success',
				message: `قسم رئيسي جديد أُنشئ آلياً: "${createdMain.name}"`,
				sectionId: createdMain.id,
				kind: 'main_section_created'
			}).catch(() => {});
		}

		const createdSub = await createSubSectionAdmin(mainId, decision.newSubName);
		subId = String(createdSub.id);
		if (!createdSub.alreadyExisted) {
			createdSectionsIds.push(subId);
			sectionsCreatedDelta += 1;
			await bumpStats({ sectionsCreatedDelta: 1 }).catch(() => {});
			await notifyFcmSectionCreated({
				level: 'sub',
				name: createdSub.name,
				parentName: createdMain.name,
				sectionId: createdSub.id,
				parentId: mainId
			});
			await appendLog({
				level: 'success',
				message: `قسم فرعي جديد أُنشئ آلياً: "${createdSub.name}" تحت "${createdMain.name}"`,
				sectionId: createdSub.id,
				parentId: mainId,
				kind: 'sub_section_created'
			}).catch(() => {});
		}
	} else if (decision.kind === 'create_sub') {
		const created = await createSubSectionAdmin(mainId, decision.newSubName);
		subId = String(created.id);
		if (!created.alreadyExisted) {
			createdSectionsIds.push(subId);
			sectionsCreatedDelta += 1;
			// تحديث الإحصائيات فوراً لأنّ القسم أُنشئ فعلاً في DB. لا ننتظر
			// نجاح الكتاب — لو فشل التنزيل يبقى القسم محسوباً.
			await bumpStats({ sectionsCreatedDelta: 1 }).catch(() => {});
			const parentMain = sections.index.mainsById[mainId];
			await notifyFcmSectionCreated({
				level: 'sub',
				name: created.name,
				parentName: parentMain?.name || '',
				sectionId: created.id,
				parentId: mainId
			});
			await appendLog({
				level: 'success',
				message: `قسم فرعي جديد أُنشئ آلياً: "${created.name}" تحت "${parentMain?.name || ''}"`,
				sectionId: created.id,
				parentId: mainId,
				kind: 'sub_section_created'
			}).catch(() => {});
		}
	} else if (decision.kind === 'create_secondary') {
		subId = decision.subId;
		const created = await createSecondarySectionAdmin(subId, decision.newSecondaryName);
		secondaryId = String(created.id);
		if (!created.alreadyExisted) {
			createdSectionsIds.push(secondaryId);
			sectionsCreatedDelta += 1;
			await bumpStats({ sectionsCreatedDelta: 1 }).catch(() => {});
			const parentSub = sections.index.subsById[subId];
			await notifyFcmSectionCreated({
				level: 'secondary',
				name: created.name,
				parentName: parentSub?.name || '',
				sectionId: created.id,
				parentId: subId
			});
			await appendLog({
				level: 'success',
				message: `قسم ثانوي جديد أُنشئ آلياً: "${created.name}" تحت "${parentSub?.name || ''}"`,
				sectionId: created.id,
				parentId: subId,
				kind: 'secondary_section_created'
			}).catch(() => {});
		}
	}

	// إن غاب القسم الفرعيّ بعد التصنيف (قسم رئيسيّ بلا فروع)، ننشئ بنية
	// منظّمة تلقائياً بدل رفض الكتاب: رئيسيّ «مكتبة نور» → فرعيّ حسب تصنيفه.
	if (!subId) {
		const createdMain = await createMainSectionAdmin('مكتبة نور');
		mainId = String(createdMain.id);
		if (!createdMain.alreadyExisted) {
			createdSectionsIds.push(mainId);
			sectionsCreatedDelta += 1;
			await bumpStats({ sectionsCreatedDelta: 1 }).catch(() => {});
		}
		const hint = Array.isArray(meta.categoryHints) ? (meta.categoryHints[0] || '') : '';
		const subName = String(hint || '').trim().slice(0, 60) || 'كتب عامة';
		const createdSub = await createSubSectionAdmin(mainId, subName);
		subId = String(createdSub.id);
		if (!createdSub.alreadyExisted) {
			createdSectionsIds.push(subId);
			sectionsCreatedDelta += 1;
			await bumpStats({ sectionsCreatedDelta: 1 }).catch(() => {});
		}
	}

	// إعادة قراءة الأقسام (لجلب أسماء الأقسام الجديدة).
	const refreshed = await buildSectionsTree();
	const main = refreshed.index.mainsById[mainId];
	const sub = refreshed.index.subsById[subId];
	const secondary = secondaryId ? refreshed.index.secondariesById[secondaryId] : null;

	if (!main || !sub) {
		throw Object.assign(new Error('main أو sub لم يُعثر عليه بعد التصنيف.'), {
			reason: 'hierarchy_resolution_failed',
			status: 500
		});
	}

	// (الخطوتان 2-3: GATE A/B تمّتا فوق قبل أيّ كتابة في DB.
	//  الـ buffer جاهز في `downloaded` ونحن متأكّدون أنّ الكتاب صالح.)

	// 6) upload + write to RTDB (dashboard_uploads + content_unified/files)
	const finalMetadata = {
		title: String(meta.title || '').trim(),
		description: String(meta.description || '').trim(),
		author: String(meta.author || '').trim(),
		thumbnail: meta.thumbnail || null,
		is_listed: true,
		main_section: String(main.id),
		main_section_id: String(main.id),
		main_section_name: String(main.name || ''),
		subsection: String(sub.id),
		subsection_name: String(sub.name || ''),
		...(secondary
			? {
					secondary_subsection: String(secondary.id),
					secondary_subsection_name: String(secondary.name || '')
				}
			: { secondary_subsection: null })
	};

	const source = {
		provider: 'noor-library',
		url: meta.source?.url || url,
		bookId: meta.source?.bookId || bookId
	};
	const result = preUploaded
		? await registerUploadedBook({
				fileId: preUploaded.fileId,
				objectPath: preUploaded.objectPath,
				downloadUrl: preUploaded.downloadUrl,
				token: preUploaded.token,
				size: preUploaded.size,
				contentType: preUploaded.contentType,
				filename: preUploaded.filename || 'book.pdf',
				thumbnailUrl: meta.thumbnail || null,
				metadata: finalMetadata,
				source
			})
		: await adminUploadAndRegister({
				buffer: downloaded.buffer,
				contentType: downloaded.contentType,
				filename: downloaded.filename,
				thumbnailUrl: meta.thumbnail || null,
				metadata: finalMetadata,
				uploader: { uid: 'noor_library_engine', email: 'engine@nebras.local' },
				source
			});

	// 7) سجّل في registry لمنع التكرار
	await recordImported(bookId, {
		fileId: result.fileId,
		title: meta.title,
		url: meta.source?.url || url,
		hierarchy: { mainId: String(main.id), subId: String(sub.id), secondaryId: secondary ? String(secondary.id) : null },
		createdSectionsIds
	});

	// 8) إشعار FCM لكلّ مستخدمي التطبيق — المحتوى الآلي يُعامَل تماماً
	//    كاليدوي. لا يستثنى الجلب الآلي من الإشعارات.
	await notifyFcmContentAdded({
		title: meta.title,
		contentType: finalMetadata.content_type || 'document',
		contentId: result.fileId,
		mainSectionId: main.id,
		subSectionId: sub.id,
		secondarySectionId: secondary?.id || '',
		mainSectionName: main.name,
		subSectionName: sub.name,
		secondarySectionName: secondary?.name || '',
		// رابط التشغيل الفعليّ (Firebase Storage) لا صفحة المصدر الخارجيّة:
		// صفحة الهبوط غير قابلة للتشغيل في مشغّلات التطبيق.
		sourceUrl: result.downloadUrl || ''
	});

	return {
		fileId: result.fileId,
		title: meta.title,
		downloadUrl: result.downloadUrl,
		hierarchy: {
			main: { id: String(main.id), name: main.name },
			sub: { id: String(sub.id), name: sub.name },
			secondary: secondary ? { id: String(secondary.id), name: secondary.name } : null
		},
		createdSectionsIds,
		sectionsCreatedDelta,
		decisionKind: decision.kind,
		decisionConfidence: decision.confidence,
		decisionReasoning: decision.reasoning,
		method: decision.method
	};
}

// ── Tick: one iteration (one batch) ─────────────────────────────────

/**
 * ينفّذ دورة واحدة من المحرّك. يمكن استدعاؤها يدويّاً (cron) أو من
 * الحلقة الداخليّة. تفترض أنّ enabled=true.
 *
 * @returns {Promise<{
 *   processed: number,
 *   created: number,
 *   skipped: number,
 *   failed: number,
 *   advancedToNextSeed: boolean,
 *   cursor: { seedIndex:number, page:number },
 *   sample: Array<{ fileId?:string, title:string, url:string, status:'ok'|'skip'|'fail', error?:string }>
 * }>}
 */
export async function runEngineTick() {
	// ❄️ تجميد شامل: لا دورة جلب.
	if (INGEST_FROZEN) return { processed: 0, created: 0, skipped: 0, failed: 0, frozen: true };
	if (NOOR_ENGINE_HARD_DISABLED) {
		return { ok: true, skipped: true, reason: 'noor_engine_hard_disabled' };
	}
	const cfg = await readConfig();
	if (cfg.seedUrls.length === 0) {
		throw Object.assign(new Error('لا توجد بذور (seedUrls) — أضف على الأقل واحدة.'), {
			reason: 'no_seeds',
			status: 400
		});
	}

	let cursor = await readCursor();
	if (cursor.seedIndex >= cfg.seedUrls.length) {
		// نعود للبداية (ندور باستمرار).
		cursor = { seedIndex: 0, page: 1 };
	}

	const seedUrl = cfg.seedUrls[cursor.seedIndex];

	// 1) اكتشاف روابط جديدة على البذرة الحاليّة
	let knownIds;
	try {
		knownIds = (await partitionKnownBooks([])).knownIds; // يعيد كلّ المعروف
	} catch {
		knownIds = new Set();
	}

	const discovery = await discoverNewBooks({
		seedUrl,
		startPage: cursor.page,
		batchSize: cfg.batchSize,
		maxPagesPerCall: cfg.maxPagesPerCall,
		knownIds
	});

	// 2) إن لم نجد جديداً → نتقدّم للبذرة التاليّة (أو نلفّ).
	let advancedToNextSeed = false;
	if (discovery.newBooks.length === 0 || discovery.exhausted) {
		const nextSeed = (cursor.seedIndex + 1) % cfg.seedUrls.length;
		cursor = { seedIndex: nextSeed, page: 1 };
		advancedToNextSeed = true;
		await writeCursor(cursor);
		await appendLog({
			level: 'info',
			message: `استُنفدت بذرة "${seedUrl}" — التحوّل للبذرة التاليّة.`,
			seedIndex: cursor.seedIndex
		});
		return {
			processed: 0,
			created: 0,
			skipped: 0,
			failed: 0,
			advancedToNextSeed,
			cursor,
			sample: []
		};
	}

	// 3) قراءة الشجرة الحاليّة مرّة واحدة لكلّ batch
	let sections;
	try {
		sections = await buildSectionsTree();
	} catch (err) {
		await bumpStats({ touchLastRun: true, lastError: `sections_read_failed: ${err?.message}` });
		throw err;
	}

	// 4) معالجة كلّ كتاب
	const sample = [];
	let processed = 0;
	let createdSectionsTotal = 0;
	let skipped = 0;
	let failed = 0;

	for (const link of discovery.newBooks) {
		// double-check سريع (race-condition بين discoverNewBooks وكتاب آخر مُسجَّل في الأثناء)
		if (await isBookImported(link.bookId).catch(() => false)) {
			skipped += 1;
			sample.push({ title: link.bookId, url: link.url, status: 'skip' });
			continue;
		}

		try {
			const r = await processBook({ url: link.url, bookId: link.bookId, sections });
			processed += 1;
			createdSectionsTotal += r.sectionsCreatedDelta;
			sample.push({
				fileId: r.fileId,
				title: r.title,
				url: link.url,
				status: 'ok',
				hierarchy: r.hierarchy,
				createdSectionsIds: r.createdSectionsIds,
				decision: r.decisionKind,
				confidence: r.decisionConfidence
			});
			await appendLog({
				level: 'success',
				message: `جُلِب: ${r.title}`,
				url: link.url,
				bookId: link.bookId,
				fileId: r.fileId,
				hierarchy: r.hierarchy,
				createdSectionsIds: r.createdSectionsIds,
				decision: r.decisionKind
			});
		} catch (err) {
			failed += 1;
			const reason = err?.reason || 'unknown';
			sample.push({
				title: link.bookId,
				url: link.url,
				status: 'fail',
				error: err?.message || String(err)
			});
			// blacklist تدريجي: نسجّل الفشل لكي يتمّ تجاوزه نهائياً بعد العتبة.
			await recordFailure(link.bookId, {
				reason,
				message: err?.message || String(err),
				url: link.url
			}).catch(() => {});
			await appendLog({
				level: 'error',
				message: err?.message || String(err),
				url: link.url,
				bookId: link.bookId,
				reason
			});
		}
	}

	// 5) تحديث المؤشّر
	if (discovery.nextPage) {
		cursor = { seedIndex: cursor.seedIndex, page: discovery.nextPage };
	} else {
		const nextSeed = (cursor.seedIndex + 1) % cfg.seedUrls.length;
		cursor = { seedIndex: nextSeed, page: 1 };
		advancedToNextSeed = true;
	}
	await writeCursor(cursor);

	// 6) تحديث الإحصائيات. ملاحظة: sectionsCreated يُحدَّث **فور** إنشاء كل قسم
	//    داخل processBook، لذا لا نمرّره هنا ثانية لتفادي العدّ المضاعف.
	await bumpStats({
		totalFetchedDelta: processed,
		runsDelta: 1,
		touchLastRun: true,
		lastError:
			failed > 0
				? `${failed} كتاب فشل في هذه الدورة (يُسجَّل في blacklist بعد ${
						/* عتبة من registry.js */ 3
					} محاولات).`
				: null
	});

	// 7) تتبُّع الدورات الفارغة المتتالية لتطبيق back-off تكيُّفي
	//    (من غير إيقاف المحرّك إطلاقاً — المستخدم وحده يوقفه).
	const stats = await readStats().catch(() => null);
	if (stats && processed === 0) {
		const consecutive = Number(stats?.consecutiveEmptyRuns || 0) + 1;
		await getAdminDatabase()
			.ref(`${STATS_PATH}/consecutiveEmptyRuns`)
			.set(consecutive)
			.catch(() => {});
		// نسجّل تحذيراً واحداً عند بلوغ العتبة (لا نُكرّره كلّ دورة).
		if (consecutive === FAILURES_BEFORE_BACKOFF) {
			await appendLog({
				level: 'warn',
				message: `${consecutive} دورة متتالية بدون أيّ نجاح — تفعيل back-off (تباطؤ الفترة بين الدورات). المحرّك يستمرّ بالعمل.`,
				reason: 'engine_backoff_engaged'
			}).catch(() => {});
		}
	} else if (processed > 0) {
		await getAdminDatabase()
			.ref(`${STATS_PATH}/consecutiveEmptyRuns`)
			.set(0)
			.catch(() => {});
	}

	return {
		processed,
		created: createdSectionsTotal,
		skipped,
		failed,
		advancedToNextSeed,
		cursor,
		sample
	};
}

/**
 * نقطة دخول الـ Cron (Vercel/GitHub Action). على serverless لا تستمرّ الحلقة
 * في الذاكرة، فالـ cron هو المُحرّك الفعليّ: ينفّذ tick واحداً في كلّ نداء.
 *
 *   • إن أوقف المستخدم المحرّك صراحةً (enabled=false) → نتخطّى بهدوء.
 *   • إن غاب enabled (أوّل تشغيل) → نعتبره مفعَّلاً ونمضي (مثل سلوك IA).
 *   • نُمسك أي خطأ ونعيده كنتيجة بدل أن نُسقط النداء.
 */
export async function runCronTick() {
	// ❄️ تجميد شامل: نُرجع skipped ليتوقّف حلقة الـ cron فوراً.
	if (INGEST_FROZEN) return { processed: 0, created: 0, skipped: true, failed: 0, frozen: true };
	// مفتاح الإيقاف (معطَّل الآن = المحرّك يعمل). إن أُعيد رفعه مستقبلاً يتوقّف.
	if (NOOR_ENGINE_HARD_DISABLED) {
		return { ok: true, skipped: true, reason: 'noor_engine_hard_disabled' };
	}
	// إقلاع تلقائيّ بلا تدخّل (مثل Internet Archive وHindawi): الغياب/أوّل
	// تشغيل = مُفعَّل. يتوقّف فقط إن أوقفه المستخدم صراحةً (enabled=false).
	const snap = await getAdminDatabase().ref(`${CONFIG_PATH}/enabled`).get().catch(() => null);
	if (!snap || !snap.exists()) {
		await writeConfig({ enabled: true }).catch(() => {});
	}
	const enabled = !snap || !snap.exists() ? true : snap.val() !== false;
	if (!enabled) {
		return { ok: true, skipped: true, reason: 'engine_disabled_by_user' };
	}
	try {
		const result = await runEngineTick();
		return { ok: true, cron: true, ...result };
	} catch (err) {
		await bumpStats({ lastError: err?.message || String(err), touchLastRun: true }).catch(() => {});
		await appendLog({
			level: 'error',
			message: `cron tick فشل: ${err?.message || String(err)}`,
			reason: err?.reason || 'cron_tick_failed'
		}).catch(() => {});
		return { ok: false, error: 'tick_failed', reason: err?.reason || 'unknown', message: err?.message || String(err) };
	}
}

// ── Background loop control ─────────────────────────────────────────

async function tickLoop() {
	const state = getGlobalState();
	if (!state.running) return;
	if (state.currentTickInFlight) return;

	state.currentTickInFlight = true;
	state.lastTickStartedAt = Date.now();

	try {
		const cfg = await readConfig();
		if (!cfg.enabled) {
			// تمّ إيقاف العلامة من الخارج → أوقف الحلقة.
			state.running = false;
			if (state.timer) {
				clearTimeout(state.timer);
				state.timer = null;
			}
			await appendLog({
				level: 'info',
				message: 'إيقاف المحرّك (enabled=false في الإعدادات).'
			});
			return;
		}
		await runEngineTick();
	} catch (err) {
		await appendLog({
			level: 'error',
			message: `tick فشل: ${err?.message || String(err)}`,
			reason: err?.reason || 'tick_failed'
		}).catch(() => {});
		await bumpStats({ lastError: err?.message || String(err), touchLastRun: true }).catch(
			() => {}
		);
	} finally {
		state.currentTickInFlight = false;
		state.lastTickEndedAt = Date.now();

		if (state.running) {
			const cfg = await readConfig().catch(() => DEFAULT_CONFIG);
			// back-off تكيُّفي: إن تتالت دورات بلا نجاح، نزيد الفاصل تدريجياً
			// (إلى MAX_BACKOFF_MS) لتفادي ضرب المصدر، لكنّنا لا نوقف المحرّك.
			const stats = await readStats().catch(() => null);
			const consecutiveEmpty = Number(stats?.consecutiveEmptyRuns || 0);
			let nextDelay = cfg.tickIntervalMs;
			if (consecutiveEmpty >= FAILURES_BEFORE_BACKOFF) {
				nextDelay = Math.min(
					cfg.tickIntervalMs * BACKOFF_MULTIPLIER,
					MAX_BACKOFF_MS
				);
			}
			state.timer = setTimeout(() => {
				tickLoop().catch(() => {});
			}, nextDelay);
		}
	}
}

/**
 * يبدأ المحرّك في الخلفية. آمن للاستدعاء أكثر من مرّة (idempotent).
 */
export async function startEngine() {
	// ❄️ تجميد شامل: لا تشغيل للمحرّك.
	if (INGEST_FROZEN) return { ok: false, frozen: true, reason: 'ingest_frozen' };
	if (NOOR_ENGINE_HARD_DISABLED) {
		return {
			ok: false,
			started: false,
			reason: 'noor_engine_hard_disabled',
			message: 'محرّك نور موقوف بمفتاح إيقاف صارم (امتثال حقوق النشر). لإعادة تفعيله اجعل NOOR_ENGINE_HARD_DISABLED=false بعد ضبط فلتر الترخيص.'
		};
	}
	const state = getGlobalState();
	const cfg = await writeConfig({ enabled: true });

	if (state.running) {
		await appendLog({ level: 'info', message: 'المحرّك يعمل بالفعل — تمّ تأكيد التشغيل.' });
		return { running: true, alreadyRunning: true, config: cfg };
	}

	state.running = true;
	await appendLog({ level: 'info', message: 'بدء المحرّك الآلي.' });
	// أوّل tick فوراً
	state.timer = setTimeout(() => {
		tickLoop().catch(() => {});
	}, 100);
	return { running: true, alreadyRunning: false, config: cfg };
}

/**
 * يوقف المحرّك. يطفئ علامة enabled في الـ DB ويُلغي المؤقّت في الذاكرة.
 */
export async function stopEngine() {
	const state = getGlobalState();
	state.running = false;
	if (state.timer) {
		clearTimeout(state.timer);
		state.timer = null;
	}
	const cfg = await writeConfig({ enabled: false });
	await appendLog({ level: 'info', message: 'إيقاف المحرّك بطلب صريح.' });
	return { running: false, config: cfg };
}

/**
 * إن كان enabled=true في DB ولا حلقة في الذاكرة، نُعيد التشغيل تلقائياً.
 * يُستدعى من /engine/status لكي يصمد المحرّك عبر إعادات تشغيل dev server.
 */
export async function autoBootIfNeeded() {
	// ❄️ تجميد شامل: لا إقلاع تلقائي.
	if (INGEST_FROZEN) return { booted: false, reason: 'ingest_frozen', frozen: true };
	const state = getGlobalState();
	if (state.autoBootAttempted) return;
	state.autoBootAttempted = true;

	const cfg = await readConfig();
	if (cfg.enabled && !state.running) {
		state.running = true;
		await appendLog({
			level: 'info',
			message: 'إعادة تشغيل تلقائي للمحرّك بعد إقلاع الخادم (enabled=true في DB).'
		});
		state.timer = setTimeout(() => {
			tickLoop().catch(() => {});
		}, 500);
	}
}

/**
 * تحديث البذور (seedUrls) من واجهة لوحة التحكّم. يحذف البذور غير الصالحة.
 *
 * @param {string[]} seedUrls
 */
export async function updateSeedUrls(seedUrls) {
	const filtered = (seedUrls || []).filter(isValidSeedUrl);
	const cfg = await writeConfig({ seedUrls: filtered });
	// إعادة المؤشّر للبداية لو غُيّرت البذور.
	await writeCursor({ seedIndex: 0, page: 1 });
	await appendLog({
		level: 'info',
		message: `تمّ تحديث البذور (${cfg.seedUrls.length} رابط) — إعادة المؤشّر إلى البذرة الأولى.`
	});
	return cfg;
}

/**
 * إعادة تعيين المؤشّر فقط (مفيد للبدء من الصفر دون مسح السجلّ).
 */
export async function resetCursor() {
	await writeCursor({ seedIndex: 0, page: 1 });
	await appendLog({ level: 'info', message: 'إعادة تعيين المؤشّر إلى البذرة الأولى/صفحة 1.' });
	return { seedIndex: 0, page: 1 };
}

// ╔══════════════════════════════════════════════════════════════════╗
// ║  Factory Reset — مسح شامل لكلّ ما أحدثه المحرّك (Clean Sweep)     ║
// ╚══════════════════════════════════════════════════════════════════╝

/**
 * "الزرّ النووي": يمسح كلّ ما أحدثه المحرّك الآلي في قاعدة البيانات
 * **دون لمس أيّ محتوى أو قسم أنشأه مديرٌ بشريّ**.
 *
 * الخطوات (كلّها عبر multi-path update واحدة قدر الإمكان):
 *   1) إيقاف المحرّك (enabled=false) لمنع كتابات جديدة أثناء المسح.
 *   2) مسح `noor_library_registry` كاملاً + `noor_library_engine/cursor`.
 *      نُبقي `engine/config` (البذور والإعدادات) و `engine/stats` (تاريخ
 *      عدّاد إجمالي، يُصفَّر هنا) و `engine/log` (للسجلّ التاريخي).
 *   3) مسح كلّ قسم (main/sub/secondary) يحمل علامة
 *      `__createdBy: 'noor_library_engine'`.
 *   4) مسح كلّ سجلّ في `dashboard_uploads` و `content_unified/files`
 *      يحمل علامة `__provider: 'noor-library'`.
 *
 * **لا يلمس Storage**: ملفّات Storage تبقى لتفادي تكاليف عمليّات حذف
 * بالآلاف، لكنّها تصبح يتيمة ولا يقرأها التطبيق لأنّ سجلّاتها مُسحت.
 * يمكن إضافة GC لاحق إن لزم.
 *
 * @returns {Promise<{
 *   ok: true,
 *   cleared: {
 *     registry: number,
 *     failures: number,
 *     uploads: number,
 *     content_files: number,
 *     mains: number,
 *     subs: number,
 *     secondaries: number
 *   }
 * }>}
 */
export async function factoryReset() {
	const db = getAdminDatabase();
	const fs = getNebrasFirestoreAdmin();

	// 1) أوقف المحرّك أولاً لمنع تداخل الكتابات.
	try {
		await stopEngine();
	} catch {
		// تجاهل — المحرّك ربّما لم يكن يعمل.
	}

	// 2) قراءة كلّ ما يلزم للحذف. نقرأ بالتوازي لخفض الزمن.
	const [
		registrySnap,
		failuresSnap,
		mainSnap,
		subSnap,
		secSnap,
		uploadsSnap,
		contentFilesSnap
	] = await Promise.all([
		db.ref('noor_library_registry').get(),
		db.ref('noor_library_failures').get(),
		fs.collection(NEBRAS_FS_SECTIONS).doc('main').get(),
		fs.collection(NEBRAS_FS_SECTIONS).doc('sub').get(),
		fs.collection(NEBRAS_FS_SECTIONS).doc('secondary').get(),
		fs.collection(NEBRAS_FS_UPLOADS).get(),
		fs.collection(NEBRAS_FS_CONTENT_FILES).get()
	]);

	const updates = {};
	const cleared = {
		registry: 0,
		failures: 0,
		uploads: 0,
		content_files: 0,
		mains: 0,
		subs: 0,
		secondaries: 0
	};

	// 2a) مسح السجلّ + سجلّ الفشل + المؤشّر
	if (registrySnap.exists()) {
		const regs = registrySnap.val() || {};
		cleared.registry = Object.keys(regs).length;
		updates['noor_library_registry'] = null;
	}
	if (failuresSnap.exists()) {
		const fails = failuresSnap.val() || {};
		cleared.failures = Object.keys(fails).length;
		updates['noor_library_failures'] = null;
	}
	updates['noor_library_engine/cursor'] = null;
	// تصفير العدّادات الإجماليّة (يبقى السجلّ التاريخي + الإعدادات).
	updates['noor_library_engine/stats'] = {
		totalFetched: 0,
		sectionsCreated: 0,
		runsCount: 0,
		lastRunAt: null,
		lastError: 'factory_reset',
		consecutiveEmptyRuns: 0
	};

	// 2b) مسح أقسام المحرّك (main/sub/secondary) فقط ما حُمل علامة __createdBy
	const enginesMains = new Set();
	const enginesSubs = new Set();
	const enginesSecs = new Set();

	if (mainSnap.exists) {
		for (const [id, val] of Object.entries(mainSnap.data() || {})) {
			if (val?.__createdBy === 'noor_library_engine') {
				enginesMains.add(String(id));
				cleared.mains += 1;
			}
		}
	}
	if (subSnap.exists) {
		for (const [id, val] of Object.entries(subSnap.data() || {})) {
			const parentMainId = String(val?.main_section ?? '');
			// نمسح إذا (أ) القسم نفسه أنشأه المحرّك، أو (ب) أبَه سيُمسح (يتيم).
			if (val?.__createdBy === 'noor_library_engine' || enginesMains.has(parentMainId)) {
				enginesSubs.add(String(id));
				cleared.subs += 1;
			}
		}
	}
	if (secSnap.exists) {
		for (const [id, val] of Object.entries(secSnap.data() || {})) {
			const parentSubId = String(val?.sub_section ?? '');
			if (val?.__createdBy === 'noor_library_engine' || enginesSubs.has(parentSubId)) {
				enginesSecs.add(String(id));
				cleared.secondaries += 1;
			}
		}
	}

	// 2c) مسح الكتب التي رفعها المحرّك (__provider === 'noor-library')
	const fileIdsToMirrorDelete = new Set();
	if (!uploadsSnap.empty) {
		for (const d of uploadsSnap.docs) {
			if (d.data()?.__provider === 'noor-library') {
				fileIdsToMirrorDelete.add(d.id);
				cleared.uploads += 1;
			}
		}
	}
	if (!contentFilesSnap.empty) {
		for (const d of contentFilesSnap.docs) {
			if (d.data()?.__provider === 'noor-library') {
				fileIdsToMirrorDelete.add(d.id);
				cleared.content_files += 1;
			}
		}
	}

	// 3) تنفيذ تحديثات RTDB (مسارات المحرّك فقط) ثم حذف الحقول في Firestore
	if (Object.keys(updates).length > 0) {
		await db.ref().update(updates);
	}

	await adminFsBulkDeleteSectionKeys('main', [...enginesMains]);
	await adminFsBulkDeleteSectionKeys('sub', [...enginesSubs]);
	await adminFsBulkDeleteSectionKeys('secondary', [...enginesSecs]);
	await adminFsBulkDeleteFileMirrorIds([...fileIdsToMirrorDelete]);

	// 4) سجلّ المسح
	await appendLog({
		level: 'warn',
		message:
			`تنفيذ "إعادة ضبط المصنع" — حُذف ${cleared.uploads + cleared.content_files} كتاب، ` +
			`${cleared.mains + cleared.subs + cleared.secondaries} قسم، ` +
			`${cleared.registry} سجلّ من السجلّ المركزي.`,
		reason: 'factory_reset'
	}).catch(() => {});

	return { ok: true, cleared };
}

/**
 * يُرجع حالة المحرّك الكاملة للـ UI (config + cursor + stats + log).
 */
export async function getEngineStatus({ logLimit = 30 } = {}) {
	await autoBootIfNeeded(); // فرصة الـ resume بعد إعادة تشغيل الخادم
	const state = getGlobalState();
	const [cfg, cursor, stats, log] = await Promise.all([
		readConfig(),
		readCursor(),
		readStats(),
		readLog(logLimit)
	]);
	return {
		processRunning: state.running,
		currentTickInFlight: state.currentTickInFlight,
		lastTickStartedAt: state.lastTickStartedAt,
		lastTickEndedAt: state.lastTickEndedAt,
		config: cfg,
		cursor,
		stats,
		currentSeedUrl: cfg.seedUrls[cursor.seedIndex] || null,
		log
	};
}
