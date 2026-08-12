/**
 * auditLog.js — سجلّ موحَّد لكلّ عمليّات نشر/تعديل/حذف المحتوى عبر اللوحة.
 *
 * الغرض:
 *   • ردّ شكاوى DMCA: نُثبت متى وكيف نُشر العنصر ومن مصدر مرخّص.
 *   • تتبّع إساءة الاستخدام من حساب مشرف مُختَرَق.
 *   • تدقيق داخليّ لمعرفة مَن نشر ماذا متى.
 *
 * يُكتب في مجموعة Firestore `nebras_audit_log` (Admin SDK فقط — لا يقرأها
 * أيّ عميل، ولا تنطبق عليها قواعد Firestore لأنّ الكتابة من الخادم).
 *
 * الاستخدام:
 *   import { writeAuditEntry } from '$lib/server/auditLog.js';
 *   await writeAuditEntry({
 *     action: 'import',          // import | manual_upload | delete | dmca_takedown | dismiss
 *     provider: 'hindawi',       // hindawi | internet_archive | manual | noor_library
 *     contentId: 'hindawi_123',
 *     licenseStatus: 'verified_open_license',
 *     licenseName: 'CC BY-SA 4.0',
 *     sourceUrl: '...',
 *     actorUid: '...',           // اختياري (المالك/المشرف)
 *     meta: { ... }              // أيّ حقول إضافيّة
 *   });
 *
 * أيّ خطأ في الكتابة لا يجب أن يُعطّل العمليّة الأصليّة — السجلّ best-effort.
 */

import { FieldValue } from 'firebase-admin/firestore';
import { getNebrasFirestoreAdmin, isAdminConfigured } from '$lib/server/firebaseAdmin.js';

const COLLECTION = 'nebras_audit_log';
const MAX_META_KEYS = 30;
const MAX_STRING_LEN = 2000;

function truncate(value) {
	if (value == null) return null;
	if (typeof value === 'string') return value.slice(0, MAX_STRING_LEN);
	return value;
}

function sanitizeMeta(meta) {
	if (!meta || typeof meta !== 'object') return null;
	const out = {};
	let count = 0;
	for (const [k, v] of Object.entries(meta)) {
		if (count >= MAX_META_KEYS) break;
		out[k] = truncate(v);
		count += 1;
	}
	return out;
}

/**
 * @param {{
 *   action: string,
 *   provider?: string,
 *   contentId?: string,
 *   contentType?: string,
 *   licenseStatus?: string,
 *   licenseName?: string,
 *   licenseUrl?: string,
 *   sourceUrl?: string,
 *   actorUid?: string,
 *   actorEmail?: string,
 *   result?: string,
 *   reason?: string,
 *   meta?: Record<string, any>
 * }} entry
 */
export async function writeAuditEntry(entry) {
	if (!isAdminConfigured()) return;
	const e = entry || {};
	const action = String(e.action || '').trim();
	if (!action) return;
	try {
		await getNebrasFirestoreAdmin()
			.collection(COLLECTION)
			.add({
				action,
				provider: truncate(e.provider || 'unknown'),
				contentId: truncate(e.contentId || ''),
				contentType: truncate(e.contentType || ''),
				licenseStatus: truncate(e.licenseStatus || ''),
				licenseName: truncate(e.licenseName || ''),
				licenseUrl: truncate(e.licenseUrl || ''),
				sourceUrl: truncate(e.sourceUrl || ''),
				actorUid: truncate(e.actorUid || ''),
				actorEmail: truncate(e.actorEmail || ''),
				result: truncate(e.result || 'ok'),
				reason: truncate(e.reason || ''),
				meta: sanitizeMeta(e.meta),
				createdAt: FieldValue.serverTimestamp()
			});
	} catch (err) {
		// لا نُفشل العمليّة الأصليّة لمجرّد فشل audit — نسجّل تحذيراً فقط.
		console.warn('[audit] write failed:', err?.message || String(err));
	}
}
