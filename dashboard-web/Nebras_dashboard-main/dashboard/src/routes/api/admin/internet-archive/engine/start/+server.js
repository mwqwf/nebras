/**
 * POST /api/admin/internet-archive/engine/start
 * يضع enabled=true. على Vercel يكفي مع Cron الخارجي كل 15 دقيقة.
 */
import { json } from '@sveltejs/kit';
import { startEngine } from '$lib/server/internetArchive/engine.js';
import { requireAdminRole, requireAdminSdk } from '$lib/server/adminApiAuth.js';

/** @type {import('@sveltejs/kit').RequestHandler} */
export async function POST(event) {
	const gate = requireAdminRole(event);
	if (!gate.ok) return gate.response;
	const sdk = requireAdminSdk();
	if (!sdk.ok) return sdk.response;
	try {
		const r = await startEngine();
		return json({ ok: true, ...r });
	} catch (err) {
		return json({ error: 'start_failed', message: err?.message || String(err) }, { status: 500 });
	}
}
