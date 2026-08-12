/**
 * أدوار لوحة التحكّم — مصدر واحد للتطبيع بين /api/auth/check و hooks.server.js
 * ومسارات /api/admin/*.
 */
import { isOwnerEmail } from '$lib/server/mailer.js';

/**
 * @param {string} email
 * @param {{ role?: string } | null | undefined} record
 * @returns {'owner'|'supervisor'}
 */
export function normalizeDashboardRole(email, record) {
	if (isOwnerEmail(email)) return 'owner';
	const r = record?.role;
	if (r === 'owner') return 'owner';
	// قيم قديمة أو غير متوقّعة → supervisor (صلاحيات المشرف الكاملة في اللوحة)
	if (r === 'admin' || r === 'moderator' || r === 'supervisor') return 'supervisor';
	return 'supervisor';
}

/**
 * @param {string | null | undefined} role
 * @returns {boolean}
 */
export function isAdminPanelRole(role) {
	return role === 'owner' || role === 'supervisor';
}
