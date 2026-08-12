import { json } from '@sveltejs/kit';
import { requireOwner } from '$lib/server/authGuard.js';
import { crawl4aiConfigured, crawl4aiFetch } from '$lib/server/crawl4aiClient.js';

/** @type {import('@sveltejs/kit').RequestHandler} */
export async function POST(event) {
	const denied = requireOwner(event);
	if (denied) return denied;

	if (!crawl4aiConfigured()) {
		return json(
			{
				error: 'not_configured',
				message: 'Set CRAWL4AI_SERVICE_URL in dashboard .env (server-side).'
			},
			{ status: 501 }
		);
	}

	let payload = {};
	try {
		payload = await event.request.json();
	} catch {
		return json({ error: 'bad_request' }, { status: 400 });
	}

	const action = String(payload?.action || '').trim().toLowerCase();
	if (action !== 'start' && action !== 'stop') {
		return json({ error: 'bad_request', message: 'action must be start or stop' }, { status: 400 });
	}

	try {
		const res = await crawl4aiFetch('/control', {
			method: 'POST',
			body: JSON.stringify({ action })
		});
		if (!res) {
			return json({ error: 'not_configured' }, { status: 501 });
		}
		const body = await res.json().catch(() => ({}));
		return json(body, { status: res.status });
	} catch (err) {
		const msg = err?.name === 'AbortError' ? 'crawl4ai_timeout' : err?.message || 'upstream_error';
		return json({ error: 'upstream_unreachable', message: msg }, { status: 502 });
	}
}
