/**
 * sectionsCreator.js — إنشاء أقسام (main / sub / secondary) تلقائياً
 * بنفس schema الذي يكتبه moderator.js يدوياً، حتى تظهر في التطبيق فوراً
 * كأنّها أُنشئت بشريّاً.
 *
 * كلّ سجلّ يحمل العلامة `__createdBy: 'ia_library_engine'` ليُمكن لزرّ
 * "إعادة ضبط المصنع" مسحه دون لمس الأقسام البشريّة.
 *
 * مستقلّ تماماً عن noorLibrary.
 */

import {
	adminFsReadSectionsLevel,
	adminFsGetSectionRecord,
	adminFsSetSectionRecord,
	adminFsDeleteSectionRecord
} from '$lib/server/nebrasUnifiedFirestoreAdmin.js';

const ENGINE_TAG = 'ia_library_engine';

function makeSectionId() {
	return Date.now() + Math.floor(Math.random() * 1000);
}

function cleanName(name) {
	return String(name || '')
		.replace(/[\u0000-\u001F\u007F]/g, '')
		.trim()
		.slice(0, 120);
}

// ── Find by name (de-dup) ──────────────────────────────────────────

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

// ── Create main / sub / secondary ──────────────────────────────────

export async function createMainSectionAdmin(name) {
	const cleanedName = cleanName(name);
	if (!cleanedName) {
		throw Object.assign(new Error('اسم القسم الرئيسي مطلوب.'), {
			reason: 'main_name_required',
			status: 400
		});
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
		__createdBy: ENGINE_TAG
	};
	await adminFsSetSectionRecord('main', id, payload);
	return { id, name: cleanedName, alreadyExisted: false };
}

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
		throw Object.assign(new Error('main_section غير صالح.'), {
			reason: 'invalid_main_section',
			status: 400
		});
	}
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
		throw Object.assign(new Error('sub_section غير صالح.'), {
			reason: 'invalid_sub_section',
			status: 400
		});
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

/** يحذف أقساماً أنشأها محرّك IA فقط. */
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
