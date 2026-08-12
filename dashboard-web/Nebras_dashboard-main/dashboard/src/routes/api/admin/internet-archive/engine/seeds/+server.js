/**
 * PUT /api/admin/internet-archive/engine/seeds
 */
import { json } from '@sveltejs/kit';
import { updateSeeds } from '$lib/server/internetArchive/engine.js';
import { requireAdminRole, requireAdminSdk } from '$lib/server/adminApiAuth.js';

/** @type {import('@sveltejs/kit').RequestHandler} */
export async function PUT(event) {
	const gate = requireAdminRole(event);
	if (!gate.ok) return gate.response;
	const sdk = requireAdminSdk();
	if (!sdk.ok) return sdk.response;

	let body;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'bad_request', reason: 'invalid_json' }, { status: 400 });
	}
	const seeds = body?.seeds;
	if (!Array.isArray(seeds)) {
		return json({ error: 'bad_request', reason: 'seeds_array_required' }, { status: 400 });
	}
	try {
		const cfg = await updateSeeds(seeds);
		return json({ ok: true, config: cfg });
	} catch (err) {
		return json({ error: 'seeds_update_failed', message: err?.message || String(err) }, { status: 500 });
	}
}
