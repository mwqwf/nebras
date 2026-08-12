/**
 * publicBaseUrl.js — يحدّد عنوان النشر العامّ للوحة، لبناء روابط مطلقة
 * يستهلكها تطبيق Flutter (مثل روابط الـ proxy: /api/proxy/ia/{id}).
 *
 * الأولويّة:
 *   1) NEBRAS_PUBLIC_BASE_URL  — اضبطه في .env للتحكّم الكامل (مستحبّ).
 *   2) VERCEL_PROJECT_PRODUCTION_URL — نطاق الإنتاج الثابت على Vercel.
 *   3) القيمة الافتراضيّة المعروفة للنشر الحالي.
 *
 * ملاحظة: نتجنّب VERCEL_URL (يتغيّر مع كلّ deployment preview) لأنّ الرابط
 * يُكتب في Firestore ويجب أن يبقى صالحاً بعد عمليّات نشر لاحقة.
 */
import { env } from '$env/dynamic/private';

const FALLBACK_BASE_URL = 'https://nebras-dashboard-main.vercel.app';

function normalize(url) {
	return String(url || '')
		.trim()
		.replace(/\/+$/, '');
}

/**
 * @returns {string} عنوان أساسي بدون شرطة نهائيّة (مثل https://x.vercel.app).
 */
export function getPublicBaseUrl() {
	const explicit = normalize(env.NEBRAS_PUBLIC_BASE_URL || env.PUBLIC_BASE_URL || '');
	if (explicit) {
		return /^https?:\/\//i.test(explicit) ? explicit : `https://${explicit}`;
	}
	const prod = normalize(env.VERCEL_PROJECT_PRODUCTION_URL || '');
	if (prod) {
		return /^https?:\/\//i.test(prod) ? prod : `https://${prod}`;
	}
	return FALLBACK_BASE_URL;
}
