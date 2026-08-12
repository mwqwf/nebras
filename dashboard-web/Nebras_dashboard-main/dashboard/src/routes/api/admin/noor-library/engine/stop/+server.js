/**
 * POST /api/admin/noor-library/engine/stop
 *
 * يُطفئ علامة enabled ويُلغي مؤقّت الحلقة في الذاكرة. أيّ tick جارٍ يكتمل
 * ثم يتوقّف الـ timer (لا قطع منتصف العمليّة لمنع تلف السجلّ).
 *
 * 🔒 Nebras Only.
 */

import { json } from '@sveltejs/kit';
import { stopEngine } from '$lib/server/noorLibrary/engine.js';
import { isAdminConfigured } from '$lib/server/firebaseAdmin.js';

/** @type {import('@sveltejs/kit').RequestHandler} */
export async function POST(event) {
	const auth = event.locals?.auth;
	if (!auth) return json({ error: 'unauthenticated' }, { status: 401 });
	if (auth.role !== 'owner' && auth.role !== 'supervisor') {
		return json({ error: 'forbidden', reason: 'role_not_allowed' }, { status: 403 });
	}
	if (!isAdminConfigured()) {
		return json(
			{ error: 'not_configured', reason: 'admin_service_account_missing' },
			{ status: 501 }
		);
	}

	try {
		const result = await stopEngine();
		return json({ ok: true, ...result });
	} catch (err) {
		return json(
			{
				error: 'stop_failed',
				reason: err?.reason || 'stop_failed',
				message: err?.message || String(err)
			},
			{ status: err?.status || 500 }
		);
	}
}
