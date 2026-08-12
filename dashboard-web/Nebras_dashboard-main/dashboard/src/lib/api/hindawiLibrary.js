/**
 * hindawiLibrary.js — أغلفة API لمحرّك مؤسسة هنداوي (يطابق noorLibrary.js).
 * كلّها تستعمل authedJson (Bearer Firebase ID Token).
 */
import { authedJson } from './_authedFetch.js';

const BASE = '/api/admin/hindawi-library/engine';

/** حالة المحرّك (config + cursor + stats + log). */
export async function getEngineStatus() {
	return authedJson(`${BASE}/status`);
}

/** تشغيل المحرّك (idempotent). */
export async function startEngine() {
	return authedJson(`${BASE}/start`, { method: 'POST', body: {} });
}

/** إيقاف المحرّك. */
export async function stopEngine() {
	return authedJson(`${BASE}/stop`, { method: 'POST', body: {} });
}

/** تشغيل دورة واحدة يدويّاً. */
export async function runOneTick() {
	return authedJson(`${BASE}/tick`, { method: 'POST', body: {} });
}

/**
 * إعادة الضبط. mode='cursor' (افتراضي، غير مدمّر) أو 'factory' (حذف كتب هنداوي).
 * @param {'cursor'|'factory'} mode
 */
export async function resetEngine(mode = 'cursor') {
	return authedJson(`${BASE}/reset`, { method: 'POST', body: { mode } });
}

/** تشخيص حيّ: crawl4ai + جلب صفحة + استخراج الروابط. */
export async function diagnose() {
	return authedJson('/api/admin/libraries/diagnose?source=hindawi');
}
