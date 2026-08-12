/**
 * sectionsCreator.js — إنشاء أقسام (main / sub / secondary) ديناميكياً عبر
 * Admin SDK عندما يقرّر المحرّك أنّ الكتاب لا يناسب أيّ قسم حالي بدقّة.
 *
 * ╔══════════════════════════════════════════════════════════════════╗
 * ║  🔒 Nebras Only — يكتب فقط في sections_unified (RTDB نبراس).      ║
 * ║  لا يلمس Mshcat/OldApp إطلاقاً. يطابق schema الأقسام كما يكتبها    ║
 * ║  src/lib/api/moderator.js → createMainSection / createSubSection /║
 * ║  createSecondarySection لكي تظهر الأقسام الجديدة في كلّ مكان        ║
 * ║  (لوحة التحكّم + الموبايل) بنفس الشكل الذي يتوقّعه القرّاء.        ║
 * ╚══════════════════════════════════════════════════════════════════╝
 *
 * المسارات المكتوبة:
 *   sections_unified/main/{id}       — { id, name, order_index, is_listed, thumbnail, created_at }
 *   sections_unified/sub/{id}        — { id, name, main_section, is_listed, thumbnail, created_at }
 *   sections_unified/secondary/{id}  — { id, name, sub_section,  is_listed, thumbnail, created_at }
 *
 * كلّ سجلّ يحمل علامة `__createdBy: 'noor_library_engine'` لكي يستطيع
 * زرّ "إعادة ضبط المصنع" مسحَه دون المساس بأقسام أنشأها مدير بشري.
 *
 * ╔══════════════════════════════════════════════════════════════════╗
 * ║  Blacklist Defense — حماية وقت الكتابة                            ║
 * ╠══════════════════════════════════════════════════════════════════╣
 * ║  يُمنع منعاً باتّاً إنشاء قسم باسم محظور أو إنشاء قسم تحت أبٍ        ║
 * ║  محظور، حتى لو تجاوز المصنِّف الفلتر في `sectionsTree.js`. هذا       ║
 * ║  defense-in-depth يضمن أنّ القائمة السوداء لا يمكن خرقها برمجياً.   ║
 * ╚══════════════════════════════════════════════════════════════════╝
 */

import {
	adminFsReadSectionsLevel,
	adminFsGetSectionRecord,
	adminFsSetSectionRecord,
	adminFsDeleteSectionRecord
} from '$lib/server/nebrasUnifiedFirestoreAdmin.js';
import {
	isBlacklistedSectionName,
	computeBlacklistedIds
} from './sectionsTree.js';

const ENGINE_TAG = 'noor_library_engine';

/**
 * يولّد معرّف قسم جديد بنفس صيغة moderator.js (Date.now() + random).
 * نُرجع رقماً (Number) — لأنّ الـ schema يعتمد Number.
 */
function makeSectionId() {
	return Date.now() + Math.floor(Math.random() * 1000);
}

function cleanName(name) {
	return String(name || '').trim().slice(0, 120);
}

function blacklistError(message, reason = 'blacklisted_section') {
	return Object.assign(new Error(message), { reason, status: 403 });
}

/**
 * يقرأ كلّ مستويات الأقسام مرّة واحدة ويحسب IDs المحظورة. مفيد للحماية
 * وقت الكتابة (يضمن أنّ أبَ القسم الذي ننشئه ليس محظوراً).
 */
async function readBlacklistGuard() {
	const [mains, subs, secondaries] = await Promise.all([
		adminFsReadSectionsLevel('main'),
		adminFsReadSectionsLevel('sub'),
		adminFsReadSectionsLevel('secondary')
	]);
	return computeBlacklistedIds({ mains, subs, secondaries });
}

// ── Find by name (de-dup) ────────────────────────────────────────────

async function findMainSectionByName(name) {
	const target = cleanName(name).toLowerCase();
	if (!target) return null;
	const mains = await adminFsReadSectionsLevel('main');
	for (const main of mains) {
		if (String(main.name || '').trim().toLowerCase() === target) {
			return { id: Number(main.id), name: String(main.name) };
		}
	}
	return null;
}

/**
 * يفحص ما إذا كان قسم فرعي بنفس الاسم موجوداً تحت main_section محدّد.
 *
 * @param {number|string} mainSectionId
 * @param {string} name
 * @returns {Promise<{ id:number, name:string }|null>}
 */
export async function findSubSectionByName(mainSectionId, name) {
	const target = cleanName(name).toLowerCase();
	if (!target) return null;
	const subs = await adminFsReadSectionsLevel('sub');
	for (const sub of subs) {
		if (
			String(sub.main_section ?? '') === String(mainSectionId) &&
			String(sub.name || '').trim().toLowerCase() === target
		) {
			return { id: Number(sub.id), name: String(sub.name) };
		}
	}
	return null;
}

/**
 * يفحص ما إذا كان قسم ثانوي بنفس الاسم موجوداً تحت sub_section محدّد.
 *
 * @param {number|string} subSectionId
 * @param {string} name
 * @returns {Promise<{ id:number, name:string }|null>}
 */
export async function findSecondarySectionByName(subSectionId, name) {
	const target = cleanName(name).toLowerCase();
	if (!target) return null;
	const secondaries = await adminFsReadSectionsLevel('secondary');
	for (const sec of secondaries) {
		if (
			String(sec.sub_section ?? '') === String(subSectionId) &&
			String(sec.name || '').trim().toLowerCase() === target
		) {
			return { id: Number(sec.id), name: String(sec.name) };
		}
	}
	return null;
}

// ── Create main / sub / secondary ───────────────────────────────────

/**
 * ينشئ قسماً رئيسيّاً جديداً بنفس schema لوحة التحكّم (moderator.js).
 * لو وُجد بنفس الاسم → يُرجعه كما هو دون إنشاء.
 *
 * يُمنع الإنشاء إذا كان الاسم مطابقاً لأحد أنماط القائمة السوداء.
 *
 * @param {string} name
 * @returns {Promise<{ id:number, name:string, alreadyExisted:boolean }>}
 */
export async function createMainSectionAdmin(name) {
	const cleanedName = cleanName(name);
	if (!cleanedName) {
		throw Object.assign(new Error('اسم القسم الرئيسي مطلوب.'), {
			reason: 'main_name_required',
			status: 400
		});
	}
	if (isBlacklistedSectionName(cleanedName)) {
		throw blacklistError(
			`اسم القسم "${cleanedName}" محظور — لا يمكن للمحرّك إنشاؤه.`
		);
	}

	const existing = await findMainSectionByName(cleanedName);
	if (existing) {
		return { id: existing.id, name: existing.name, alreadyExisted: true };
	}

	const id = makeSectionId();
	const payload = {
		id,
		name: cleanedName,
		order_index: 0,
		is_listed: true,
		thumbnail: null,
		created_at: new Date().toISOString(),
		// علامة تعريفيّة: تسمح بمسح الأقسام التي أنشأها المحرّك دون لمس
		// الأقسام التي أنشأها مديرٌ بشري.
		__createdBy: ENGINE_TAG
	};
	await adminFsSetSectionRecord('main', id, payload);
	return { id, name: cleanedName, alreadyExisted: false };
}

/**
 * ينشئ قسماً فرعياً جديداً تحت قسم رئيسي. لو وُجد بنفس الاسم → يُرجعه.
 *
 * يفشل إذا كان الـ main parent محظوراً، أو إذا كان اسم القسم الجديد محظوراً.
 *
 * @param {number|string} mainSectionId
 * @param {string} name
 * @returns {Promise<{ id:number, name:string, main_section:number, alreadyExisted:boolean }>}
 */
export async function createSubSectionAdmin(mainSectionId, name) {
	const cleanedName = cleanName(name);
	if (!cleanedName) {
		throw Object.assign(new Error('اسم القسم الفرعي مطلوب.'), {
			reason: 'sub_name_required',
			status: 400
		});
	}
	const mainNum = Number(mainSectionId);
	if (!Number.isFinite(mainNum) || mainNum <= 0) {
		throw Object.assign(new Error('main_section غير صالح لإنشاء قسم فرعي.'), {
			reason: 'invalid_main_section',
			status: 400
		});
	}
	if (isBlacklistedSectionName(cleanedName)) {
		throw blacklistError(
			`اسم القسم الفرعي "${cleanedName}" محظور — لا يمكن للمحرّك إنشاؤه.`
		);
	}

	// حماية: تأكّد أنّ الأبَ ليس محظوراً.
	const guard = await readBlacklistGuard();
	if (guard.mainIds.has(String(mainNum))) {
		throw blacklistError(
			'القسم الرئيسي المُختار مدرَج في القائمة السوداء — لا يقبل أيّ كتابة آلية.'
		);
	}

	// منع التكرار
	const existing = await findSubSectionByName(mainNum, cleanedName);
	if (existing) {
		return {
			id: existing.id,
			name: existing.name,
			main_section: mainNum,
			alreadyExisted: true
		};
	}

	const id = makeSectionId();
	const payload = {
		id,
		name: cleanedName,
		main_section: mainNum,
		is_listed: true,
		thumbnail: null,
		created_at: new Date().toISOString(),
		__createdBy: ENGINE_TAG
	};
	await adminFsSetSectionRecord('sub', id, payload);
	return { id, name: cleanedName, main_section: mainNum, alreadyExisted: false };
}

/**
 * ينشئ قسماً ثانوياً جديداً تحت قسم فرعي. لو وُجد بنفس الاسم → يُرجعه.
 *
 * يفشل إذا كان الـ sub parent محظوراً (أو ينحدر من main محظور)، أو إذا
 * كان اسم القسم الجديد محظوراً.
 *
 * @param {number|string} subSectionId
 * @param {string} name
 * @returns {Promise<{ id:number, name:string, sub_section:number, alreadyExisted:boolean }>}
 */
export async function createSecondarySectionAdmin(subSectionId, name) {
	const cleanedName = cleanName(name);
	if (!cleanedName) {
		throw Object.assign(new Error('اسم القسم الثانوي مطلوب.'), {
			reason: 'sec_name_required',
			status: 400
		});
	}
	const subNum = Number(subSectionId);
	if (!Number.isFinite(subNum) || subNum <= 0) {
		throw Object.assign(new Error('sub_section غير صالح لإنشاء قسم ثانوي.'), {
			reason: 'invalid_sub_section',
			status: 400
		});
	}
	if (isBlacklistedSectionName(cleanedName)) {
		throw blacklistError(
			`اسم القسم الثانوي "${cleanedName}" محظور — لا يمكن للمحرّك إنشاؤه.`
		);
	}

	// حماية: تأكّد أنّ الأبَ ليس محظوراً.
	const guard = await readBlacklistGuard();
	if (guard.subIds.has(String(subNum))) {
		throw blacklistError(
			'القسم الفرعي المُختار مدرَج في القائمة السوداء (أو ينحدر من قسم محظور) — لا يقبل أيّ كتابة آلية.'
		);
	}

	const existing = await findSecondarySectionByName(subNum, cleanedName);
	if (existing) {
		return {
			id: existing.id,
			name: existing.name,
			sub_section: subNum,
			alreadyExisted: true
		};
	}

	const id = makeSectionId();
	const payload = {
		id,
		name: cleanedName,
		sub_section: subNum,
		is_listed: true,
		thumbnail: null,
		created_at: new Date().toISOString(),
		__createdBy: ENGINE_TAG
	};
	await adminFsSetSectionRecord('secondary', id, payload);
	return { id, name: cleanedName, sub_section: subNum, alreadyExisted: false };
}

/**
 * يحذف أقساماً أُنشئت للتوّ بواسطة المحرّك (للتراجع عند فشل رفع الكتاب).
 * يمرّ على المعرّفات بالترتيب المعكوس (ثانوي → فرعي → رئيسي).
 * يحذف فقط ما يحمل `__createdBy === noor_library_engine`.
 *
 * @param {Array<string|number>} createdSectionIds
 */
export async function rollbackEngineCreatedSections(createdSectionIds) {
	const list = [...createdSectionIds].map(String).reverse();
	for (const sid of list) {
		for (const level of /** @type {const} */ (['secondary', 'sub', 'main'])) {
			const rec = await adminFsGetSectionRecord(level, sid);
			if (rec && rec.__createdBy === ENGINE_TAG) {
				await adminFsDeleteSectionRecord(level, sid);
				break;
			}
		}
	}
}
