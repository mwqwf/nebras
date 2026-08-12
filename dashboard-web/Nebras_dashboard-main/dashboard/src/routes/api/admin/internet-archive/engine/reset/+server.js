/**
 * POST /api/admin/internet-archive/engine/reset
 *
 * type=cursor → إعادة المؤشّر فقط (غير مدمّر).
 * 🛑 type=factory (الحذف الشامل لكلّ المحتوى) أُزيل نهائيًّا — يُرفض هنا.
 */
import { json } from '@sveltejs/kit';
import { resetCursor } from '$lib/server/internetArchive/engine.js';
import { requireAdminRole, requireAdminSdk } from '$lib/server/adminApiAuth.js';

/** @type {import('@sveltejs/kit').RequestHandler} */
export async function POST(event) {
	const gate = requireAdminRole(event);
	if (!gate.ok) return gate.response;
	const sdk = requireAdminSdk();
	if (!sdk.ok) return sdk.response;

	let body;
	try {
		body = await event.request.json();
	} catch {
		body = {};
	}
	const type = String(body?.type || 'cursor').toLowerCase();

	// 🛑 الحذف الشامل أُزيل نهائيًّا — لا يُمكن استدعاؤه حتى لو وصل الطلب مباشرةً.
	if (type === 'factory') {
		return json(
			{ error: 'feature_removed', message: 'خاصيّة الحذف الشامل أُزيلت نهائيًّا.' },
			{ status: 410 }
		);
	}

	try {
		const c = await resetCursor();
		return json({ ok: true, type: 'cursor', cursor: c });
	} catch (err) {
		return json({ error: 'reset_failed', message: err?.message || String(err) }, { status: 500 });
	}
}
