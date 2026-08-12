/**
 * /api/admin/reports — البلاغات متاحة لفريق الإدارة، والحذف النهائي للمالك.
 *
 * ╔══════════════════════════════════════════════════════════════════╗
 * ║  GET   → قائمة البلاغات المعلّقة (status == 'pending').            ║
 * ║  POST  → إجراء على بلاغ:                                          ║
 * ║           { action: 'delete',  reportId, contentId, contentType } ║
 * ║              يحذف المحتوى المخالف فعليّاً + يُعلّم البلاغ deleted.   ║
 * ║           { action: 'dismiss', reportId }                         ║
 * ║              يتجاهل بلاغاً كاذباً (status = dismissed).            ║
 * ║                                                                  ║
 * ║  الحذف يشمل المحتوى الرسمي أو UGC + ملفاته وتعليقاته وتفاعلاته.  ║
 * ╚══════════════════════════════════════════════════════════════════╝
 */
import { json } from '@sveltejs/kit';
import { requireAdminRole } from '$lib/server/adminApiAuth.js';
import { FieldValue } from 'firebase-admin/firestore';
import { getNebrasFirestoreAdmin, isAdminConfigured } from '$lib/server/firebaseAdmin.js';
import { deleteContentEverywhere } from '$lib/server/contentTakedown.js';

const REPORTS = 'content_reports';
// مجموعة الإخفاء العالميّ المؤقّت: يكتب فيها التطبيق فور بلاغ حقوق نشر،
// ويحذفها هذا الـ endpoint عند مراجعة المالك (delete أو dismiss).
const TAKEDOWN_PENDING = 'content_takedown_pending';

/** @type {import('@sveltejs/kit').RequestHandler} */
export async function GET(event) {
	const gate = requireAdminRole(event);
	if (!gate.ok) return gate.response;
	if (!isAdminConfigured()) return json({ error: 'not_configured' }, { status: 501 });

	const fs = getNebrasFirestoreAdmin();
	let snap;
	try {
		snap = await fs
			.collection(REPORTS)
			.where('status', '==', 'pending')
			.limit(300)
			.get();
	} catch {
		// fallback بدون فهرس/where إن لزم
		snap = await fs.collection(REPORTS).limit(300).get();
	}

	const items = snap.docs
		.map((d) => ({ id: d.id, ...(d.data() || {}) }))
		.filter((r) => (r.status || 'pending') === 'pending')
		.map((r) => ({
			id: r.id,
			contentId: String(r.contentId || ''),
			contentTitle: String(r.contentTitle || ''),
			contentType: String(r.contentType || ''),
			sourceUrl: String(r.sourceUrl || ''),
			reasonCode: String(r.reasonCode || 'other'),
			note: String(r.note || ''),
			reporterUid: String(r.reporterUid || ''),
			createdAtMs: toMs(r.createdAt)
		}))
		.sort((a, b) => b.createdAtMs - a.createdAtMs);

	return json({ ok: true, count: items.length, items });
}

/** @type {import('@sveltejs/kit').RequestHandler} */
export async function POST(event) {
	const gate = requireAdminRole(event);
	if (!gate.ok) return gate.response;
	if (!isAdminConfigured()) return json({ error: 'not_configured' }, { status: 501 });

	let body;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'invalid_body' }, { status: 400 });
	}

	const action = String(body?.action || '').trim();
	const reportId = String(body?.reportId || '').trim();
	if (!reportId) return json({ error: 'report_id_required' }, { status: 400 });

	const fs = getNebrasFirestoreAdmin();

	if (action === 'dismiss') {
		let contentId = String(body?.contentId || '').trim();
		// احتياط دفاعيّ: إن لم تُمرّر الواجهة المعرّف، نقرؤه من مستند البلاغ
		// نفسه كي نضمن حذف علامة الإخفاء حتّى مع نداء قديم لا يرسل contentId.
		if (!contentId) {
			try {
				const reportSnap = await fs.collection(REPORTS).doc(reportId).get();
				contentId = String(reportSnap.data()?.contentId || '').trim();
			} catch {
				/* تجاهل: نكمل التجاهل حتّى لو تعذّرت قراءة المعرّف. */
			}
		}
		await fs.collection(REPORTS).doc(reportId).set(
			{ status: 'dismissed', resolvedAt: FieldValue.serverTimestamp() },
			{ merge: true }
		);
		// إزالة علامة الإخفاء العالميّ ⇒ المحتوى يظهر للمستخدمين من جديد.
		// (نُحاول الحذف بصمت: المستند قد لا يكون موجوداً إن كان البلاغ
		// لغير حقوق نشر، أو كان مكرّراً قد عُولج قبلاً.)
		if (contentId) {
			await fs.collection(TAKEDOWN_PENDING).doc(contentId).delete().catch(() => {});
		}
		return json({ ok: true, action: 'dismiss', reportId });
	}

	if (action === 'delete') {
		// الحذف لا رجعة فيه (Firestore + Storage)، ولذلك يبقى حصراً للمالك
		// حتى مع إتاحة قراءة البلاغات وإغلاقها لكلّ المشرفين.
		if (gate.auth.role !== 'owner') {
			return json({ error: 'forbidden', reason: 'owner_required_for_delete' }, { status: 403 });
		}
		const contentId = String(body?.contentId || '').trim();
		const contentType = String(body?.contentType || '').trim().toLowerCase();
		if (!contentId) return json({ error: 'content_id_required' }, { status: 400 });

		// 1) حذف المحتوى المخالف من كلّ المواضع (Firestore + Storage).
		await deleteContentEverywhere(contentId, contentType);

		// 2) تعليم البلاغ "محذوف".
		await fs.collection(REPORTS).doc(reportId).set(
			{ status: 'deleted', resolvedAt: FieldValue.serverTimestamp() },
			{ merge: true }
		);

		// 3) إزالة علامة الإخفاء العالميّ — لم تَعُد لازمة لأنّ المحتوى نفسه
		//    حُذف من كلّ المواضع.
		await fs.collection(TAKEDOWN_PENDING).doc(contentId).delete().catch(() => {});

		return json({ ok: true, action: 'delete', reportId, contentId });
	}

	return json({ error: 'unknown_action' }, { status: 400 });
}

function toMs(v) {
	if (!v) return 0;
	if (typeof v === 'number') return v;
	if (typeof v?.toMillis === 'function') return v.toMillis();
	if (typeof v?._seconds === 'number') return v._seconds * 1000;
	const t = Date.parse(String(v));
	return Number.isFinite(t) ? t : 0;
}
