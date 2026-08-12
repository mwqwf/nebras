/**
 * sectionsTree.js — قراءة شجرة الأقسام الحاليّة من Firestore بصيغة
 * موحَّدة جاهزة للمصنِّف ولـ validateHierarchyPath.
 *
 * نسخة مستقلّة داخل مجلّد internetArchive — لا تستورد من noorLibrary
 * إطلاقاً. تستعمل فقط نقاط Firestore الموحَّدة (`nebrasUnifiedFirestoreAdmin`)
 * التي يستعملها الرفع اليدوي.
 */

import {
	adminFsReadSectionsLevel
} from '$lib/server/nebrasUnifiedFirestoreAdmin.js';

/**
 * يبني شجرة [main → sub → secondary] + مؤشّرات IDs للقراءة السريعة.
 *
 * @returns {Promise<{
 *   tree: Array<{ id:string, name:string, children: Array<{ id:string, name:string, parentId:string, children: Array<{ id:string, name:string, parentId:string }> }> }>,
 *   flat: { mains: any[], subs: any[], secondaries: any[] },
 *   index: { mainsById: Record<string,any>, subsById: Record<string,any>, secondariesById: Record<string,any> }
 * }>}
 */
export async function buildSectionsTree() {
	const [mains, subs, secondaries] = await Promise.all([
		adminFsReadSectionsLevel('main'),
		adminFsReadSectionsLevel('sub'),
		adminFsReadSectionsLevel('secondary')
	]);

	const mainsById = Object.fromEntries(mains.map((m) => [String(m.id), m]));
	const subsById = Object.fromEntries(subs.map((s) => [String(s.id), s]));
	const secondariesById = Object.fromEntries(secondaries.map((s) => [String(s.id), s]));

	const subsByMain = new Map();
	for (const s of subs) {
		const k = String(s.main_section ?? '');
		if (!k) continue;
		if (!subsByMain.has(k)) subsByMain.set(k, []);
		subsByMain.get(k).push(s);
	}

	const secondariesBySub = new Map();
	for (const s of secondaries) {
		const k = String(s.sub_section ?? '');
		if (!k) continue;
		if (!secondariesBySub.has(k)) secondariesBySub.set(k, []);
		secondariesBySub.get(k).push(s);
	}

	const tree = mains.map((m) => {
		const mainId = String(m.id);
		const subChildren = (subsByMain.get(mainId) || []).map((sub) => {
			const subId = String(sub.id);
			const secChildren = (secondariesBySub.get(subId) || []).map((sec) => ({
				id: String(sec.id),
				name: String(sec.name || ''),
				parentId: subId
			}));
			return {
				id: subId,
				name: String(sub.name || ''),
				parentId: mainId,
				children: secChildren
			};
		});
		return {
			id: mainId,
			name: String(m.name || ''),
			children: subChildren
		};
	});

	return {
		tree,
		flat: { mains, subs, secondaries },
		index: { mainsById, subsById, secondariesById }
	};
}

/**
 * يتحقّق أنّ مسار التصنيف سليم وفق القاعدة الذهبيّة:
 *   main موجود — sub.main_section === main — secondary.sub_section === sub.
 *
 * @returns {{ valid: boolean, reason?: string, resolved?: { main:any, sub:any, secondary:any|null } }}
 */
export function validateHierarchyPath({ mainId, subId, secondaryId }, index) {
	if (!mainId) return { valid: false, reason: 'main_section_required' };
	const main = index.mainsById[String(mainId)];
	if (!main) return { valid: false, reason: 'main_section_not_found' };

	if (!subId) return { valid: false, reason: 'sub_section_required' };
	const sub = index.subsById[String(subId)];
	if (!sub) return { valid: false, reason: 'sub_section_not_found' };
	if (String(sub.main_section ?? '') !== String(mainId)) {
		return { valid: false, reason: 'sub_does_not_belong_to_main' };
	}

	let secondary = null;
	if (secondaryId) {
		secondary = index.secondariesById[String(secondaryId)];
		if (!secondary) return { valid: false, reason: 'secondary_section_not_found' };
		if (String(secondary.sub_section ?? '') !== String(subId)) {
			return { valid: false, reason: 'secondary_does_not_belong_to_sub' };
		}
	}

	return { valid: true, resolved: { main, sub, secondary } };
}
