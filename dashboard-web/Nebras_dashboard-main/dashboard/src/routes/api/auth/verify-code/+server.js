/**
 * POST /api/auth/verify-code
 *
 * التحقّق النهائي من رمز التحقّق ثم تسجيل المستخدم في قائمة المصرّح لهم.
 * بعد هذه العمليّة يصبح المستخدم "معترفاً به" وتسجيلات الدخول اللاحقة
 * تعمل بلا رمز (/api/auth/check → authorized=true).
 *
 * Body: { idToken: string, code: string }
 *
 * Responses:
 *   200 { ok: true, user: { uid, email, displayName, photoURL } }
 *   200 { ok: false, reason: 'no_code'|'expired'|'invalid'|'too_many_attempts' }
 *   401 { error: 'invalid_token' }
 *   500 { error: 'server_error' }
 */

import { json } from '@sveltejs/kit';
import { getAdminDatabase, verifyIdToken } from '$lib/server/firebaseAdmin.js';
import { syncNebrasDashboardClaimsForUid } from '$lib/server/dashboardClaimsSync.js';
import { verifyCode } from '$lib/server/ownerCode.js';

/** @type {import('@sveltejs/kit').RequestHandler} */
export async function POST({ request }) {
	let body;
	try {
		body = await request.json();
	} catch {
		return json({ error: 'invalid_json' }, { status: 400 });
	}

	let decoded;
	try {
		decoded = await verifyIdToken(body?.idToken);
	} catch (err) {
		return json(
			{ error: 'invalid_token', message: err?.message || 'token verification failed' },
			{ status: 401 }
		);
	}

	const result = await verifyCode(body?.code);
	if (!result.ok) {
		return json({ ok: false, reason: result.reason });
	}

	const uid = decoded.uid;
	const userInfo = {
		uid,
		email: decoded.email || '',
		displayName: decoded.name || '',
		photoURL: decoded.picture || ''
	};

	try {
		const now = Date.now();
		await getAdminDatabase()
			.ref(`dashboard_users/${uid}`)
			.set({
				...userInfo,
				role: 'supervisor',
				isBlocked: false,
				createdAt: now,
				lastSignedInAt: now,
				createdVia: 'otp_approval'
			});
		await syncNebrasDashboardClaimsForUid(uid);
	} catch (err) {
		console.error('[api/auth/verify-code] failed to write user:', err);
		return json({ error: 'server_error', message: err?.message || 'unknown' }, { status: 500 });
	}

	return json({ ok: true, user: { ...userInfo, role: 'supervisor', isBlocked: false } });
}
