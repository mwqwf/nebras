/**
 * POST /api/admin/internet-archive/engine/bootstrap
 *
 * زرّ واحد يفعّل كل شيء آلياً:
 *   - يضع DEFAULT_SEEDS لو الإعدادات فارغة
 *   - enabled=true
 *   - يُعيد المؤشّر للبداية
 *   - يطلق أوّل tick فوراً (يجلب أوّل دفعة وينشئ أقساماً تلقائياً)
 *
 * بعد ثوانٍ يظهر محتوى في التطبيق دون أيّ تدخّل بشري آخر.
 */
import { json } from '@sveltejs/kit';
import { bootstrap } from '$lib/server/internetArchive/engine.js';
import { requireAdminRole, requireAdminSdk } from '$lib/server/adminApiAuth.js';

/** @type {import('@sveltejs/kit').RequestHandler} */
export async function POST(event) {
	const gate = requireAdminRole(event);
	if (!gate.ok) return gate.response;
	const sdk = requireAdminSdk();
	if (!sdk.ok) return sdk.response;
	try {
		const r = await bootstrap();
		return json({ ok: true, ...r });
	} catch (err) {
		return json(
			{
				error: 'bootstrap_failed',
				reason: err?.reason || 'unknown',
				message: err?.message || String(err)
			},
			{ status: err?.status || 500 }
		);
	}
}
