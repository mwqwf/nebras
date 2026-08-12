/**
 * POST /api/admin/noor-library/engine/tick
 *
 * يُنفّذ دورة واحدة (batch) من المحرّك بشكل مزامن، ثم يردّ بنتائجها.
 *
 * استخدامان:
 *   1) Manual debugging من الواجهة (زر "تشغيل دفعة الآن").
 *   2) Cron خارجي على Vercel (حيث لا تستمرّ حلقة في الذاكرة).
 *
 * 🔒 Nebras Only. لا يحتاج enabled=true (يمكن تشغيله يدويّاً حتى لو كان
 *    المحرّك متوقّفاً — مفيد للاختبار).
 */

import { json } from '@sveltejs/kit';
import { runEngineTick } from '$lib/server/noorLibrary/engine.js';
import { isAdminConfigured } from '$lib/server/firebaseAdmin.js';

export const config = {
	// Tick قد يستغرق دقائق (تنزيل/رفع كتب). في dev هذا مقبول؛ على Vercel
	// قد نحتاج رفعه عبر vercel.json (حدّ Pro).
	bodySizeLimit: 1024
};

/** @type {import('@sveltejs/kit').RequestHandler} */
export async function POST(event) {
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

	const startedAt = Date.now();
	try {
		const result = await runEngineTick();
		return json({ ok: true, elapsedMs: Date.now() - startedAt, ...result });
	} catch (err) {
		return json(
			{
				error: 'tick_failed',
				reason: err?.reason || 'tick_failed',
				message: err?.message || String(err),
				elapsedMs: Date.now() - startedAt
			},
			{ status: err?.status || 500 }
		);
	}
}
