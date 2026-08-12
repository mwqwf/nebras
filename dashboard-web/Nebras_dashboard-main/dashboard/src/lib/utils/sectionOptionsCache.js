/**
 * Section Options Cache
 * =====================
 * كاش بسيط في الذاكرة لخيارات الأقسام (رئيسي/فرعي/ثانوي) أثناء جلسة
 * المستخدم في الصفحة. الهدف: عدم إعادة جلب نفس القائمة من Firebase RTDB
 * + دمج Mshcat في كل مرّة يفتح فيها المستخدم مودال "إضافة إلى الطابور".
 *
 * - مدّة الصلاحية افتراضياً 5 دقائق — كافية لتدفّق إدراج جماعي سريع
 *   ودون التأثير على إنشاء أقسام جديدة في صفحات أخرى لأن الجلب يتجدّد
 *   بعد انتهاء المدّة.
 * - يمكن إبطال الكاش يدوياً عبر `invalidateSectionOptionsCache()` عند
 *   معرفة تغيير سياقي (مثلاً بعد إنشاء قسم جديد).
 * - الكاش مفتاحه `mainId`/`subId` لذا التغيير على فرع لا يبطل البقيّة.
 */

import {
	listMyMainSections,
	listMySubSections,
	listMySecondarySections
} from '$lib/api/moderator.js';

const TTL_MS = 5 * 60_000;

const cache = {
	/** @type {{ data: any[], at: number } | null} */
	mains: null,
	/** @type {Map<string, { data: any[], at: number }>} */
	subsByMain: new Map(),
	/** @type {Map<string, { data: any[], at: number }>} */
	secsBySub: new Map()
};

/** @type {Map<string, Promise<any[]>>} */
const pending = new Map();

function fresh(entry) {
	return entry && Date.now() - entry.at < TTL_MS;
}

/** قائمة الأقسام الرئيسية (مع دمج Mshcat). يستخدم الكاش إن وُجد. */
export async function getCachedMainSections({ force = false } = {}) {
	if (!force && fresh(cache.mains)) return cache.mains.data;
	const key = 'mains';
	if (pending.has(key)) return pending.get(key);
	const p = (async () => {
		try {
			const d = await listMyMainSections({ all: true });
			const data = d.results || [];
			cache.mains = { data, at: Date.now() };
			return data;
		} catch {
			return cache.mains?.data || [];
		} finally {
			pending.delete(key);
		}
	})();
	pending.set(key, p);
	return p;
}

/** قائمة الفروع لقسم رئيسي محدّد. */
export async function getCachedSubSections(mainId, { force = false } = {}) {
	const k = String(mainId || '');
	if (!k) return [];
	const entry = cache.subsByMain.get(k);
	if (!force && fresh(entry)) return entry.data;
	const pkey = `sub:${k}`;
	if (pending.has(pkey)) return pending.get(pkey);
	const p = (async () => {
		try {
			const d = await listMySubSections({ main_section: mainId || undefined, all: true });
			const data = d.results || [];
			cache.subsByMain.set(k, { data, at: Date.now() });
			return data;
		} catch {
			return entry?.data || [];
		} finally {
			pending.delete(pkey);
		}
	})();
	pending.set(pkey, p);
	return p;
}

/** قائمة الأقسام الثانوية لفرع محدّد. */
export async function getCachedSecondarySections(subId, { force = false } = {}) {
	const k = String(subId || '');
	if (!k) return [];
	const entry = cache.secsBySub.get(k);
	if (!force && fresh(entry)) return entry.data;
	const pkey = `sec:${k}`;
	if (pending.has(pkey)) return pending.get(pkey);
	const p = (async () => {
		try {
			const d = await listMySecondarySections({ sub_section: subId || undefined, all: true });
			const data = d.results || [];
			cache.secsBySub.set(k, { data, at: Date.now() });
			return data;
		} catch {
			return entry?.data || [];
		} finally {
			pending.delete(pkey);
		}
	})();
	pending.set(pkey, p);
	return p;
}

/**
 * إبطال الكاش (كلّياً أو جزئياً). تُستدعى عند معرفة تغيير سياقي.
 *
 * @param {{ scope?: 'all'|'mains'|'subs'|'secs', mainId?: string|number, subId?: string|number }} [opts]
 */
export function invalidateSectionOptionsCache({ scope = 'all', mainId, subId } = {}) {
	if (scope === 'all' || scope === 'mains') cache.mains = null;
	if (scope === 'all' || scope === 'subs') {
		if (mainId !== undefined) cache.subsByMain.delete(String(mainId));
		else cache.subsByMain.clear();
	}
	if (scope === 'all' || scope === 'secs') {
		if (subId !== undefined) cache.secsBySub.delete(String(subId));
		else cache.secsBySub.clear();
	}
}
