/**
 * classifier.js — تصنيف عربي محلّيّ مستقلّ لعنصر Internet Archive.
 *
 * المنطق:
 *   1) heuristic مطابقة نصّيّة عربيّة (بعد normalization) بين:
 *        title + creator + subject[] + collection[] + description
 *      وبين أسماء أقسام الشجرة الحاليّة (main → sub → secondary).
 *   2) إن لم يجد main مناسباً → يقترح **إنشاء** main جديد من أوّل subject
 *      مفيد من IA (أو من collection)، ويُنشئ sub أوّل تحته.
 *   3) إن وجد main لكن لا sub مناسب → يقترح إنشاء sub جديد من subject.
 *   4) إن وجد main + sub → اختياريّاً ينشئ secondary من stem العنوان.
 *
 * النتيجة كائن قرار:
 *   { kind:'existing'|'create_sub'|'create_main',
 *     mainId, subId, secondaryId,
 *     newMainName?, newSubName?, newSecondaryName?,
 *     confidence, reasoning, method:'heuristic' }
 *
 * مستقلّ تماماً عن noorLibrary.
 */

function normalizeArabic(s) {
	return String(s || '')
		.replace(/[ً-ٟؐ-ؚۖ-ۭ]/g, '')
		.replace(/ـ/g, '')
		.replace(/[آأإٱ]/g, 'ا')
		.replace(/ى/g, 'ي')
		.replace(/ة/g, 'ه')
		.replace(/\s+/g, ' ')
		.trim()
		.toLowerCase();
}

/**
 * تطبيع مرشّحات subject/collection القادمة من IA إلى أسماء عربيّة قابلة
 * للقراءة في الواجهة. لو وُجدت ترجمة → نستعملها؛ وإلا نُبقي القيمة كما هي
 * (لكن نختصرها).
 */
const COLLECTION_LABELS = Object.freeze({
	opensource: 'محتوى مفتوح',
	opensource_arabic: 'محتوى عربي مفتوح',
	community_texts: 'نصوص مجتمعيّة',
	arabicliterature: 'الأدب العربي',
	arabicliteratureandlinguistics: 'الأدب واللغة العربيّة',
	islamicbooks_archive: 'كتب إسلاميّة',
	'islamic-books': 'كتب إسلاميّة',
	shamela: 'المكتبة الشاملة'
});

const SUBJECT_HINTS = Object.freeze({
	quran: 'القرآن الكريم',
	'quranic-recitation': 'تلاوة القرآن الكريم',
	tafsir: 'التفسير',
	hadith: 'الحديث الشريف',
	fiqh: 'الفقه الإسلامي',
	'islamic-law': 'الفقه الإسلامي',
	aqeedah: 'العقيدة',
	creed: 'العقيدة',
	seerah: 'السيرة النبويّة',
	history: 'التاريخ الإسلامي',
	arabic: 'اللغة العربيّة',
	literature: 'الأدب',
	dawah: 'الدعوة',
	'islamic-lectures': 'دروس إسلاميّة'
});

/**
 * يُنظّف اسم قسم مقترح: الأرشيف يحشر عدّة مواضيع في حقل subject واحد
 * مفصولة بـ `*` أو `;` أو `,` فينتج اسم قسم مشوَّه طويل ("علم القرآن*تفسير...").
 * نأخذ أوّل مقطع نظيف فقط ونقصّه لطول معقول.
 */
function sanitizeSectionName(raw) {
	let s = String(raw || '').trim();
	if (!s) return '';
	// أوّل مقطع قبل الفواصل الشائعة.
	s = s.split(/[*;|/\\\n\r\t]+/)[0].trim();
	// أزل علامات/فواصل زائدة من الأطراف.
	s = s.replace(/^[\s,،.\-–—_]+/, '').replace(/[\s,،.\-–—_]+$/, '').trim();
	// طول قسم معقول.
	if (s.length > 28) s = s.slice(0, 28).trim();
	return s;
}

function labelizeSubject(raw) {
	const n = normalizeArabic(raw);
	if (!n) return '';
	const en = String(raw || '').trim().toLowerCase().replace(/_/g, '-');
	if (SUBJECT_HINTS[en]) return SUBJECT_HINTS[en];
	// لو النصّ عربي أصلاً، ابقِه كما هو (بعد تنظيف + قصّ)
	return sanitizeSectionName(raw);
}

function labelizeCollection(raw) {
	const en = String(raw || '').trim().toLowerCase();
	if (COLLECTION_LABELS[en]) return COLLECTION_LABELS[en];
	return String(raw || '').trim().slice(0, 60);
}

/**
 * يقترح اسماً عربيّاً لـ main افتراضي بحسب نوع المحتوى. يُستعمل كـ
 * fallback نهائيّ حتى لا يبقى عنصرٌ بلا قسم.
 */
function defaultMainNameByType(nebrasContentType) {
	if (nebrasContentType === 'audio') return 'الصوتيّات';
	if (nebrasContentType === 'video') return 'الفيديو';
	return 'المكتبة';
}

function defaultSubNameByType(nebrasContentType) {
	if (nebrasContentType === 'audio') return 'تسجيلات صوتيّة';
	if (nebrasContentType === 'video') return 'مقاطع مرئيّة';
	return 'كتب متنوّعة';
}

function tokensOf(s, minLen = 3) {
	return new Set(
		normalizeArabic(s)
			.split(' ')
			.filter((t) => t.length >= minLen)
	);
}

/**
 * يحسب درجة تطابق اسم قسم مع وصف العنصر.
 */
function scoreOf(sectionName, haystack, tokens) {
	const n = normalizeArabic(sectionName);
	if (!n) return 0;
	let score = 0;
	for (const w of n.split(' ')) {
		if (w.length >= 3 && tokens.has(w)) score += 1;
	}
	if (n.length >= 4 && haystack.includes(n)) score += 3;
	return score;
}

/**
 * يستخلص أفضل "category hint" — اسم عربيّ صالح لإنشاء قسم منه — من
 * subjects أو collections في IA. يُفضّل الأقصر والأوضح.
 */
function pickBestHint(subjects, collections, nebrasContentType) {
	// 1) أولوية للترجمات المعروفة (SUBJECT_HINTS)
	for (const s of subjects || []) {
		const labeled = labelizeSubject(s);
		if (
			labeled &&
			labeled !== String(s).trim() // لها ترجمة معروفة
		) {
			return labeled;
		}
	}
	// 2) ثم أوّل subject عربي — بعد تنظيفه (أوّل مقطع نظيف + قصّ).
	//    ⚠️ للصوت/الفيديو نتخطّى هذه الخطوة: عناوين/مواضيع التلاوات هي
	//    أسماء قُرّاء فريدة، فاشتقاق اسم القسم منها يُنتج قسماً لكلّ قارئ
	//    (تشتّت شديد، يصعّب ظهور المحتوى). نتركها للكتب فقط حيث الـ subject
	//    عادةً تصنيف حقيقيّ (فقه، تفسير، …).
	if (nebrasContentType === 'document') {
		for (const s of subjects || []) {
			if (!/[؀-ۿ]/.test(String(s || ''))) continue;
			const clean = sanitizeSectionName(s);
			if (clean && clean.length >= 2) return clean;
		}
	}
	// 3) ثم collection معرفة
	for (const c of collections || []) {
		const labeled = labelizeCollection(c);
		if (labeled && labeled !== String(c).trim()) return labeled;
	}
	// 4) fallback افتراضي بحسب النوع (للصوت/الفيديو: قسم مستقرّ موحَّد)
	return defaultSubNameByType(nebrasContentType);
}

/**
 * الواجهة الرئيسيّة: يُرجع قرار تصنيف تنفيذيّاً (مع توجيهات إنشاء أقسام
 * عند الحاجة). لا يكتب أيّ شيء في DB — الكتابة في engine.js.
 *
 * @param {{
 *   tree: any[],
 *   index: { mainsById:Record<string,any>, subsById:Record<string,any>, secondariesById:Record<string,any> }
 * }} sections
 * @param {{
 *   title:string,
 *   author?:string,
 *   description?:string,
 *   subjects?:string[],
 *   collections?:string[],
 *   nebrasContentType:'document'|'audio'|'video'
 * }} item
 * @returns {{
 *   kind: 'existing' | 'create_sub' | 'create_main',
 *   mainId: string|null,
 *   subId: string|null,
 *   secondaryId: string|null,
 *   newMainName?: string,
 *   newSubName?: string,
 *   newSecondaryName?: string,
 *   confidence: number,
 *   reasoning: string,
 *   method: 'heuristic'
 * }}
 */
export function classifyItem(sections, item) {
	const haystack = normalizeArabic(
		[
			item.title,
			item.author,
			item.description,
			...(item.subjects || []),
			...(item.collections || [])
		]
			.filter(Boolean)
			.join(' ')
	);
	const tokens = tokensOf(haystack);
	const tree = sections.tree || [];

	// 1) ابحث عن أفضل main موجود
	let bestMain = null;
	let bestMainScore = 0;
	for (const m of tree) {
		const s = scoreOf(m.name, haystack, tokens);
		if (s > bestMainScore) {
			bestMainScore = s;
			bestMain = m;
		}
	}

	const bestHint = pickBestHint(item.subjects, item.collections, item.nebrasContentType);

	// 2) لا أقسام إطلاقاً، أو أفضل main ضعيف → إنشاء main جديد
	if (!bestMain || bestMainScore === 0) {
		return {
			kind: 'create_main',
			mainId: null,
			subId: null,
			secondaryId: null,
			newMainName: defaultMainNameByType(item.nebrasContentType),
			newSubName: bestHint,
			confidence: 0.35,
			reasoning: 'لم يُعثَر على قسم رئيسي مناسب — اقتراح إنشاء قسم جديد.',
			method: 'heuristic'
		};
	}

	// 3) ابحث عن أفضل sub داخل bestMain
	let bestSub = null;
	let bestSubScore = 0;
	for (const sub of bestMain.children || []) {
		const s = scoreOf(sub.name, haystack, tokens);
		if (s > bestSubScore) {
			bestSubScore = s;
			bestSub = sub;
		}
	}

	if (!bestSub) {
		return {
			kind: 'create_sub',
			mainId: String(bestMain.id),
			subId: null,
			secondaryId: null,
			newSubName: bestHint,
			confidence: 0.45,
			reasoning: `وُجد قسم رئيسي مناسب "${bestMain.name}" — اقتراح إنشاء قسم فرعي جديد.`,
			method: 'heuristic'
		};
	}

	// 4) قسم رئيسي + قسم فرعي موجودان → استخدمهما (مع secondary إن وُجد)
	let bestSec = null;
	let bestSecScore = 0;
	for (const sec of bestSub.children || []) {
		const s = scoreOf(sec.name, haystack, tokens);
		if (s > bestSecScore) {
			bestSecScore = s;
			bestSec = sec;
		}
	}

	return {
		kind: 'existing',
		mainId: String(bestMain.id),
		subId: String(bestSub.id),
		secondaryId: bestSec ? String(bestSec.id) : null,
		confidence: Math.min(0.5 + bestMainScore * 0.05 + bestSubScore * 0.05, 0.9),
		reasoning: `مطابقة محلّيّة: ${bestMain.name} ← ${bestSub.name}${bestSec ? ' ← ' + bestSec.name : ''}.`,
		method: 'heuristic'
	};
}
