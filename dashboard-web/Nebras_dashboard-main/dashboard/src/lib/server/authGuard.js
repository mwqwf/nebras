/**
 * Auth Guard — أدوات مساعدة خادميّة لفرض صلاحيّات المالك (Owner-only)
 * على نقاط الـ API الإداريّة.
 *
 * ملاحظة: الجدار الرئيسي في `hooks.server.js` يمنع غير المصرّح لهم /
 * المحظورين أصلاً من الوصول إلى `/api/admin/*`، وهذا الملف يُضيف طبقة
 * إضافيّة: يتحقّق من أنّ المنادي تحديداً له دور 'owner'.
 */

import { json } from '@sveltejs/kit';

/**
 * يُعيد استجابة 403 موحّدة إذا لم يكن المنادي مالكاً.
 * يستخدم `event.locals.auth` التي يملؤها `hooks.server.js`.
 *
 * @param {import('@sveltejs/kit').RequestEvent} event
 * @returns {Response|null} استجابة جاهزة عند الرفض، وإلّا null.
 */
export function requireOwner(event) {
	const auth = event.locals?.auth;
	if (!auth) {
		return json({ error: 'unauthenticated' }, { status: 401 });
	}
	if (auth.role !== 'owner') {
		return json({ error: 'forbidden', reason: 'owner_only' }, { status: 403 });
	}
	return null;
}
