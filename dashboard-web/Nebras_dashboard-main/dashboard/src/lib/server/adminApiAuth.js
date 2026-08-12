/**
 * تحقّق موحّد لمسارات /api/admin/* (owner أو supervisor + Admin SDK).
 */

import { json } from '@sveltejs/kit';
import { isAdminConfigured } from '$lib/server/firebaseAdmin.js';
import { isAdminPanelRole } from '$lib/server/dashboardRoles.js';

/**
 * @param {{ locals?: { auth?: { role?: string } } }} event
 * @returns {{ ok: true, auth: NonNullable<import('@sveltejs/kit').RequestEvent['locals']['auth']> } | { ok: false, response: Response }}
 */
export function requireAdminRole(event) {
	const auth = event.locals?.auth;
	if (!auth) {
		return { ok: false, response: json({ error: 'unauthenticated' }, { status: 401 }) };
	}
	if (!isAdminPanelRole(auth.role)) {
		return { ok: false, response: json({ error: 'forbidden', reason: 'role_not_allowed' }, { status: 403 }) };
	}
	return { ok: true, auth };
}

/** @returns {{ ok: true } | { ok: false, response: Response }} */
export function requireAdminSdk() {
	if (!isAdminConfigured()) {
		return {
			ok: false,
			response: json(
				{
					error: 'not_configured',
					reason: 'admin_service_account_missing',
					message:
						'تأكّد من ضبط NEBRAS_SERVICE_ACCOUNT_PATH أو NEBRAS_SERVICE_ACCOUNT_JSON في .env.'
				},
				{ status: 501 }
			)
		};
	}
	return { ok: true };
}
