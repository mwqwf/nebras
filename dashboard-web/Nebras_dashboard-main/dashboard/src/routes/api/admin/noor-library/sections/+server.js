/**
 * GET /api/admin/noor-library/sections
 *
 * يُرجع شجرة الأقسام الكاملة [main → sub → secondary] لإظهارها في صفحة
 * الجلب وتمكين المستخدم من اختيار/تعديل المسار قبل التأكيد.
 *
 * الحماية: hooks.server.js يضمن Bearer صالح + dashboard_users + !blocked.
 *           إضافياً نشترط دور owner أو supervisor.
 */

import { json } from '@sveltejs/kit';
import { buildSectionsTree } from '$lib/server/noorLibrary/sectionsTree.js';

/** @type {import('@sveltejs/kit').RequestHandler} */
export async function GET(event) {
	const auth = event.locals?.auth;
	if (!auth) return json({ error: 'unauthenticated' }, { status: 401 });
	if (auth.role !== 'owner' && auth.role !== 'supervisor') {
		return json({ error: 'forbidden', reason: 'role_not_allowed' }, { status: 403 });
	}

	try {
		const sections = await buildSectionsTree();
		return json({
			ok: true,
			tree: sections.tree,
			counts: {
				mains: sections.flat.mains.length,
				subs: sections.flat.subs.length,
				secondaries: sections.flat.secondaries.length
			},
		});
	} catch (err) {
		return json(
			{ error: 'internal_error', message: err?.message || String(err) },
			{ status: 500 }
		);
	}
}
