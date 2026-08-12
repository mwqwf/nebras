/**
 * POST /api/admin/internet-archive/search
 *
 * بحث Internet Archive عبر Scraping API. يستقبل عوامل تصفية وُيُرجع
 * صفحة واحدة من النتائج مع cursor للصفحة التالية (pagination كاملة).
 *
 * Body:
 *   {
 *     q?: string,
 *     nebrasTypes?: Array<'document'|'audio'|'video'>,
 *     languages?: string[],
 *     collections?: string[],
 *     creators?: string[],
 *     cursor?: string,         // null لأوّل صفحة
 *     count?: number            // ≤ 1000
 *   }
 *
 * Response:
 *   { ok: true, items, nextCursor, total, exhausted, query }
 */

import { json } from '@sveltejs/kit';
import { isAdminPanelRole } from '$lib/server/dashboardRoles.js';
import { buildLuceneQuery, scrapeOnePage } from '$lib/server/internetArchive/search.js';

/** @type {import('@sveltejs/kit').RequestHandler} */
export async function POST(event) {
	const auth = event.locals?.auth;
	if (!auth) return json({ error: 'unauthenticated' }, { status: 401 });
	if (!isAdminPanelRole(auth.role)) {
		return json({ error: 'forbidden', reason: 'role_not_allowed' }, { status: 403 });
	}

	let body;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'bad_request', reason: 'invalid_json' }, { status: 400 });
	}

	const query = buildLuceneQuery({
		q: body?.q,
		nebrasTypes: body?.nebrasTypes,
		languages: body?.languages,
		collections: body?.collections,
		creators: body?.creators
	});

	if (!query) {
		return json(
			{ error: 'bad_request', reason: 'empty_query' },
			{ status: 400 }
		);
	}

	try {
		const result = await scrapeOnePage({
			query,
			count: Number(body?.count || 50),
			cursor: typeof body?.cursor === 'string' ? body.cursor : null
		});
		return json({ ok: true, query, ...result });
	} catch (err) {
		return json(
			{
				error: 'search_failed',
				reason: err?.reason || 'unknown',
				message: err?.message || String(err)
			},
			{ status: err?.status || 502 }
		);
	}
}
