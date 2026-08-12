/**
 * noorLibrary.js — Client API لسكريبت جلب مكتبة نور.
 *
 * يلفّ نقاط /api/admin/noor-library/* عبر authedJson لكي تحمل تلقائيّاً
 * Bearer token الـ Firebase ID والترجمة العربيّة للأخطاء.
 *
 * هذه الوحدة لا تكتب في قاعدة البيانات مباشرة — كلّ شيء يمرّ عبر الخادم
 * الذي يستخدم Admin SDK ويكتب في dashboard_uploads + content_unified/files.
 */

import { authedJson } from './_authedFetch.js';

/**
 * يجلب شجرة الأقسام الكاملة لعرضها في الـ selectors.
 * @returns {Promise<{
 *   tree: Array<{ id:string, name:string, children: Array<{ id:string, name:string, parentId:string, children: Array<{ id:string, name:string, parentId:string }> }> }>,
 *   counts: { mains:number, subs:number, secondaries:number }
 * }>}
 */
export async function fetchNoorSectionsTree() {
	return authedJson('/api/admin/noor-library/sections', { method: 'GET' });
}

/**
 * يطلب من الخادم جلب metadata الكتاب وتصنيفه دون رفعه.
 * @param {string} url
 */
export async function previewNoorBook(url) {
	return authedJson('/api/admin/noor-library/preview', {
		method: 'POST',
		body: { url }
	});
}

/**
 * يبدأ عمليّة الاستيراد الفعليّ (تنزيل + رفع + كتابة في RTDB).
 * @param {{
 *   url: string,
 *   metadata: { title:string, description?:string, author?:string, thumbnail?:string },
 *   hierarchy: { mainId:string, subId:string, secondaryId?:string|null },
 *   overrideFileUrl?: string,
 *   listed?: boolean
 * }} payload
 */
export async function importNoorBook(payload) {
	return authedJson('/api/admin/noor-library/import', {
		method: 'POST',
		body: payload
	});
}

/** يُرجع آخر مهام الجلب اليدويّ (مرتّبة من الأحدث للأقدم). */
export async function listNoorJobs(limit = 30) {
	return authedJson(`/api/admin/noor-library/jobs?limit=${encodeURIComponent(limit)}`, {
		method: 'GET'
	});
}

// ╔══════════════════════════════════════════════════════════════════╗
// ║  Autonomous Engine API — التحكّم بالمحرّك الآلي في الخلفية         ║
// ╚══════════════════════════════════════════════════════════════════╝

/**
 * يُرجع الحالة الكاملة للمحرّك الآلي:
 *   { config, cursor, stats, log, processRunning, currentSeedUrl }
 *
 * @param {number} [logLimit=30]
 */
export async function getEngineStatus(logLimit = 30) {
	return authedJson(
		`/api/admin/noor-library/engine/status?limit=${encodeURIComponent(logLimit)}`,
		{ method: 'GET' }
	);
}

/** يبدأ المحرّك الآلي. آمن للاستدعاء أكثر من مرّة. */
export async function startEngineRemote() {
	return authedJson('/api/admin/noor-library/engine/start', { method: 'POST' });
}

/** يوقف المحرّك الآلي (يُطفئ علامة enabled و يُلغي مؤقّت الذاكرة). */
export async function stopEngineRemote() {
	return authedJson('/api/admin/noor-library/engine/stop', { method: 'POST' });
}

/**
 * يُحدّث قائمة بذور الزحف (seedUrls). يصفّي غير الصالحة.
 *
 * @param {string[]} seedUrls
 */
export async function updateEngineSeeds(seedUrls) {
	return authedJson('/api/admin/noor-library/engine/seed', {
		method: 'POST',
		body: { seedUrls }
	});
}

/** يُعيد المؤشّر للبذرة الأولى/صفحة 1 (لا يمسّ السجلّ ولا الإحصائيات). */
export async function resetEngineCursor() {
	return authedJson('/api/admin/noor-library/engine/seed', { method: 'DELETE' });
}

/**
 * يُنفّذ دورة واحدة من المحرّك مزامنةً (للاختبار اليدوي أو cron).
 * قد يستغرق دقائق حسب حجم الـ batch.
 */
export async function runEngineTickRemote() {
	return authedJson('/api/admin/noor-library/engine/tick', { method: 'POST' });
}

/**
 * "الزرّ النووي" — يمسح كلّ ما أحدثه المحرّك الآلي:
 *   - noor_library_registry  + noor_library_failures + engine/cursor.
 *   - أيّ قسم (main/sub/secondary) يحمل علامة __createdBy='noor_library_engine'.
 *   - أيّ كتاب يحمل علامة __provider='noor-library'.
 *
 * ⚠️ عمليّة غير قابلة للتراجع — الواجهة يجب أن تطلب تأكيد المستخدم قبل الاستدعاء.
 *
 * @returns {Promise<{
 *   ok: true,
 *   elapsedMs: number,
 *   cleared: {
 *     registry: number, failures: number,
 *     uploads: number, content_files: number,
 *     mains: number, subs: number, secondaries: number
 *   }
 * }>}
 */
export async function factoryResetEngine() {
	return authedJson('/api/admin/noor-library/engine/reset', { method: 'DELETE' });
}

/** تشخيص حيّ: crawl4ai + جلب صفحة + استخراج الروابط. */
export async function diagnose() {
	return authedJson('/api/admin/libraries/diagnose?source=noor');
}
