/**
 * يزامن Custom Claims على Firebase Auth مع سجلّ `dashboard_users` في RTDB
 * حتى تطابق قواعد Firestore (`request.auth.token.role`) صلاحيّة المشرف فعليّاً.
 *
 * يُستدعى من مسارات `/api/auth/*` و`/api/admin/supervisors/*` بعد أيّ تعديل
 * على السجلّ — والعميل يجب أن يستدعي `getIdToken(true)` لاحقاً ليحمّل التوكن
 * المحدَّث قبل كتابات Firestore من المتصفّح.
 */
import { getAdminAuthService, getAdminDatabase } from '$lib/server/firebaseAdmin.js';

/**
 * @param {string} uid
 * @returns {Promise<void>}
 */
export async function syncNebrasDashboardClaimsForUid(uid) {
	const id = String(uid || '').trim();
	if (!id) return;

	const auth = getAdminAuthService();
	let snap;
	try {
		snap = await getAdminDatabase().ref(`dashboard_users/${id}`).get();
	} catch (err) {
		console.warn('[dashboardClaimsSync] RTDB read failed:', err?.message || err);
		return;
	}

	if (!snap.exists()) {
		try {
			await auth.setCustomUserClaims(id, {});
		} catch (err) {
			console.warn('[dashboardClaimsSync] clear claims failed:', err?.message || err);
		}
		return;
	}

	const v = snap.val() || {};
	if (v.isBlocked === true) {
		try {
			await auth.setCustomUserClaims(id, {});
		} catch (err) {
			console.warn('[dashboardClaimsSync] blocked clear failed:', err?.message || err);
		}
		return;
	}

	const rawRole =
		v.role === 'admin' || v.role === 'moderator'
			? 'supervisor'
			: v.role || 'supervisor';
	if (rawRole === 'owner') {
		try {
			await auth.setCustomUserClaims(id, { role: 'owner' });
		} catch (err) {
			console.warn('[dashboardClaimsSync] set owner failed:', err?.message || err);
		}
		return;
	}
	if (rawRole === 'supervisor') {
		try {
			await auth.setCustomUserClaims(id, { role: 'supervisor' });
		} catch (err) {
			console.warn('[dashboardClaimsSync] set supervisor failed:', err?.message || err);
		}
		return;
	}

	try {
		await auth.setCustomUserClaims(id, {});
	} catch (err) {
		console.warn('[dashboardClaimsSync] reset claims failed:', err?.message || err);
	}
}
