/**
 * POST /api/auth/check
 *
 * يستقبل ID token صادر من Firebase Auth في العميل، ويقرّر صلاحيّة
 * المستخدم وفق سياسة المصادقة الصارمة:
 *
 *   1) Google Sign-In حصراً (لا Email/Password إطلاقاً).
 *   2) Owner Bypass: إذا كان البريد القادم من Google يطابق OWNER_EMAIL
 *      في `.env` (بعد trim + lowercase) يُمنَح صلاحيّات الإدارة الكاملة
 *      فوراً، ويُسجَّل في `dashboard_users/{uid}` بدور `owner`، دون أيّ
 *      شاشة انتظار أو طلب رمز.
 *   3) أي مستخدم آخر:
 *        • إن كان مُدرَجاً مسبقاً في `dashboard_users` → authorized:true.
 *        • وإلا → needsOwnerCode:true (يُرسَل الرمز إلى المالك في طلب
 *          لاحق عبر /api/auth/request-code).
 *
 * Body: { idToken: string }
 *
 * Responses:
 *   200 { authorized: true,  user: { uid, email, displayName, photoURL, role, isBlocked } }
 *   200 { authorized: false, blocked: true,  user: {...} }        // supervisor موقوف
 *   200 { authorized: false, needsOwnerCode: true, user: {...} }
 *   401 { error: 'invalid_token' }
 *   500 { error: 'server_error' }
 *
 * ملاحظات ترقية الصلاحيّات (Owner vs Supervisor):
 *   • أيّ سجلّ قديم بدور 'admin' يُهاجَر تلقائيّاً إلى 'supervisor' بشكل idempotent.
 *   • أيّ سجلّ بلا حقل isBlocked يُضاف له isBlocked:false (Backfill آمن).
 *   • حساب المالك (OWNER_EMAIL) يُثبَّت دوماً على role:'owner' و isBlocked:false
 *     (لا يمكن قَفل المالك على نفسه).
 */

import { json } from '@sveltejs/kit';
import { getAdminDatabase, verifyIdToken } from '$lib/server/firebaseAdmin.js';
import { syncNebrasDashboardClaimsForUid } from '$lib/server/dashboardClaimsSync.js';
import { isOwnerEmail } from '$lib/server/mailer.js';
import { normalizeDashboardRole } from '$lib/server/dashboardRoles.js';

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

	const uid = decoded.uid;
	const email = decoded.email || '';
	const userInfo = {
		uid,
		email,
		displayName: decoded.name || '',
		photoURL: decoded.picture || ''
	};

	try {
		const db = getAdminDatabase();
		const userRef = db.ref(`dashboard_users/${uid}`);
		const snap = await userRef.get();

		// ─── 1) Owner Bypass ───────────────────────────────────────────
		// نتحقّق من هوية المالك عبر البريد الذي رجع من Google (decoded.email)
		// بعد التحقّق من ID token، فلا يمكن تزويره من المتصفّح. إذا تطابق،
		// نضمن وجود السجلّ في قاعدة البيانات (idempotent) ثم نعيده authorized.
		// المالك لا يمكن حظره على نفسه — نُصلح isBlocked إلى false دائماً.
		if (isOwnerEmail(email)) {
			const now = Date.now();
			if (snap.exists()) {
				const val = snap.val() || {};
				const patch = { lastSignedInAt: now };
				if (val.role !== 'owner') patch.role = 'owner';
				if (val.isBlocked !== false) patch.isBlocked = false;
				await userRef.update(patch).catch(() => {});
			} else {
				await userRef.set({
					...userInfo,
					role: 'owner',
					isBlocked: false,
					createdAt: now,
					lastSignedInAt: now,
					createdVia: 'owner_bypass'
				});
			}
			await syncNebrasDashboardClaimsForUid(uid);
			return json({
				authorized: true,
				user: { ...userInfo, role: 'owner', isBlocked: false }
			});
		}

		// ─── 2) مستخدم مُعتمَد مسبقاً ───────────────────────────────────
		if (snap.exists()) {
			const val = snap.val() || {};

			// Backfill/Migration idempotent:
			//   - الدور القديم 'admin' يُرقَّى إلى 'supervisor'.
			//   - isBlocked يُضاف إن كان ناقصاً (للسجلّات القديمة فقط).
			const migration = {};
			if (val.role === 'admin') migration.role = 'supervisor';
			if (typeof val.isBlocked !== 'boolean') migration.isBlocked = false;

			const effectiveRole = normalizeDashboardRole(email, {
				role: migration.role || val.role
			});
			const effectiveBlocked =
				typeof val.isBlocked === 'boolean' ? val.isBlocked : false;

			// حظر → نرفض وننبّه العميل ليُجبِر تسجيل الخروج.
			if (effectiveBlocked === true) {
				// نطبّق الـ migration فقط (إن وُجد) دون تحديث lastSignedInAt لأنّه
				// لم يُسمَح له فعليّاً بالدخول.
				if (Object.keys(migration).length > 0) {
					await userRef.update(migration).catch(() => {});
				}
				await syncNebrasDashboardClaimsForUid(uid);
				return json({
					authorized: false,
					blocked: true,
					user: { ...userInfo, role: effectiveRole, isBlocked: true }
				});
			}

			const patch = { lastSignedInAt: Date.now(), ...migration };
			await userRef.update(patch).catch(() => {});

			await syncNebrasDashboardClaimsForUid(uid);
			return json({
				authorized: true,
				user: { ...userInfo, role: effectiveRole, isBlocked: false }
			});
		}

		// ─── 3) مستخدم جديد غير المالك → يحتاج رمز المالك ───────────────
		return json({ authorized: false, needsOwnerCode: true, user: userInfo });
	} catch (err) {
		console.error('[api/auth/check] server_error:', err);
		return json({ error: 'server_error', message: err?.message || 'unknown' }, { status: 500 });
	}
}
