/**
 * إزالة القيم `undefined` بعمق — Firestore يرفض الحقول undefined بينما RTDB كانت تتجاهلها.
 * @param {unknown} value
 * @returns {unknown}
 */
export function stripUndefinedDeep(value) {
	if (Array.isArray(value)) {
		return value.map((item) => stripUndefinedDeep(item)).filter((item) => item !== undefined);
	}
	if (value && typeof value === 'object' && !(value instanceof Date)) {
		const out = {};
		for (const [k, v] of Object.entries(value)) {
			const cleaned = stripUndefinedDeep(v);
			if (cleaned !== undefined) out[k] = cleaned;
		}
		return out;
	}
	return value === undefined ? undefined : value;
}

/**
 * أقصى طول لحقل `description` المخزَّن في وثيقة محتوى (بالأحرف).
 *
 * 🐞 إصلاح جذريّ: بعض المصادر (Internet Archive تحديداً) تُرجِع وصفاً ضخماً
 * (HTML بمئات الكيلوبايت) يُخزَّن **مرّتين** — في الجذر `description` وداخل
 * `metadata.description` — فتقترب الوثيقة من حدّ 1MB. تطبيق الجوال يقرأ
 * أحدث الوثائق عبر قناة Firestore (StandardMessageCodec) دفعةً واحدة، فتتضخّم
 * الرسالة وتُحدث ضغط ذاكرة حادّاً (blocking GC) ينتهي بمهلة/OOM/انهيار. الوصف
 * يُعرض كنصّ عاديّ على شاشة التفاصيل فقط، فحدٌّ معقول يكفي تماماً.
 */
export const MAX_CONTENT_DESCRIPTION_CHARS = 8000;

/**
 * @param {unknown} value
 * @param {number} max
 * @returns {unknown}
 */
function clampString(value, max) {
	if (typeof value !== 'string' || value.length <= max) return value;
	return value.slice(0, max).trimEnd() + '…';
}

/**
 * يقصّ حقول الوصف الضخمة (`description` في الجذر وداخل `metadata`) قبل الكتابة
 * إلى Firestore حتى تبقى وثيقة المحتوى صغيرة وآمنة لقراءة الجوال. لا يلمس أيّ
 * حقل آخر، ولا يُنشئ `metadata` إن لم تكن موجودة.
 * @param {unknown} payload
 * @returns {unknown}
 */
export function clampContentTextFields(payload) {
	if (!payload || typeof payload !== 'object' || Array.isArray(payload)) return payload;
	const out = { ...payload };
	if (typeof out.description === 'string') {
		out.description = clampString(out.description, MAX_CONTENT_DESCRIPTION_CHARS);
	}
	if (out.metadata && typeof out.metadata === 'object' && !Array.isArray(out.metadata)) {
		const md = { ...out.metadata };
		if (typeof md.description === 'string') {
			md.description = clampString(md.description, MAX_CONTENT_DESCRIPTION_CHARS);
		}
		out.metadata = md;
	}
	return out;
}
