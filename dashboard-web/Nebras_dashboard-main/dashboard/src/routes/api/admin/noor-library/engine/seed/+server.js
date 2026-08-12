/**
 * POST /api/admin/noor-library/engine/seed
 *
 * يحدّث قائمة البذور (Seed URLs) للمحرّك. يصفّي الروابط غير الصالحة، ثم
 * يُعيد المؤشّر للبذرة الأولى. لا يوقف المحرّك (يطبَّق التغيير تلقائيّاً
 * في الـ tick التالي).
 *
 * Body: { seedUrls: string[] }
 *
 * 🔒 Nebras Only.
 */

import { json } from '@sveltejs/kit';
import { updateSeedUrls, resetCursor } from '$lib/server/noorLibrary/engine.js';
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
			{ error: 'not_configured', reason: 'admin_service_account_missing' },
			{ status: 501 }
		);
	}

	let body;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'bad_request', reason: 'invalid_json' }, { status: 400 });
	}

	const seedUrls = Array.isArray(body?.seedUrls) ? body.seedUrls.map(String) : null;
	if (!seedUrls) {
		return json(
			{ error: 'bad_request', reason: 'seedUrls_array_required' },
			{ status: 400 }
		);
	}

	try {
		const cfg = await updateSeedUrls(seedUrls);
		return json({ ok: true, config: cfg });
	} catch (err) {
		return json(
			{
				error: 'seed_update_failed',
				reason: err?.reason || 'seed_update_failed',
				message: err?.message || String(err)
			},
			{ status: err?.status || 500 }
		);
	}
}

/**
 * DELETE /api/admin/noor-library/engine/seed — إعادة المؤشّر فقط (لا يمسّ البذور).
 */
export async function DELETE(event) {
	const auth = event.locals?.auth;
	if (!auth) return json({ error: 'unauthenticated' }, { status: 401 });
	if (auth.role !== 'owner' && auth.role !== 'supervisor') {
		return json({ error: 'forbidden', reason: 'role_not_allowed' }, { status: 403 });
	}
	try {
		const cursor = await resetCursor();
		return json({ ok: true, cursor });
	} catch (err) {
		return json(
			{ error: 'reset_failed', message: err?.message || String(err) },
			{ status: 500 }
		);
	}
}
