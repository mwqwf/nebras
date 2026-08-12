/**
 * GET /api/cron/suggestions-bridge
 *
 * جسر اقتراحات التصحيح ✏️ — كلّ اقتراح `content_suggestions` معلّق يتحوّل
 * رسالة نظام في دردشة الإدارة + إشعار topic، ويُوسم bridged (idempotent).
 *
 * الجدولة: GitHub Action كلّ 15 دقيقة (suggestions-bridge.yml) — يصل
 * الاقتراح للمشرفين خلال دقائق فيُصلحونه من هواتفهم.
 */
import { json } from '@sveltejs/kit';
import { env } from '$env/dynamic/private';
import { isAdminConfigured } from '$lib/server/firebaseAdmin.js';
import { bridgePendingSuggestions } from '$lib/server/adminChatBot.js';

/** @param {import('@sveltejs/kit').RequestEvent} event */
function authorizeCron(event) {
	const secret = String(env.CRON_SECRET || '').trim();
	if (!secret) {
		console.warn('[cron/suggestions-bridge] CRON_SECRET غير مضبوط — يُسمح بالنبضة.');
		return { ok: true };
	}
	const header = event.request.headers.get('authorization') || '';
	const m = /^Bearer\s+(.+)$/i.exec(header.trim());
	if (!m || m[1].trim() !== secret) return { ok: false, reason: 'invalid_cron_secret' };
	return { ok: true };
}

/** @type {import('@sveltejs/kit').RequestHandler} */
export async function GET(event) {
	const auth = authorizeCron(event);
	if (!auth.ok) return json({ error: 'unauthorized', reason: auth.reason }, { status: 401 });
	if (!isAdminConfigured()) return json({ error: 'not_configured' }, { status: 501 });
	try {
		const bridged = await bridgePendingSuggestions();
		return json({ ok: true, bridgedSuggestions: bridged });
	} catch (err) {
		console.error('[cron/suggestions-bridge] failed:', err);
		return json({ error: 'server_error', message: err?.message || 'unknown' }, { status: 500 });
	}
}
