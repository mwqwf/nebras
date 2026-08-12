/**
 * GET /api/admin/noor-library/jobs?limit=30
 *
 * يُرجع آخر مهام جلب من مكتبة نور (مرتّبة من الأحدث للأقدم) لعرضها في
 * شريط "آخر العمليات" داخل صفحة الجلب.
 */

import { json } from '@sveltejs/kit';
import { listRecentJobs } from '$lib/server/noorLibrary/adminUploader.js';

/** @type {import('@sveltejs/kit').RequestHandler} */
export async function GET(event) {
	const auth = event.locals?.auth;
	if (!auth) return json({ error: 'unauthenticated' }, { status: 401 });
	if (auth.role !== 'owner' && auth.role !== 'supervisor') {
		return json({ error: 'forbidden', reason: 'role_not_allowed' }, { status: 403 });
	}

	const limit = Math.max(1, Math.min(100, Number(event.url.searchParams.get('limit')) || 30));

	try {
		const jobs = await listRecentJobs(limit);
		return json({ ok: true, jobs });
	} catch (err) {
		return json(
			{ error: 'internal_error', message: err?.message || String(err) },
			{ status: 500 }
		);
	}
}
