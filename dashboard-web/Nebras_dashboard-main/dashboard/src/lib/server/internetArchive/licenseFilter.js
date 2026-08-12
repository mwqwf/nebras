/**
 * licenseFilter.js — فلتر التراخيص لمحرّك Internet Archive.
 *
 * ╔══════════════════════════════════════════════════════════════════╗
 * ║  لماذا يهمّ هذا الملف:                                            ║
 * ║  Internet Archive يستضيف محتوى بتراخيص متعدّدة. حين ننشر تطبيقاً  ║
 * ║  على Google Play لا يحقّ لنا تضمين محتوى محميّ بحقوق طبع. هذا     ║
 * ║  الفلتر يقبل فقط ما هو **آمن قانونياً للنشر**:                     ║
 * ║   • Public Domain (PD)                                            ║
 * ║   • Creative Commons (CC0, CC-BY, CC-BY-SA)                       ║
 * ║   • مجموعات إسلامية معروفة المصدر (allowlist يدوي)                ║
 * ║                                                                  ║
 * ║  أيّ شيء آخر — بما فيه CC-BY-NC، All Rights Reserved، أو غياب     ║
 * ║  ترخيص واضح — مرفوض افتراضياً.                                    ║
 * ╚══════════════════════════════════════════════════════════════════╝
 */

/**
 * أكواد ترخيص Creative Commons / Public Domain التي نقبلها افتراضياً.
 * نُطابقها على licenseurl وlicense النصّي بعد تطبيع.
 */
const ALLOWED_LICENSE_PATTERNS = Object.freeze([
	/publicdomain/i,
	/public-domain/i,
	/^pd$/i,
	/creativecommons\.org\/publicdomain/i,
	/cc0/i,
	/cc-by(?!-nc)(?!-nd)/i, // CC-BY و CC-BY-SA — نمنع NC و ND
	/creativecommons\.org\/licenses\/by\/[0-9.]+/i,
	/creativecommons\.org\/licenses\/by-sa\/[0-9.]+/i
]);

/**
 * أنماط تشير صراحةً إلى حقوق طبع محفوظة — نرفضها فوراً حتى لو كان العنصر
 * في مجموعة موثوقة. هذا حارس الامتثال لـ Google Play / DMCA.
 *
 * أي عنصر يحوي licenseurl أو rights يطابق هذه الأنماط = رفض قطعي،
 * يُسجَّل في failures registry كـ blacklist دائم.
 */
// ⚠️ مضيَّقة عمداً: الإصدار القديم كان يحوي `/copyright(ed)?/i` المجرّد الذي
// يطابق كلمة "copyright" أينما وردت — فيرفض عناصر **الملكية العامة** التي
// يحمل حقل `rights` فيها عبارات مثل «No known copyright restrictions» أو
// «copyright not renewed»، ويضعها في حظر دائم فينخفض الاسترجاع تدريجياً.
// الآن نطابق فقط الإشارات المقيِّدة الحقيقيّة (حقوق محفوظة صريحة / © سنة /
// قيود NC/ND). علامات الملكية العامة تُلتقط أولاً في PUBLIC_DOMAIN_PATTERNS.
const COPYRIGHT_DENY_PATTERNS = Object.freeze([
	/all\s*rights?\s*reserved/i,
	/©\s*\d{4}/, // © 2019
	/\(c\)\s*\d{4}/i, // (c) 2019
	/copyright(ed)?\s*(?:©|\(c\)|\bby\b|\d{4})/i, // "Copyright 2019" / "Copyrighted by X"
	/proprietary/i,
	/non\s*commercial/i, // CC-BY-NC — قيود تجاريّة
	/no\s*derivatives/i, // CC-BY-ND
	/-nc-/i, // أي CC variant فيه NC
	/-nd-/i, // أي CC variant فيه ND
	/-nc$/i,
	/-nd$/i,
	/^\s*cr\s*$/i // حقل rights يساوي بالكامل "CR" (اختصار IA لـ copyrighted)
]);

/**
 * علامات الملكية العامّة / غياب القيد التي يجب أن **تُقبَل** حتى لو احتوت
 * كلمة "copyright" (مثل «No known copyright restrictions»). تُفحَص قبل
 * بوّابة الرفض كي لا يُحجب محتوى مشروع.
 */
const PUBLIC_DOMAIN_PATTERNS = Object.freeze([
	/public\s*[-_]?\s*domain/i,
	/no\s*known\s*copyright/i,
	/not\s*in\s*copyright/i,
	/out\s*of\s*copyright/i,
	/no\s*copyright\s*(restriction|renewal)/i,
	/copyright\s*(?:has\s*)?(?:not\s*been\s*renewed|not\s*renewed|expired)/i,
	/\bcc0\b/i
]);

/**
 * يفحص إن كان النصّ يدلّ صراحةً على حقوق طبع محفوظة. حارس Google Play.
 * @param {string} text
 * @returns {boolean}
 */
function looksLikeCopyrighted(text) {
	if (!text) return false;
	const s = String(text).trim();
	if (!s) return false;
	for (const pat of COPYRIGHT_DENY_PATTERNS) {
		if (pat.test(s)) return true;
	}
	return false;
}

/**
 * يفحص إن كان النصّ يدلّ على ملكية عامّة / غياب قيد حقوق.
 * @param {string} text
 * @returns {boolean}
 */
function looksPublicDomain(text) {
	if (!text) return false;
	const s = String(text).trim();
	if (!s) return false;
	for (const pat of PUBLIC_DOMAIN_PATTERNS) {
		if (pat.test(s)) return true;
	}
	return false;
}

/** يفحص تطابق ترخيص CC/PD مسموح صريح (URL أو نصّ). */
function matchesAllowedLicense(text) {
	if (!text) return false;
	const s = String(text).trim();
	if (!s) return false;
	for (const pat of ALLOWED_LICENSE_PATTERNS) {
		if (pat.test(s)) return true;
	}
	return false;
}

/**
 * 🔒 مجموعات الملكية العامّة المنسَّقة فقط (Public-Domain allowlist).
 * هذه قوائم مغلقة لا يرفع إليها عامّة الناس عشوائياً، فعضويّتها دليل ملكية
 * عامّة كافٍ — تُمنح وحدها تساهل "غياب الترخيص". أُزيلت المجموعات المجتمعيّة
 * مفتوحة الرفع (booksbylanguage_arabic, folkscanomy_*, audio_islamic,
 * opensource_*) لأنّها قد تحوي محتوى محميّاً بحقوق طبع؛ المحتوى منها يُقبَل فقط بترخيص
 * PD/CC صريح. هذا fallback يُستعمل حين لا يُمرّر المُحرّك قائمة (نادر) —
 * المصدر المعتمد هو PD_TRUSTED_COLLECTIONS في engine.js.
 */
export const DEFAULT_TRUSTED_COLLECTIONS = Object.freeze([
	'gutenberg',
	'librivoxaudio',
	'librivox',
	'prelinger'
]);

/**
 * يفحص ترخيص عنصر IA. يقبل إن وُجد license/licenseurl يطابق الأنماط
 * المسموحة. إن غاب الترخيص، يقبل **فقط** إذا كان العنصر ضمن مجموعة
 * موثوقة (trustedCollections) ومُفعَّل وضع التساهل بالمجموعات.
 *
 * @param {Object} item metadata الخام من IA Metadata API (.metadata)
 * @param {{
 *   trustedCollections?: string[],
 *   allowMissingLicenseInTrustedCollections?: boolean
 * }} [opts]
 * @returns {{ ok: boolean, reason: string, licenseMatched?: string, collection?: string }}
 */
/**
 * إصدار منطق بوّابة الترخيص. يُرفَع عند كل تعديل جوهريّ على قواعد القبول/
 * الرفض. سجلّ الفشل يختم العناصر المرفوضة بهذا الرقم؛ وعند تغيّر الإصدار
 * تُمنح العناصر المرفوضة سابقاً (بسبب ترخيص) **إعادة محاولة واحدة** تحت
 * البوّابة الجديدة — فتعود عناصر الملكية العامّة التي حظرتها البوّابة
 * القديمة خطأً، دون إعادة محاولة لا نهائيّة للمحتوى المحظور فعلاً.
 * (v1 = البوّابة القديمة العريضة، v2 = البوّابة المتوازنة الحاليّة.)
 */
export const LICENSE_GATE_VERSION = 2;

/** أسباب فشل لا تُعاد محاولتها (blacklist فوري). */
export const PERMANENT_FAILURE_REASONS = Object.freeze(
	new Set([
		'license_not_allowed',
		'license_missing',
		'license_missing_and_not_trusted',
		'license_copyrighted_explicit', // ⚠ حارس Google Play — لا يُعاد المحاولة
		'license_rights_copyrighted_explicit'
	])
);

/**
 * فحص سريع على صفّ نتيجة scrape (يحتوي licenseurl/rights/collection).
 * @param {Record<string, unknown>} scrapeRow
 * @param {Parameters<typeof evaluateLicense>[1]} [opts]
 */
export function isLicenseAllowedScrapeItem(scrapeRow, opts = {}) {
	return evaluateLicense(scrapeRow, opts).ok;
}

/**
 * @param {Array<Record<string, unknown>>} items
 * @param {Parameters<typeof evaluateLicense>[1]} [opts]
 */
export function filterScrapeItemsByLicense(items, opts = {}) {
	return (items || []).filter((row) => isLicenseAllowedScrapeItem(row, opts));
}

export function evaluateLicense(item, opts = {}) {
	const trusted = new Set(
		(opts.trustedCollections && opts.trustedCollections.length
			? opts.trustedCollections
			: DEFAULT_TRUSTED_COLLECTIONS
		).map((s) => String(s).toLowerCase())
	);
	const allowMissingInTrusted = Boolean(opts.allowMissingLicenseInTrustedCollections);

	const licenseUrl = String(item?.licenseurl || '').trim();
	const licenseField = String(item?.license || '').trim();
	const rightsField = String(item?.rights || '').trim();

	// ───────── ✅ EXPLICIT ALLOW — ملكية عامّة / CC مسموح ─────────
	// يُفحَص **أوّلاً** عبر كل الحقول: PD صريح أو CC مسموح يُقبَل فوراً حتى لو
	// احتوى حقل rights كلمة "copyright" (مثل «No known copyright restrictions»).
	// هذا يُصلح علّة انخفاض الاسترجاع دون السماح بمحتوى محميّ فعلاً.
	if (
		looksPublicDomain(licenseUrl) ||
		looksPublicDomain(licenseField) ||
		looksPublicDomain(rightsField) ||
		matchesAllowedLicense(licenseUrl) ||
		matchesAllowedLicense(licenseField) ||
		matchesAllowedLicense(rightsField)
	) {
		return {
			ok: true,
			reason: 'license_allowed',
			licenseMatched: pickString(licenseUrl, licenseField, rightsField)
		};
	}

	// ───────── 🚨 HARD GATE — رفض صريح للمحتوى المحميّ ─────────
	// (Google Play / DMCA — رفض قطعيّ لأيّ إشارة حقوق محفوظة حقيقيّة:
	//  «All Rights Reserved»، «© 2019»، «Copyrighted by…»، أو قيود NC/ND).
	if (looksLikeCopyrighted(licenseUrl) || looksLikeCopyrighted(licenseField)) {
		return {
			ok: false,
			reason: 'license_copyrighted_explicit',
			licenseMatched: licenseUrl || licenseField
		};
	}
	if (looksLikeCopyrighted(rightsField)) {
		return {
			ok: false,
			reason: 'license_rights_copyrighted_explicit',
			licenseMatched: rightsField
		};
	}

	// ───────── 🔸 ترخيص مُعلَن غير مسموح ─────────
	// نعتمد **حقول الترخيص المُعلَنة فقط** (licenseurl/license)، لا حقل
	// `rights` الوصفيّ — لأنّ rights كثيراً ما يحوي نصّاً وصفيّاً لا يدلّ على
	// قيد، فالاعتماد عليه كان يرفض عناصر مشروعة (سبب رئيسيّ للانخفاض).
	const declaredLicense = pickString(licenseUrl, licenseField);
	if (declaredLicense) {
		// وصل هنا = مُعلَن لكنه ليس PD/CC مسموحاً ولا محظوراً صراحةً ⇒ غير معروف.
		return { ok: false, reason: 'license_not_allowed', licenseMatched: declaredLicense };
	}

	// ───────── ⚠️ TRUSTED COLLECTION FALLBACK ─────────
	// لا يوجد ترخيص صريح — هل العنصر ضمن مجموعة موثوقة + الوضع المسموح؟
	// نقبله مشروطاً، ونصنّفه `community_collection` (وليس verified PD)
	// حتى نستطيع تمييزه في Firestore + متجر التطبيق لاحقاً.
	if (!allowMissingInTrusted) {
		return { ok: false, reason: 'license_missing' };
	}
	const collections = Array.isArray(item?.collection)
		? item.collection
		: item?.collection
			? [item.collection]
			: [];
	for (const c of collections) {
		const cn = String(c || '').toLowerCase();
		if (trusted.has(cn)) {
			return {
				ok: true,
				reason: 'trusted_collection_fallback',
				collection: cn,
				// تصنيف license مخفّض — يستعمله adminUploader لوسم الوثيقة
				// في Firestore بـ __license_status: 'community_collection'
				licenseTier: 'community_collection'
			};
		}
	}
	return { ok: false, reason: 'license_missing_and_not_trusted' };
}

function pickString(...values) {
	for (const v of values) {
		if (v == null) continue;
		if (Array.isArray(v) && v.length > 0) return String(v[0] || '');
		const s = String(v || '').trim();
		if (s) return s;
	}
	return '';
}
