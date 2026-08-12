/**
 * POST /api/admin/aggregates/popularity
 * يُعيد حساب aggregates_popular/top_weekly من view_count / play_count.
 */
import { json } from '@sveltejs/kit';
import { isAdminConfigured } from '$lib/server/firebaseAdmin.js';
import { runAggregatePopularity } from '$lib/server/aggregatePopularity.js';

/** @type {import('@sveltejs/kit').RequestHandler} */
export async function POST(event) {
	const auth = event.locals?.auth;
	if (!auth) return json({ error: 'unauthenticated' }, { status: 401 });
	if (auth.role !== 'owner' && auth.role !== 'supervisor') {
		return json({ error: 'forbidden' }, { status: 403 });
	}
	if (!isAdminConfigured()) {
		return json({ error: 'not_configured' }, { status: 501 });
	}
	try {
		const body = await event.request.json().catch(() => ({}));
		const limit = Number(body?.limit) || 50;
		const result = await runAggregatePopularity({ limit });
		return json({ ok: true, ...result });
	} catch (err) {
		console.error('[aggregates/popularity]', err);
		return json({ error: String(err?.message || err) }, { status: 500 });
	}
}
