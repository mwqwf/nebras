/**
 * sectionsTree.js — قراءة شجرة الأقسام الحاليّة من Realtime Database
 * (Admin SDK) وتقديمها بصيغة موحَّدة جاهزة للمصنِّف المحليّ وللواجهة.
 *
 * الهيكل الذي تعتمده لوحة التحكّم (راجع moderator.js):
 *   sections_unified/main/{mainId}                 — { id, name, ... }
 *   sections_unified/sub/{subId}                   — { id, name, main_section, ... }
 *   sections_unified/secondary/{secId}             — { id, name, sub_section, ... }
 *
 * هذه الوحدة لا تكتب أبداً — قراءة فقط. لذلك آمنة للاستدعاء من أيّ مسار
 * /api/admin/noor-library/* دون قيد إضافي.
 *
 * ╔══════════════════════════════════════════════════════════════════╗
 * ║  Blacklist (القائمة السوداء للأقسام)                              ║
 * ╠══════════════════════════════════════════════════════════════════╣
 * ║  بعض الأقسام مخصّصة لاستخدام بشري حصراً (مثل "دروس بترخيصها")     ║
 * ║  ويُمنع منعاً باتّاً على المحرّك الآلي:                              ║
 * ║     1) أن يرى هذه الأقسام في الشجرة المُمرَّرة للمصنِّف.           ║
 * ║     2) أن يضيف كتاباً داخلها أو ينشئ قسماً فرعياً/ثانوياً تحتها.    ║
 * ║                                                                  ║
 * ║  الفلترة تتمّ هنا بمستوى المصدر (أعلى نقطة)، لذا أيّ مكوّن يستهلك  ║
 * ║  `buildSectionsTree()` يحصل تلقائياً على شجرة "نظيفة". إضافة      ║
 * ║  حماية ثانية في `sectionsCreator.js` تمنع الكتابة حتى لو حاول     ║
 * ║  المصنِّف تجاوز الفلتر بـ ID مخمَّن.                                ║
 * ╚══════════════════════════════════════════════════════════════════╝
 */

import { getNebrasFirestoreAdmin } from '$lib/server/firebaseAdmin.js';
import {
	NEBRAS_FS_SECTIONS
} from '$lib/firebase/nebrasUnifiedPaths.js';

/**
 * أسماء الأقسام (main/sub/secondary) الممنوعة على المحرّك الآلي.
 * المطابقة تتمّ بعد تطبيع عربيّ (إزالة تشكيل + توحيد ا/أ/إ + ى→ي + ة→ه).
 *
 * أيّ قسم يطابق اسمه أحد هذه الأنماط — أو ينحدر من قسم مطابق — يُحذف
 * من الشجرة قبل تمريرها للمصنِّف ولا يقبل أيّ كتابة من المحرّك الآلي.
 */
export const BLACKLISTED_SECTION_NAMES = Object.freeze([
	'دروس بتدكصهك',
	// نسخ بديلة محتملة (Typos شائعة) لنفس القسم — احتراز تشغيلي
	'دروس بترخيصها',
	'دروس بترخيصه'
]);

// ── Arabic normalization (نسخة من classifier.js لتفادي الاعتمادية الدائريّة) ─
function normalizeArabic(s) {
	return String(s || '')
		.replace(/[\u064B-\u065F\u0610-\u061A\u06D6-\u06ED]/g, '')
		.replace(/\u0640/g, '')
		.replace(/[\u0622\u0623\u0625\u0671]/g, '\u0627')
		.replace(/\u0649/g, '\u064A')
		.replace(/\u0629/g, '\u0647')
		.replace(/\s+/g, ' ')
		.trim()
		.toLowerCase();
}

const NORMALIZED_BLACKLIST = new Set(
	BLACKLISTED_SECTION_NAMES.map(normalizeArabic).filter(Boolean)
);

/**
 * يفحص ما إذا كان اسم قسم مطابقاً لأحد أنماط القائمة السوداء (مع تطبيع).
 * @param {string} name
 * @returns {boolean}
 */
export function isBlacklistedSectionName(name) {
	const n = normalizeArabic(name);
	if (!n) return false;
	return NORMALIZED_BLACKLIST.has(n);
}

async function readLevel(level) {
	const snap = await getNebrasFirestoreAdmin()
		.collection(NEBRAS_FS_SECTIONS)
		.doc(level)
		.get();
	if (!snap.exists) return [];
	const val = snap.data() || {};
	return Object.values(val);
}

/**
 * يحسب IDs الأقسام (main/sub/secondary) الممنوعة بناءً على القائمة السوداء
 * وعلاقات الأبوّة. أيّ ابن لقسم محظور يُعدّ محظوراً تلقائياً.
 *
 * @param {{ mains: any[], subs: any[], secondaries: any[] }} flat
 * @returns {{ mainIds:Set<string>, subIds:Set<string>, secondaryIds:Set<string> }}
 */
export function computeBlacklistedIds({ mains, subs, secondaries }) {
	const mainIds = new Set();
	for (const m of mains) {
		if (isBlacklistedSectionName(m?.name)) mainIds.add(String(m.id));
	}

	const subIds = new Set();
	for (const s of subs) {
		const isNameBlocked = isBlacklistedSectionName(s?.name);
		const parentBlocked = mainIds.has(String(s?.main_section ?? ''));
		if (isNameBlocked || parentBlocked) subIds.add(String(s.id));
	}

	const secondaryIds = new Set();
	for (const sec of secondaries) {
		const isNameBlocked = isBlacklistedSectionName(sec?.name);
		const parentBlocked = subIds.has(String(sec?.sub_section ?? ''));
		if (isNameBlocked || parentBlocked) secondaryIds.add(String(sec.id));
	}

	return { mainIds, subIds, secondaryIds };
}

/**
 * يبني شجرة [main → sub → secondary] جاهزة للعرض بعد إزالة كلّ
 * الأقسام المحظورة (وأبنائها). يُرجع أيضاً المؤشّرات الكاملة + مؤشّرات
 * الـ blacklist لكي يستعملها `sectionsCreator.js` للحماية وقت الكتابة.
 *
 * @returns {Promise<{
 *   tree: Array<{ id:string, name:string, children: Array<{ id:string, name:string, parentId:string, children: Array<{ id:string, name:string, parentId:string }> }> }>,
 *   flat: { mains: any[], subs: any[], secondaries: any[] },
 *   index: { mainsById: Record<string,any>, subsById: Record<string,any>, secondariesById: Record<string,any> },
 *   blacklist: { mainIds: Set<string>, subIds: Set<string>, secondaryIds: Set<string> }
 * }>}
 */
export async function buildSectionsTree() {
	const [mainsAll, subsAll, secondariesAll] = await Promise.all([
		readLevel('main'),
		readLevel('sub'),
		readLevel('secondary')
	]);

	// 1) احسب الـ blacklist على البيانات الكاملة (نحتاج الأبوّة الكاملة)
	const blacklist = computeBlacklistedIds({
		mains: mainsAll,
		subs: subsAll,
		secondaries: secondariesAll
	});

	// 2) صفِّ الأقسام المحظورة قبل بناء الـ tree/index
	const mains = mainsAll.filter((m) => !blacklist.mainIds.has(String(m.id)));
	const subs = subsAll.filter((s) => !blacklist.subIds.has(String(s.id)));
	const secondaries = secondariesAll.filter(
		(s) => !blacklist.secondaryIds.has(String(s.id))
	);

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
		index: { mainsById, subsById, secondariesById },
		blacklist
	};
}

/**
 * يُنتج تمثيلاً نصّيّاً مدمجاً للشجرة (تشخيص/عرض)، مع IDs لكلّ مستوى.
 *
 *   [M:123] الفقه الإسلامي
 *     [S:456] العبادات
 *       [E:789] الصلاة
 *       [E:790] الزكاة
 *     [S:457] المعاملات
 *   [M:124] الحديث الشريف
 *
 * @param {Awaited<ReturnType<typeof buildSectionsTree>>['tree']} tree
 */
export function serializeTreeAsPlainText(tree) {
	const lines = [];
	for (const m of tree) {
		lines.push(`[M:${m.id}] ${m.name}`);
		for (const s of m.children) {
			lines.push(`  [S:${s.id}] ${s.name}`);
			for (const e of s.children) {
				lines.push(`    [E:${e.id}] ${e.name}`);
			}
		}
	}
	return lines.join('\n');
}

/**
 * يتحقّق أنّ المسار الذي اقترحه المصنِّف أو المستخدم سليم وفق القاعدة الذهبيّة:
 *   main_section_id موجود — sub.main_section === main_section_id —
 *   secondary.sub_section === sub.id (إن وُجد).
 *
 * @returns {{ valid: boolean, reason?: string, resolved?: { main: any, sub: any, secondary: any|null } }}
 */
export function validateHierarchyPath(
	{ mainId, subId, secondaryId },
	index
) {
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
