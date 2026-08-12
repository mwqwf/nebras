/**
 * internetArchive.js — طبقة API العميل لمحرّك Internet Archive.
 *
 * كلّ الدوال تستعمل `authedJson` (Bearer Firebase ID Token). تتعامل مع
 * مسارات /api/admin/internet-archive/* فقط، ولا تعرف بأيّ أمر يخصّ
 * تطبيق Flutter (التطبيق يقرأ Firestore مباشرة).
 */

import { authedJson } from './_authedFetch.js';

const BASE = '/api/admin/internet-archive';

/** يقرأ شجرة الأقسام الحاليّة (main → sub → secondary). */
export async function fetchSectionsTree() {
	return authedJson(`${BASE}/sections`);
}

/**
 * بحث Scraping API (صفحة واحدة + cursor).
 * @param {{ q?:string, nebrasTypes?:string[], languages?:string[], collections?:string[], creators?:string[], cursor?:string|null, count?:number }} args
 */
export async function searchItems(args) {
	return authedJson(`${BASE}/search`, {
		method: 'POST',
		body: args || {}
	});
}

/**
 * معاينة عنصر — يفحص الترخيص + الصيغة + يختار الملف.
 * @param {{ identifier:string, trustedCollections?:string[], allowMissingLicenseInTrustedCollections?:boolean }} args
 */
export async function previewItem(args) {
	return authedJson(`${BASE}/preview`, {
		method: 'POST',
		body: args
	});
}

/**
 * استيراد عنصر مفرد إلى تصنيف محدّد.
 * @param {{ identifier:string, hierarchy:{ mainId:string, subId:string, secondaryId?:string|null }, trustedCollections?:string[], allowMissingLicenseInTrustedCollections?:boolean }} args
 */
export async function importItem(args) {
	return authedJson(`${BASE}/import`, {
		method: 'POST',
		body: args
	});
}

/* ── محرّك ─────────────────────────────────────────────── */

export async function getEngineStatus() {
	return authedJson(`${BASE}/engine/status`);
}

export async function startEngine() {
	return authedJson(`${BASE}/engine/start`, { method: 'POST', body: {} });
}

/**
 * زرّ "تشغيل تلقائي كامل" — يضع بذور افتراضية إن لم توجد، يُفعِّل المحرّك،
 * ويطلق أوّل دورة فوراً. لا حاجة لـ JSON أو تصنيف يدوي بعد ذلك.
 */
export async function bootstrapEngine() {
	return authedJson(`${BASE}/engine/bootstrap`, { method: 'POST', body: {} });
}

/**
 * تشخيص شامل — ينفّذ tick متزامن ويُرجع: env، Firebase، RTDB، اختبار IA API،
 * نتيجة tick أو stack trace للخطأ. للتشخيص العملي على Vercel.
 */
export async function diagnoseEngine() {
	return authedJson(`${BASE}/engine/diagnose`, { method: 'POST', body: {} });
}

export async function stopEngine() {
	return authedJson(`${BASE}/engine/stop`, { method: 'POST', body: {} });
}

export async function runOneTick() {
	return authedJson(`${BASE}/engine/tick`, { method: 'POST', body: {} });
}

/**
 * تحديث قائمة البذور بالكامل.
 * @param {Array<Object>} seeds
 */
export async function updateSeeds(seeds) {
	return authedJson(`${BASE}/engine/seeds`, { method: 'PUT', body: { seeds } });
}

/**
 * إعادة تعيين — cursor فقط أو factoryReset كامل.
 * @param {'cursor'|'factory'} type
 */
export async function resetEngine(type = 'cursor') {
	return authedJson(`${BASE}/engine/reset`, { method: 'POST', body: { type } });
}
