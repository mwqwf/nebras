/**
 * POST /api/admin/noor-library/engine/start
 *
 * يُشعل علامة enabled في RTDB ويبدأ الحلقة في الذاكرة. آمن للاستدعاء
 * مرّتين (idempotent): إن كان المحرّك يعمل أصلاً، يردّ alreadyRunning=true.
 *
 * 🔒 Nebras Only — يُسجّل uploaderUid/Email تلقائيّاً للـ audit log.
 */

import { json } from '@sveltejs/kit';
import { startEngine, runEngineTick } from '$lib/server/noorLibrary/engine.js';
import { isAdminConfigured } from '$lib/server/firebaseAdmin.js';

/** @type {import('@sveltejs/kit').RequestHandler} */
export async function POST(event) {
	const auth = event.locals?.auth;
	if (!auth) return json({ error: 'unauthenticated' }, { status: 401 });
	if (auth.role !== 'owner' && auth.role !== 'supervisor') {
		return json({ error: 'forbidden', reason: 'role_not_allowed' }, { status: 403 });
	}
	if (!isAdminConfigured()) {
		return json(
			{
				error: 'not_configured',
				reason: 'admin_service_account_missing',
				message: 'تأكّد من أنّ NEBRAS_SERVICE_ACCOUNT_PATH معرَّف في .env و الملفّ موجود.'
			},
			{ status: 501 }
		);
	}

	try {
		const result = await startEngine();
		// دورة فوريّة (serverless لا تُبقي الحلقة). نور تحتاج crawl4ai فقد تفشل
		// الدورة بهدوء — لا نُفشل التشغيل بسببها.
		let tick = null;
		try {
			tick = await runEngineTick();
		} catch (e) {
			tick = { tickError: e?.message || String(e), reason: e?.reason || 'tick_failed' };
		}
		return json({ ok: true, ...result, tick, processed: tick?.processed, skipped: tick?.skipped, failed: tick?.failed });
	} catch (err) {
		return json(
			{
				error: 'start_failed',
				reason: err?.reason || 'start_failed',
				message: err?.message || String(err)
			},
			{ status: err?.status || 500 }
		);
	}
}
