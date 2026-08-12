/**
 * POST /api/admin/hindawi-library/engine/reset
 *   body: { mode?: 'cursor' }   (افتراضي 'cursor')
 *     • cursor  → إعادة المؤشّر للصفحة 1 فقط (غير مدمّر).
 *   🛑 mode='factory' (الحذف الشامل لكتب هنداوي) أُزيل نهائيًّا — يُرفض هنا.
 */
import { json } from '@sveltejs/kit';
import { resetCursor } from '$lib/server/hindawi/engine.js';
import { isAdminConfigured } from '$lib/server/firebaseAdmin.js';

/** @type {import('@sveltejs/kit').RequestHandler} */
export async function POST(event) {
	const auth = event.locals?.auth;
	if (!auth) return json({ error: 'unauthenticated' }, { status: 401 });
	const body = await event.request.json().catch(() => ({}));
	const mode = String(body?.mode || 'cursor').toLowerCase();

	// 🛑 الحذف الشامل أُزيل نهائيًّا — يُرفض حتى لو وصل الطلب مباشرةً.
	if (mode === 'factory') {
		return json(
			{ error: 'feature_removed', message: 'خاصيّة الحذف الشامل أُزيلت نهائيًّا.' },
			{ status: 410 }
		);
	}
	if (auth.role !== 'owner' && auth.role !== 'supervisor') {
		return json({ error: 'forbidden', reason: 'role_not_allowed' }, { status: 403 });
	}
	if (!isAdminConfigured()) {
		return json({ error: 'not_configured' }, { status: 501 });
	}
	try {
		const result = await resetCursor();
		return json({ ok: true, mode: 'cursor', ...result });
	} catch (err) {
		return json(
			{ error: 'reset_failed', reason: err?.reason || 'reset_failed', message: err?.message || String(err) },
			{ status: err?.status || 500 }
		);
	}
}
