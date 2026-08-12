/**
 * GET /api/admin/supervisors
 *
 * يُعيد قائمة المشرفين المسجَّلين في قائمة الـ admins
 * (`dashboard_users`) — للمالك فقط.
 *
 * يمرّ الطلب أوّلاً عبر `hooks.server.js` (التوكن + عدم الحظر)، ثم
 * نُطبّق `requireOwner` للتأكّد من أنّ المنادي تحديداً هو المالك.
 *
 * Response 200:
 *   {
 *     total: number,
 *     supervisors: Array<{
 *       uid, email, displayName, photoURL,
 *       role: 'supervisor'|'owner'|string,
 *       isBlocked: boolean,
 *       createdAt?: number,
 *       lastSignedInAt?: number,
 *       createdVia?: string
 *     }>
 *   }
 */

import { json } from '@sveltejs/kit';
import { getAdminDatabase } from '$lib/server/firebaseAdmin.js';
import { requireOwner } from '$lib/server/authGuard.js';

/** @type {import('@sveltejs/kit').RequestHandler} */
export async function GET(event) {
	const denied = requireOwner(event);
	if (denied) return denied;

	try {
		const snap = await getAdminDatabase().ref('dashboard_users').get();
		if (!snap.exists()) {
			return json({ total: 0, supervisors: [] });
		}

		const raw = snap.val() || {};
		const list = [];
		for (const [uid, v] of Object.entries(raw)) {
			if (!v || typeof v !== 'object') continue;
			// نعرض المشرفين والمالك معاً حتى يظهر الجدول كاملاً. أزرار
			// الحظر تُعطَّل في الواجهة لدور 'owner' وللمالك نفسه.
			list.push({
				uid,
				email: v.email || '',
				displayName: v.displayName || '',
				photoURL: v.photoURL || '',
				role: v.role === 'admin' ? 'supervisor' : v.role || 'supervisor',
				isBlocked: v.isBlocked === true,
				createdAt: typeof v.createdAt === 'number' ? v.createdAt : null,
				lastSignedInAt: typeof v.lastSignedInAt === 'number' ? v.lastSignedInAt : null,
				createdVia: v.createdVia || null
			});
		}

		// أحدث تسجيل دخول في الأعلى (fallback: createdAt).
		list.sort((a, b) => {
			const ax = a.lastSignedInAt || a.createdAt || 0;
			const bx = b.lastSignedInAt || b.createdAt || 0;
			return bx - ax;
		});

		return json({ total: list.length, supervisors: list });
	} catch (err) {
		console.error('[api/admin/supervisors] list failed:', err);
		return json({ error: 'server_error', message: err?.message || 'unknown' }, { status: 500 });
	}
}
