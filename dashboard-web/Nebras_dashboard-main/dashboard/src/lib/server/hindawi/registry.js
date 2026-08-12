/**
 * registry.js — سجلّ كتب مؤسسة هنداوي المُجلَبة لمنع التكرار.
 *
 * مطابق بنيوياً لسجلّ مكتبة نور لكن بمسارات RTDB مستقلّة
 * (`hindawi_library_*`) كي لا تتداخل النطاقات بين المحرّكين.
 *
 *   hindawi_library_registry/{bookId}  — كتاب مُجلَب بنجاح
 *   hindawi_library_failures/{bookId}  — عدّاد فشل (blacklist تدريجي)
 */

import { getAdminDatabase } from '$lib/server/firebaseAdmin.js';

const REGISTRY_ROOT = 'hindawi_library_registry';
const FAILURES_ROOT = 'hindawi_library_failures';
export const FAILURE_BLACKLIST_THRESHOLD = 3;

function safeKey(bookId) {
	return String(bookId || '')
		.replace(/[.$#\[\]/]/g, '_')
		.slice(0, 700);
}

/** @param {string} bookId @returns {Promise<boolean>} */
export async function isBookImported(bookId) {
	const key = safeKey(bookId);
	if (!key) return false;
	const snap = await getAdminDatabase().ref(`${REGISTRY_ROOT}/${key}`).get();
	return snap.exists();
}

/**
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
			if (Number(rec?.count || 0) >= FAILURE_BLACKLIST_THRESHOLD) known.add(id);
		}
	}
	if (ids.length === 0) return { knownIds: known, newIds: [] };
	const newIds = [];
	for (const id of ids) if (!known.has(id)) newIds.push(id);
	return { knownIds: known, newIds };
}

/**
 * @param {string} bookId
 * @param {{ fileId:string, title?:string, url?:string, hierarchy?:object, createdSectionsIds?:string[] }} record
 */
export async function recordImported(bookId, record) {
	const key = safeKey(bookId);
	if (!key) throw new Error('bookId غير صالح للتسجيل.');
	await getAdminDatabase().ref(`${REGISTRY_ROOT}/${key}`).set({
		fileId: String(record?.fileId || ''),
		title: String(record?.title || '').slice(0, 400),
		url: String(record?.url || '').slice(0, 1000),
		hierarchy: record?.hierarchy || null,
		createdSectionsIds: Array.isArray(record?.createdSectionsIds)
			? record.createdSectionsIds.slice(0, 10)
			: [],
		importedAt: { '.sv': 'timestamp' }
	});
}

/** @param {string} bookId @param {{ reason?:string, message?:string, url?:string, permanent?:boolean }} info */
export async function recordFailure(bookId, info = {}) {
	const key = safeKey(bookId);
	if (!key) return;
	const ref = getAdminDatabase().ref(`${FAILURES_ROOT}/${key}`);
	await ref.transaction((current) => {
		const c = current || { count: 0, firstFailedAt: Date.now() };
		// permanent=true (إزالة/DMCA): نرفع العدّاد إلى العتبة فوراً كي يُعدّ
		// الكتاب «معروفاً» في partitionKnownBooks فلا يُعاد جلبه أبداً —
		// مكافئ لـ ia_library_dmca_blacklist في محرّك أرشيف الإنترنت.
		const nextCount = info?.permanent
			? FAILURE_BLACKLIST_THRESHOLD
			: Number(c.count || 0) + 1;
		return {
			count: nextCount,
			firstFailedAt: c.firstFailedAt || Date.now(),
			lastFailedAt: Date.now(),
			lastReason: String(info?.reason || 'unknown').slice(0, 60),
			lastMessage: String(info?.message || '').slice(0, 300),
			permanent: Boolean(info?.permanent) || Boolean(c.permanent),
			url: String(info?.url || c.url || '').slice(0, 1000)
		};
	});
}
