/**
 * Supervisor Actions — للمالك فقط.
 *
 * PATCH  /api/admin/supervisors/:uid      — تبديل حالة الحظر.
 *   Body: { isBlocked: boolean, mode?: 'temporary'|'permanent' }
 *         (mode حالياً يُسجَّل كوسم توضيحي فقط في blockReason — السلوك
 *          الفعلي واحد: isBlocked=true يمنع الدخول فوراً.)
 *   Response 200: { ok: true, supervisor: {...} }
 *
 * DELETE /api/admin/supervisors/:uid      — حذف المشرف نهائيّاً من قائمة
 *                                            الـ admins (Permanent Ban).
 *   Response 200: { ok: true, removed: true }
 *
 * قيود الأمان:
 *   • owner-only (عبر requireOwner + hooks.server.js).
 *   • لا يمكن حظر/حذف سجلّ بدور 'owner' أو نفس المنادي.
 */

import { json } from '@sveltejs/kit';
import { getAdminDatabase } from '$lib/server/firebaseAdmin.js';
import { syncNebrasDashboardClaimsForUid } from '$lib/server/dashboardClaimsSync.js';
import { requireOwner } from '$lib/server/authGuard.js';

function badRequest(reason) {
	return json({ error: 'bad_request', reason }, { status: 400 });
}

async function readSupervisor(uid) {
	const ref = getAdminDatabase().ref(`dashboard_users/${uid}`);
	const snap = await ref.get();
	return { ref, snap, value: snap.exists() ? snap.val() : null };
}

function sanitizeOutput(uid, v) {
	return {
		uid,
		email: v.email || '',
		displayName: v.displayName || '',
		photoURL: v.photoURL || '',
		role: v.role === 'admin' ? 'supervisor' : v.role || 'supervisor',
		isBlocked: v.isBlocked === true,
		createdAt: typeof v.createdAt === 'number' ? v.createdAt : null,
		lastSignedInAt: typeof v.lastSignedInAt === 'number' ? v.lastSignedInAt : null,
		blockedAt: typeof v.blockedAt === 'number' ? v.blockedAt : null,
		blockedBy: v.blockedBy || null,
		blockMode: v.blockMode || null
	};
}

/** @type {import('@sveltejs/kit').RequestHandler} */
export async function PATCH(event) {
	const denied = requireOwner(event);
	if (denied) return denied;

	const { params, request, locals } = event;
	const uid = (params.uid || '').trim();
	if (!uid) return badRequest('missing_uid');

	let body;
	try {
		body = await request.json();
	} catch {
		return badRequest('invalid_json');
	}

	if (typeof body?.isBlocked !== 'boolean') {
		return badRequest('isBlocked_required_boolean');
	}
	const modeRaw = body?.mode;
	const mode = modeRaw === 'permanent' ? 'permanent' : 'temporary';

	// منع المالك من قَفل نفسه.
	if (locals?.auth?.uid === uid) {
		return json({ error: 'forbidden', reason: 'cannot_modify_self' }, { status: 403 });
	}

	try {
		const { ref, snap, value } = await readSupervisor(uid);
		if (!snap.exists() || !value) {
			return json({ error: 'not_found' }, { status: 404 });
		}
		if (value.role === 'owner') {
			return json({ error: 'forbidden', reason: 'cannot_modify_owner' }, { status: 403 });
		}

		const now = Date.now();
		/** @type {Record<string, any>} */
		const patch = {
			isBlocked: body.isBlocked
		};
		if (body.isBlocked) {
			patch.blockedAt = now;
			patch.blockedBy = locals?.auth?.uid || null;
			patch.blockMode = mode;
		} else {
			patch.blockedAt = null;
			patch.blockedBy = null;
			patch.blockMode = null;
		}

		await ref.update(patch);
		await syncNebrasDashboardClaimsForUid(uid);

		const after = { ...value, ...patch };
		return json({ ok: true, supervisor: sanitizeOutput(uid, after) });
	} catch (err) {
		console.error('[api/admin/supervisors/:uid] patch failed:', err);
		return json({ error: 'server_error', message: err?.message || 'unknown' }, { status: 500 });
	}
}

/** @type {import('@sveltejs/kit').RequestHandler} */
export async function DELETE(event) {
	const denied = requireOwner(event);
	if (denied) return denied;

	const { params, locals } = event;
	const uid = (params.uid || '').trim();
	if (!uid) return badRequest('missing_uid');

	if (locals?.auth?.uid === uid) {
		return json({ error: 'forbidden', reason: 'cannot_remove_self' }, { status: 403 });
	}

	try {
		const { ref, snap, value } = await readSupervisor(uid);
		if (!snap.exists() || !value) {
			return json({ error: 'not_found' }, { status: 404 });
		}
		if (value.role === 'owner') {
			return json({ error: 'forbidden', reason: 'cannot_remove_owner' }, { status: 403 });
		}
		await ref.remove();
		await syncNebrasDashboardClaimsForUid(uid);
		return json({ ok: true, removed: true });
	} catch (err) {
		console.error('[api/admin/supervisors/:uid] delete failed:', err);
		return json({ error: 'server_error', message: err?.message || 'unknown' }, { status: 500 });
	}
}
