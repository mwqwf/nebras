/**
 * POST /api/admin/internet-archive/preview
 *
 * يفحص عنصر IA دون كتابته في DB:
 *   1) يجلب metadata الكامل
 *   2) يفحص الترخيص (licenseFilter)
 *   3) يختار أفضل ملف قابل للتشغيل (playabilityFilter)
 *   4) يُعيد كائن preview جاهز للعرض في لوحة التحكّم
 *
 * Body:
 *   {
 *     identifier: string,
 *     trustedCollections?: string[],
 *     allowMissingLicenseInTrustedCollections?: boolean
 *   }
 *
 * Response:
 *   { ok: true, preview }   عند النجاح
 *   { error, reason, message } عند الفشل (ترخيص/صيغ/جلب)
 */

import { json } from '@sveltejs/kit';
import { isAdminPanelRole } from '$lib/server/dashboardRoles.js';
import { previewItem } from '$lib/server/internetArchive/fetcher.js';

/** @type {import('@sveltejs/kit').RequestHandler} */
export async function POST(event) {
	const auth = event.locals?.auth;
	if (!auth) return json({ error: 'unauthenticated' }, { status: 401 });
	if (!isAdminPanelRole(auth.role)) {
		return json({ error: 'forbidden', reason: 'role_not_allowed' }, { status: 403 });
	}

	let body;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'bad_request', reason: 'invalid_json' }, { status: 400 });
	}

	const identifier = String(body?.identifier || '').trim();
	if (!identifier) {
		return json({ error: 'bad_request', reason: 'identifier_required' }, { status: 400 });
	}

	try {
		const preview = await previewItem(identifier, {
			trustedCollections: Array.isArray(body?.trustedCollections)
				? body.trustedCollections
				: undefined,
			allowMissingLicenseInTrustedCollections: Boolean(
				body?.allowMissingLicenseInTrustedCollections
			)
		});
		return json({ ok: true, preview });
	} catch (err) {
		return json(
			{
				error: 'preview_failed',
				reason: err?.reason || 'unknown',
				message: err?.message || String(err)
			},
			{ status: err?.status || 422 }
		);
	}
}
