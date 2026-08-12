/**
 * _authedFetch.js — طبقة مشتركة لإرسال طلبات JSON المصادَقة إلى
 * مسارات API المحمية بـ Bearer (مثل المسارات الإداريّة).
 *
 * يضيف `Authorization: Bearer <Firebase ID token>` تلقائيّاً (طازجاً عند
 * الحاجة)، ويترجم الأخطاء إلى رسائل عربيّة مختصرة جاهزة للعرض في UI
 * عبر Toast/Alert. يرمي دائماً `Error` موسَّعاً بخصائص:
 *   err.status   → HTTP status number
 *   err.payload  → JSON body من الخادم (أو null)
 *   err.reason   → payload.reason (إن وُجد) — لفحوص محدَّدة من الواجهة
 *   err.message  → نصّ مترجَم يصلح مباشرةً للعرض
 *
 * لا يُصدَّر من هنا سوى الدالّتين `authedJson` و `rawAuthedFetch`؛
 * الملف underscore-prefixed لإظهار النيّة: لا تستورد منه إلا من وحدات
 * أخرى في نفس الطبقة ($lib/api/*).
 */

import { getFirebaseAuth } from '$lib/firebase/client.js';
import { getIdToken } from 'firebase/auth';

/**
 * يحصل على Firebase ID token طازج. يُرجع null إذا لم يكن المستخدم
 * مسجَّلاً (فنرمي 401 بدل محاولة الاتصال — تجربة أوضح للمطوّر).
 */
async function freshBearer() {
	try {
		const auth = getFirebaseAuth();
		if (!auth?.currentUser) return null;
		const token = await getIdToken(auth.currentUser, /* forceRefresh */ false);
		return token || null;
	} catch {
		return null;
	}
}

/**
 * يبني رسالة عربيّة قابلة للعرض بناءً على رمز الحالة ومحتوى الجواب.
 * @param {number} status
 * @param {any} payload
 */
function buildErrorMessage(status, payload) {
	// رسالة صريحة من الخادم لها الأولويّة دائماً (الخادم يكتبها بلغة UI).
	const serverMsg = payload?.message && String(payload.message).trim();
	if (serverMsg) return serverMsg;

	if (status === 401) return 'يجب تسجيل الدخول لإجراء هذه العملية.';
	if (status === 403) {
		if (payload?.reason === 'access_suspended' || payload?.forceSignOut) {
			return 'تم تعليق وصولك من قبل الإدارة.';
		}
		if (payload?.reason === 'role_not_allowed') {
			return 'صلاحيّاتك لا تسمح بإتمام هذه العملية.';
		}
		if (payload?.reason === 'not_in_admins') {
			return 'حسابك غير مسجَّل كعضو في إدارة لوحة التحكّم.';
		}
		return 'الوصول مرفوض.';
	}
	if (status === 404) return 'لم يُعثر على العنصر المطلوب.';
	if (status === 409) return 'تعارض في البيانات — حاول مرّة أخرى.';
	if (status === 501) {
		return (
			'خاصيّة الكتابة عبر السيرفر غير مفعّلة لهذا المشروع — ' +
			'يحتاج المسؤول إلى ضبط مفاتيح الخدمة في ملف .env.'
		);
	}
	if (status === 400) {
		return `طلب غير صحيح (${payload?.reason || 'bad_request'}).`;
	}
	if (status >= 500) {
		return 'حدث خطأ غير متوقَّع على الخادم — حاول مرّة أخرى لاحقاً.';
	}
	return `تعذّر إتمام العملية (HTTP ${status}).`;
}

/**
 * نسخة خامّ مخصّصة لحالات لا تحتاج JSON (كرفع FormData)؛ تعيد Response
 * مباشرة بعد إلصاق ترويسة Authorization. لا تتحقّق من نوع المحتوى.
 *
 * @param {string} path
 * @param {RequestInit} [init]
 */
export async function rawAuthedFetch(path, init = {}) {
	const token = await freshBearer();
	/** @type {HeadersInit} */
	const headers = new Headers(init.headers || {});
	if (token) headers.set('Authorization', `Bearer ${token}`);
	return fetch(path, { ...init, headers });
}

/**
 * مرسِل JSON مصادَق. يرمي خطأ موسَّعاً إن لم يكن 2xx.
 *
 * @param {string} path
 * @param {{ method?: string, body?: any, searchParams?: Record<string,string> }} [options]
 * @returns {Promise<any>}
 */
export async function authedJson(path, options = {}) {
	const { method = 'GET', body, searchParams } = options;

	// دمج searchParams إن وُجدت (دون تعديل الـ path الأصلي).
	let finalPath = path;
	if (searchParams && Object.keys(searchParams).length > 0) {
		const qs = new URLSearchParams();
		for (const [k, v] of Object.entries(searchParams)) {
			if (v !== undefined && v !== null) qs.set(k, String(v));
		}
		finalPath += (path.includes('?') ? '&' : '?') + qs.toString();
	}

	const token = await freshBearer();
	if (!token) {
		const err = /** @type {any} */ (new Error('يجب تسجيل الدخول لإجراء هذه العملية.'));
		err.status = 401;
		err.payload = null;
		err.reason = 'not_signed_in';
		throw err;
	}

	/** @type {HeadersInit} */
	const headers = { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` };

	let res;
	try {
		res = await fetch(finalPath, {
			method,
			headers,
			body: body === undefined ? undefined : JSON.stringify(body)
		});
	} catch (networkErr) {
		const err = /** @type {any} */ (
			new Error('تعذّر الاتصال بالخادم — تأكد من اتصال الإنترنت ثمّ أعد المحاولة.')
		);
		err.status = 0;
		err.payload = null;
		err.reason = 'network_error';
		err.cause = networkErr;
		throw err;
	}

	let payload = null;
	const contentType = res.headers.get('content-type') || '';
	if (contentType.includes('application/json')) {
		try {
			payload = await res.json();
		} catch {
			payload = null;
		}
	}

	if (!res.ok) {
		const err = /** @type {any} */ (new Error(buildErrorMessage(res.status, payload)));
		err.status = res.status;
		err.payload = payload;
		err.reason = payload?.reason || payload?.error || null;
		throw err;
	}

	return payload;
}
