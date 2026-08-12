/** GET /api/admin/hindawi-library/engine/status */
import { json } from '@sveltejs/kit';
import { getEngineStatus } from '$lib/server/hindawi/engine.js';
import { isAdminConfigured } from '$lib/server/firebaseAdmin.js';

/** @type {import('@sveltejs/kit').RequestHandler} */
export async function GET(event) {
	const auth = event.locals?.auth;
	if (!auth) return json({ error: 'unauthenticated' }, { status: 401 });
	if (auth.role !== 'owner' && auth.role !== 'supervisor') {
		return json({ error: 'forbidden', reason: 'role_not_allowed' }, { status: 403 });
	}
	if (!isAdminConfigured()) {
		return json({ error: 'not_configured' }, { status: 501 });
	}
	try {
		const status = await getEngineStatus({ logLimit: 30 });
		return json({ ok: true, ...status });
	} catch (err) {
		return json(
			{ error: 'status_failed', reason: err?.reason || 'status_failed', message: err?.message || String(err) },
			{ status: err?.status || 500 }
		);
	}
}
