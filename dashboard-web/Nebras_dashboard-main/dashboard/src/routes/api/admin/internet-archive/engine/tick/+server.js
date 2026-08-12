/**
 * POST /api/admin/internet-archive/engine/tick
 * يُنفّذ دورة واحدة (batch) من المحرّك. يُستدعى من Cron الخارجي على Vercel
 * (كلّ X دقيقة) — أو يدوياً من لوحة التحكّم للاختبار.
 *
 * Cron يستدعيه بـ `Authorization: Bearer <CRON_SECRET>`. الـ hook الخادمي
 * يسمح بالـ /api/cron/* بدون Firebase ID Token، لكن هذا المسار تحت /admin/
 * فيتطلّب توكن مدير عند الاستدعاء البشري.
 */
import { json } from '@sveltejs/kit';
import { runEngineTick } from '$lib/server/internetArchive/engine.js';
import { isAdminPanelRole } from '$lib/server/dashboardRoles.js';
import { INGEST_FROZEN, FROZEN_RESPONSE } from '$lib/server/ingestFreeze.js';

export async function POST(event) {
	// ❄️ الجلب مُجمّد بطلب المالك — لا ننفّذ أيّ دورة (2026-07-23).
	if (INGEST_FROZEN) return json(FROZEN_RESPONSE, { status: 200 });
	const auth = event.locals?.auth;
	if (!auth) return json({ error: 'unauthenticated' }, { status: 401 });
	if (!isAdminPanelRole(auth.role)) {
		return json({ error: 'forbidden', reason: 'role_not_allowed' }, { status: 403 });
	}
	try {
		const r = await runEngineTick();
		return json({ ok: true, ...r });
	} catch (err) {
		return json(
			{
				error: 'tick_failed',
				reason: err?.reason || 'unknown',
				message: err?.message || String(err)
			},
			{ status: err?.status || 500 }
		);
	}
}
