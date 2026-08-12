/**
 * GET /api/admin/noor-library/engine/status
 *
 * يُرجع حالة المحرّك الآلي الكاملة:
 *   - config (enabled, seedUrls, throttle, batch)
 *   - cursor (seedIndex, page)
 *   - stats (totalFetched, sectionsCreated, lastRunAt, lastError, runsCount)
 *   - log (آخر 30 إدخال — افتراضي، قابل للتجاوز عبر ?limit=)
 *   - processRunning (هل الحلقة في الذاكرة فعلاً تعمل؟)
 *
 * يُحاول autoBoot إن كان enabled=true في DB ولا حلقة في الذاكرة (مفيد بعد
 * إعادة تشغيل dev server).
 *
 * 🔒 Nebras Only.
 */

import { json } from '@sveltejs/kit';
import { getEngineStatus } from '$lib/server/noorLibrary/engine.js';
import { isAdminConfigured } from '$lib/server/firebaseAdmin.js';

/** @type {import('@sveltejs/kit').RequestHandler} */
export async function GET(event) {
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

	const limit = Math.max(1, Math.min(60, Number(event.url.searchParams.get('limit')) || 30));

	try {
		const status = await getEngineStatus({ logLimit: limit });
		return json({
			ok: true,
			...status
		});
	} catch (err) {
		return json(
			{
				error: 'internal_error',
				reason: err?.reason || 'status_failed',
				message: err?.message || String(err)
			},
			{ status: err?.status || 500 }
		);
	}
}
