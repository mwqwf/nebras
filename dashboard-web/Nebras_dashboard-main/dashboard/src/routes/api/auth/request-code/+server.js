/**
 * POST /api/auth/request-code
 *
 * يُولّد رمز تحقّق جديد (6 أرقام) ويُرسله إلى بريد المالك.
 * يشترط أن يكون الطلب مصحوباً بـ ID token صالح (مستخدم أكمل Google Sign-In
 * بنجاح) حتى لا يتمكّن أيّ زائر من إغراق بريد المالك بالرموز.
 *
 * Body: { idToken: string }
 *
 * Responses:
 *   200 { ok: true, delivered: boolean, expiresInSec: 600 }
 *        delivered=false يعني أنّ SMTP أو OWNER_EMAIL ناقصَي الإعداد —
 *        الرمز مُخزَّن وصالح لكنّه لم يُرسَل بالبريد. في وضع التطوير
 *        يظهر في console الخادم.
 *   200 { ok: false, reason: 'rate_limited', retryAfterSec: number }
 *        — طلب متكرّر بسرعة؛ انتظر قبل المحاولة.
 *   401 { error: 'invalid_token' }
 *   500 { error: 'server_error' }
 */

import { json } from '@sveltejs/kit';
import { getAdminDatabase, verifyIdToken } from '$lib/server/firebaseAdmin.js';
import { sendOwnerCode, isOwnerEmail } from '$lib/server/mailer.js';
import { issueNewCode } from '$lib/server/ownerCode.js';

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

	// دفاع في العمق: المالك لا يحتاج إلى رمز إطلاقاً (يدخل عبر Owner
	// Bypass في /api/auth/check). لو وصل هنا بطريقةٍ ما نرفض فوراً.
	if (isOwnerEmail(decoded.email)) {
		return json({ ok: false, reason: 'already_authorized' }, { status: 400 });
	}

	// إن كان المستخدم مُصرّحاً له أصلاً، لا معنى لطلب رمز مالك.
	try {
		const db = getAdminDatabase();
		const existing = await db.ref(`dashboard_users/${decoded.uid}`).get();
		if (existing.exists()) {
			return json({ ok: false, reason: 'already_authorized' }, { status: 400 });
		}
	} catch (err) {
		console.error('[api/auth/request-code] db check failed:', err);
	}

	let issued;
	try {
		issued = await issueNewCode();
	} catch (err) {
		console.error('[api/auth/request-code] issueNewCode failed:', err);
		return json({ error: 'server_error', message: err?.message || 'unknown' }, { status: 500 });
	}

	if (!issued.ok) {
		return json(
			{ ok: false, reason: issued.reason, retryAfterSec: Math.ceil(issued.retryAfterMs / 1000) },
			{ status: 200 }
		);
	}

	const { delivered } = await sendOwnerCode({
		code: issued.code,
		candidateEmail: decoded.email || '',
		candidateName: decoded.name || ''
	});

	return json({ ok: true, delivered, expiresInSec: 10 * 60 });
}
