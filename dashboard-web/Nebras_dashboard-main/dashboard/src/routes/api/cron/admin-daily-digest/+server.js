/**
 * GET /api/cron/admin-daily-digest
 *
 * الموجز اليومي لدردشة الإدارة 📊 — يكتب رسالة نظام بإحصاءات الأمس ويرسل
 * إشعار topic، ويجسّر أيّ اقتراحات تصحيح معلّقة كاحتياط (الجسر السريع له
 * كرونه المستقلّ /api/cron/suggestions-bridge).
 *
 * الجدولة: GitHub Action يومي (Vercel Hobby مستنفَد بكرونَيه الحاليَّين).
 * المصادقة: نفس نمط بقيّة الكرونات — Bearer CRON_SECRET إن ضُبط.
 */
import { json } from '@sveltejs/kit';
import { env } from '$env/dynamic/private';
import { isAdminConfigured } from '$lib/server/firebaseAdmin.js';
import { postDailyDigest, bridgePendingSuggestions } from '$lib/server/adminChatBot.js';

/** @param {import('@sveltejs/kit').RequestEvent} event */
function authorizeCron(event) {
	const secret = String(env.CRON_SECRET || '').trim();
	if (!secret) {
		console.warn('[cron/admin-daily-digest] CRON_SECRET غير مضبوط — يُسمح بالنبضة.');
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
		const digest = await postDailyDigest();
		return json({ ok: true, digest, bridgedSuggestions: bridged });
	} catch (err) {
		console.error('[cron/admin-daily-digest] failed:', err);
		return json({ error: 'server_error', message: err?.message || 'unknown' }, { status: 500 });
	}
}
