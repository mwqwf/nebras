/**
 * GET /api/cron/aggregates-popularity
 *
 * جدولة Vercel Cron — يعيد حساب aggregates_popular/top_weekly.
 * يتطلّب رأس Authorization: Bearer <CRON_SECRET> (متغيّر بيئة على Vercel).
 *
 * لا يمرّ عبر hooks /api/admin/* — مصادقة سرّ التشغيل فقط.
 */
import { json } from '@sveltejs/kit';
import { env } from '$env/dynamic/private';
import { isAdminConfigured } from '$lib/server/firebaseAdmin.js';
import { runAggregatePopularity } from '$lib/server/aggregatePopularity.js';

/** @param {import('@sveltejs/kit').RequestEvent} event */
function authorizeCron(event) {
	const secret = String(env.CRON_SECRET || '').trim();
	// 🔐 secure-by-configuration: صارم إن ضُبط CRON_SECRET، ويسمح إن لم يُضبط
	// (يعيد احتساب aggregates لا يكشف بيانات؛ التقوية بإضافة المتغيّر فقط).
	if (!secret) {
		console.warn(
			'[cron/aggregates-popularity] CRON_SECRET غير مضبوط — يُسمح بالنبضة. اضبطه للتقوية (fail-closed).'
		);
		return { ok: true, unauthenticated: true };
	}
	const header =
		event.request.headers.get('authorization') ||
		event.request.headers.get('Authorization') ||
		'';
	const m = /^Bearer\s+(.+)$/i.exec(header.trim());
	const token = m ? m[1].trim() : '';
	if (!token || token !== secret) return { ok: false, reason: 'invalid_cron_secret' };
	return { ok: true };
}

/** @type {import('@sveltejs/kit').RequestHandler} */
export async function GET(event) {
	const auth = authorizeCron(event);
	if (!auth.ok) {
		return json({ error: 'unauthorized', reason: auth.reason }, { status: 401 });
	}
	if (!isAdminConfigured()) {
		return json({ error: 'not_configured' }, { status: 501 });
	}
	try {
		const limit = Number(event.url.searchParams.get('limit')) || 50;
		const result = await runAggregatePopularity({ limit });
		return json({ ok: true, cron: true, ...result });
	} catch (err) {
		console.error('[cron/aggregates-popularity]', err);
		return json({ error: String(err?.message || err) }, { status: 500 });
	}
}
