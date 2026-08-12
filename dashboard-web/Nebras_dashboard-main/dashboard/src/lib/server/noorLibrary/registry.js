/**
 * registry.js — سجل الكتب المُجلَبة من مكتبة نور لمنع التكرار.
 *
 * ╔══════════════════════════════════════════════════════════════════╗
 * ║  🔒 Nebras Only — يكتب حصراً في Realtime Database لمشروع نبراس.   ║
 * ╚══════════════════════════════════════════════════════════════════╝
 *
 * المسارات في RTDB:
 *   noor_library_registry/{noorBookId}   — سجلّ كلّ كتاب مُجلَب
 *     {
 *       fileId: 'noor_xxx',
 *       importedAt: <ts>,
 *       title: '...',
 *       url: '...',
 *       hierarchy: { mainId, subId, secondaryId },
 *       createdSectionsIds: ['<id1>', ...]   // إن أنشأ المحرك أقساماً جديدة
 *     }
 *
 * الفهرسة برقم/سلسلة slug الكتاب (parseNoorUrl().bookId) لكي يكون فحص
 * الوجود في O(1) عبر `db.ref(...).get()` بدلاً من scan كامل.
 */

import { getAdminDatabase } from '$lib/server/firebaseAdmin.js';

const REGISTRY_ROOT = 'noor_library_registry';
const FAILURES_ROOT = 'noor_library_failures';
// عتبة الـ blacklist: بعدها يُعتبر الكتاب غير قابل للجلب ويُتخطّى دائماً.
export const FAILURE_BLACKLIST_THRESHOLD = 3;

function safeKey(bookId) {
	// مفاتيح RTDB لا تقبل: . $ # [ ] /
	return String(bookId || '')
		.replace(/[.$#\[\]/]/g, '_')
		.slice(0, 700);
}

/**
 * يفحص ما إذا كان الكتاب مُجلَباً سابقاً.
 * @param {string} bookId
 * @returns {Promise<boolean>}
 */
export async function isBookImported(bookId) {
	const key = safeKey(bookId);
	if (!key) return false;
	const snap = await getAdminDatabase().ref(`${REGISTRY_ROOT}/${key}`).get();
	return snap.exists();
}

/**
 * يفحص قائمة من المعرّفات دفعة واحدة (أكثر كفاءة من loop).
 * يقرأ السجلّ كاملاً (متوسّط)، يبني Set، ثمّ يصفّي. إن صار السجلّ ضخماً
 * (>10K) نستبدله بـ multi-path fan-out لاحقاً.
 *
 * **ملاحظة**: الآن `knownIds` يضمّ:
 *   - كلّ ما هو في `noor_library_registry` (مُجلَب بنجاح).
 *   - كلّ ما تجاوز عتبة الفشل في `noor_library_failures`
 *     (blacklisted — لا فائدة من إعادة المحاولة).
 *
 * @param {string[]} bookIds
 * @returns {Promise<{ knownIds: Set<string>, newIds: string[] }>}
 */
export async function partitionKnownBooks(bookIds) {
	const ids = (bookIds || []).map(safeKey).filter(Boolean);
	const db = getAdminDatabase();

	const [regSnap, failSnap] = await Promise.all([
		db.ref(REGISTRY_ROOT).get(),
		db.ref(FAILURES_ROOT).get()
	]);

	const known = new Set(regSnap.exists() ? Object.keys(regSnap.val() || {}) : []);
	if (failSnap.exists()) {
		const failures = failSnap.val() || {};
		for (const [id, rec] of Object.entries(failures)) {
			const count = Number(rec?.count || 0);
			if (count >= FAILURE_BLACKLIST_THRESHOLD) known.add(id);
		}
	}

	if (ids.length === 0) return { knownIds: known, newIds: [] };
	const newIds = [];
	for (const id of ids) {
		if (!known.has(id)) newIds.push(id);
	}
	return { knownIds: known, newIds };
}

/**
 * يسجّل كتاباً مُجلَباً بنجاح.
 *
 * @param {string} bookId
 * @param {{
 *   fileId: string,
 *   title?: string,
 *   url?: string,
 *   hierarchy?: { mainId:string, subId:string, secondaryId?:string|null },
 *   createdSectionsIds?: string[]
 * }} record
 */
export async function recordImported(bookId, record) {
	const key = safeKey(bookId);
	if (!key) throw new Error('bookId غير صالح للتسجيل في السجلّ.');
	const payload = {
		fileId: String(record?.fileId || ''),
		title: String(record?.title || '').slice(0, 400),
		url: String(record?.url || '').slice(0, 1000),
		hierarchy: record?.hierarchy || null,
		createdSectionsIds: Array.isArray(record?.createdSectionsIds)
			? record.createdSectionsIds.slice(0, 10)
			: [],
		importedAt: { '.sv': 'timestamp' }
	};
	await getAdminDatabase().ref(`${REGISTRY_ROOT}/${key}`).set(payload);
}

/**
 * إحصائيات سريعة على السجلّ.
 *
 * @returns {Promise<{
 *   totalImported: number,
 *   lastImportedAt: number|null,
 *   firstImportedAt: number|null
 * }>}
 */
export async function getRegistryStats() {
	const snap = await getAdminDatabase().ref(REGISTRY_ROOT).get();
	if (!snap.exists()) {
		return { totalImported: 0, lastImportedAt: null, firstImportedAt: null };
	}
	const val = snap.val() || {};
	let total = 0;
	let last = 0;
	let first = Number.MAX_SAFE_INTEGER;
	for (const k of Object.keys(val)) {
		total += 1;
		const t = Number(val[k]?.importedAt || 0);
		if (t > last) last = t;
		if (t > 0 && t < first) first = t;
	}
	return {
		totalImported: total,
		lastImportedAt: last || null,
		firstImportedAt: first === Number.MAX_SAFE_INTEGER ? null : first
	};
}

/**
 * يحذف سجلّاً واحداً (لإعادة المحاولة لاحقاً).
 * @param {string} bookId
 */
export async function clearImported(bookId) {
	const key = safeKey(bookId);
	if (!key) return;
	await getAdminDatabase().ref(`${REGISTRY_ROOT}/${key}`).remove();
}

/**
 * يسجّل محاولة فاشلة لكتاب ما. يزيد العدّاد ويحفظ آخر سبب.
 * بعد بلوغ العدد عتبةَ `FAILURE_BLACKLIST_THRESHOLD` يُعتبر blacklisted تلقائياً
 * بفضل دمج `partitionKnownBooks`.
 *
 * @param {string} bookId
 * @param {{ reason?: string, message?: string, url?: string }} info
 */
export async function recordFailure(bookId, info = {}) {
	const key = safeKey(bookId);
	if (!key) return;
	const ref = getAdminDatabase().ref(`${FAILURES_ROOT}/${key}`);
	await ref.transaction((current) => {
		const c = current || { count: 0, firstFailedAt: Date.now() };
		return {
			count: Number(c.count || 0) + 1,
			firstFailedAt: c.firstFailedAt || Date.now(),
			lastFailedAt: Date.now(),
			lastReason: String(info?.reason || 'unknown').slice(0, 60),
			lastMessage: String(info?.message || '').slice(0, 300),
			url: String(info?.url || c.url || '').slice(0, 1000)
		};
	});
}

/**
 * إحصائيّات الفشل (لِـ UI الإدارة).
 * @returns {Promise<{ totalFailed: number, blacklistedCount: number }>}
 */
export async function getFailureStats() {
	const snap = await getAdminDatabase().ref(FAILURES_ROOT).get();
	if (!snap.exists()) return { totalFailed: 0, blacklistedCount: 0 };
	const val = snap.val() || {};
	let total = 0;
	let blacklisted = 0;
	for (const k of Object.keys(val)) {
		total += 1;
		if (Number(val[k]?.count || 0) >= FAILURE_BLACKLIST_THRESHOLD) blacklisted += 1;
	}
	return { totalFailed: total, blacklistedCount: blacklisted };
}
