/** POST /api/admin/hindawi-library/engine/start */
import { json } from '@sveltejs/kit';
import { startEngine, runEngineTick } from '$lib/server/hindawi/engine.js';
import { isAdminConfigured } from '$lib/server/firebaseAdmin.js';

/** @type {import('@sveltejs/kit').RequestHandler} */
export async function POST(event) {
	const auth = event.locals?.auth;
	if (!auth) return json({ error: 'unauthenticated' }, { status: 401 });
	if (auth.role !== 'owner' && auth.role !== 'supervisor') {
		return json({ error: 'forbidden', reason: 'role_not_allowed' }, { status: 403 });
	}
	if (!isAdminConfigured()) {
		return json({ error: 'not_configured', reason: 'admin_service_account_missing' }, { status: 501 });
	}
	try {
		const result = await startEngine();
		// على serverless لا تعيش الحلقة، فننفّذ دورة فوريّة لتظهر نتائج بنقرة
		// واحدة (هنداوي تعمل بـ fetch عاديّ). نبتلع خطأ الدورة كي لا يُفشل التشغيل.
		let tick = null;
		try {
			tick = await runEngineTick();
		} catch (e) {
			tick = { tickError: e?.message || String(e), reason: e?.reason || 'tick_failed' };
		}
		return json({ ok: true, ...result, tick, processed: tick?.processed, skipped: tick?.skipped, failed: tick?.failed });
	} catch (err) {
		return json(
			{ error: 'start_failed', reason: err?.reason || 'start_failed', message: err?.message || String(err) },
			{ status: err?.status || 500 }
		);
	}
}
