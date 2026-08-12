/**
 * GET /api/admin/internet-archive/sections
 *
 * يُعيد شجرة الأقسام الحاليّة. للعرض في الواجهة فقط — التصنيف الآليّ
 * في engine.js لا يحتاج هذا المسار.
 */
import { json } from '@sveltejs/kit';
import { buildSectionsTree } from '$lib/server/internetArchive/sectionsTree.js';
import { requireAdminRole, requireAdminSdk } from '$lib/server/adminApiAuth.js';

/** @type {import('@sveltejs/kit').RequestHandler} */
export async function GET(event) {
	const gate = requireAdminRole(event);
	if (!gate.ok) return gate.response;
	const sdk = requireAdminSdk();
	if (!sdk.ok) return sdk.response;

	try {
		const sections = await buildSectionsTree();
		return json({ ok: true, tree: sections.tree });
	} catch (err) {
		return json(
			{ error: 'sections_read_failed', message: err?.message || String(err) },
			{ status: 500 }
		);
	}
}
