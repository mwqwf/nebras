/**
 * GET /api/admin/internet-archive/engine/status
 *
 * يُعيد الحالة الكاملة للمحرّك (config + cursor + stats + log).
 */
import { json } from '@sveltejs/kit';
import { isAdminPanelRole } from '$lib/server/dashboardRoles.js';
import { getEngineStatus } from '$lib/server/internetArchive/engine.js';

/** @type {import('@sveltejs/kit').RequestHandler} */
export async function GET(event) {
	const auth = event.locals?.auth;
	if (!auth) return json({ error: 'unauthenticated' }, { status: 401 });
	if (!isAdminPanelRole(auth.role)) {
		return json({ error: 'forbidden', reason: 'role_not_allowed' }, { status: 403 });
	}
	try {
		const status = await getEngineStatus({ logLimit: 40 });
		return json({ ok: true, status });
	} catch (err) {
		return json({ error: 'status_failed', message: err?.message || String(err) }, { status: 500 });
	}
}
