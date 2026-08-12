/**
 * بوت دردشة الإدارة — يكتب «رسائل نظام» في `admin_chat_messages` عبر
 * Admin SDK (يتجاوز قواعد العميل عمداً: senderId ثابت 'system').
 *
 * يُستعمل من كرونين:
 *   • /api/cron/admin-daily-digest  — الموجز اليومي 📊 (+ جسر الاقتراحات كاحتياط).
 *   • /api/cron/suggestions-bridge  — جسر اقتراحات التصحيح ✏️ (كل ربع ساعة عبر
 *     GitHub Action، لأنّ Vercel Hobby لا يسمح بأكثر من كرونَين يوميّين).
 *
 * تطبيق اللوحة يعرض رسائل senderId=='system' كبطاقة معلوماتيّة وسطيّة.
 */

import { FieldValue } from 'firebase-admin/firestore';
import { getNebrasFirestoreAdmin, sendTopicMessage } from './firebaseAdmin.js';

const ADMIN_CHAT_TOPIC = 'nebras_admin_chat';

/** كتابة رسالة نظام في دردشة الإدارة (نفس شكل وثيقة رسائل العميل). */
export async function postSystemMessage(text) {
	const fs = getNebrasFirestoreAdmin();
	await fs.collection('admin_chat_messages').add({
		senderId: 'system',
		senderName: 'نبراس',
		senderPhoto: '',
		type: 'text',
		text: String(text || '').slice(0, 4000),
		att: null,
		replyTo: null,
		sentAtMs: Date.now(),
		createdAt: FieldValue.serverTimestamp(),
		deleted: false,
		deletedBy: '',
		hiddenFor: [],
		reactions: {}
	});
}

/** إشعار FCM لأعضاء دردشة الإدارة (data-only — التطبيق يبني الإشعار). */
export async function notifyAdmins(title, body) {
	try {
		await sendTopicMessage({
			topic: ADMIN_CHAT_TOPIC,
			title,
			body,
			data: { kind: 'admin_chat', senderId: 'system' }
		});
	} catch (err) {
		// الإشعار كماليّ — لا يُفشل الكرون.
		console.warn('[adminChatBot] notify failed:', err?.message || err);
	}
}

/**
 * جسر اقتراحات التصحيح: كلّ وثيقة `content_suggestions` بحالة pending ولم
 * تُجسَّر بعد → رسالة نظام في الدردشة + وسم bridged (idempotent).
 * @returns {Promise<number>} عدد الاقتراحات المُجسَّرة.
 */
export async function bridgePendingSuggestions() {
	const fs = getNebrasFirestoreAdmin();
	const snap = await fs
		.collection('content_suggestions')
		.where('status', '==', 'pending')
		.limit(25)
		.get();
	const fresh = snap.docs.filter((d) => d.data().bridged !== true);
	for (const doc of fresh) {
		const v = doc.data();
		const note = String(v.note || '').slice(0, 600);
		const text =
			'✏️ اقتراح تصحيح جديد من مستخدم التطبيق\n' +
			`النوع: ${v.contentType || 'غير محدّد'} — المعرّف: ${v.contentId || '؟'}\n` +
			`«${note}»`;
		await postSystemMessage(text);
		await doc.ref.update({
			bridged: true,
			bridgedAt: FieldValue.serverTimestamp()
		});
	}
	if (fresh.length > 0) {
		await notifyAdmins(
			'اقتراحات تصحيح جديدة ✏️',
			fresh.length === 1
				? 'وصل اقتراح تصحيح جديد من مستخدم — افتح دردشة الإدارة.'
				: `وصلت ${fresh.length} اقتراحات تصحيح جديدة — افتح دردشة الإدارة.`
		);
	}
	return fresh.length;
}

/** تحويل قيمة createdAt بأشكالها المتعدّدة (Timestamp/نص/رقم) إلى ms أو null. */
function toMs(v) {
	if (!v) return null;
	if (typeof v.toDate === 'function') return v.toDate().getTime();
	if (typeof v === 'number') return v > 1e12 ? v : v * 1000;
	if (typeof v === 'string') {
		const t = Date.parse(v);
		return Number.isNaN(t) ? null : t;
	}
	return null;
}

/**
 * الموجز اليومي 📊: إحصاءات الأمس (محتوى جديد، بلاغات واقتراحات معلّقة،
 * عدد الأعضاء) → رسالة نظام + إشعار.
 * @returns {Promise<object>} ملخّص الأرقام.
 */
export async function postDailyDigest() {
	const fs = getNebrasFirestoreAdmin();
	const now = new Date();
	const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
	const yesterdayStart = todayStart - 24 * 60 * 60 * 1000;

	// محتوى الأمس: نقرأ أحدث دفعة ونرشّح محليّاً (createdAt بأشكال مختلطة
	// تاريخيّاً، فالاستعلام المباشر على المدى غير موثوق).
	let newContent = 0;
	try {
		const recent = await fs
			.collection('content_unified_files')
			.orderBy('createdAt', 'desc')
			.limit(300)
			.get();
		for (const d of recent.docs) {
			const ms = toMs(d.data().createdAt);
			if (ms !== null && ms >= yesterdayStart && ms < todayStart) newContent++;
		}
	} catch (err) {
		console.warn('[adminChatBot] content count failed:', err?.message || err);
	}

	let newCommunityPosts = 0;
	try {
		const recentCommunity = await fs
			.collection('ugc_contents')
			.orderBy('created_at', 'desc')
			.limit(300)
			.get();
		for (const d of recentCommunity.docs) {
			const ms = toMs(d.data().created_at);
			if (ms !== null && ms >= yesterdayStart && ms < todayStart) newCommunityPosts++;
		}
	} catch (err) {
		console.warn('[adminChatBot] community count failed:', err?.message || err);
	}

	async function countPending(coll) {
		try {
			const agg = await fs
				.collection(coll)
				.where('status', '==', 'pending')
				.count()
				.get();
			return agg.data().count || 0;
		} catch {
			return 0;
		}
	}
	const pendingReports = await countPending('content_reports');
	const pendingSuggestions = await countPending('content_suggestions');

	let membersCount = 0;
	try {
		const agg = await fs.collection('admin_chat_members').count().get();
		membersCount = agg.data().count || 0;
	} catch {
		/* كماليّ */
	}

	const lines = [
		'📊 الموجز اليومي — صباح الخير يا فريق نبراس!',
		`• محتوى جديد أمس: ${newContent}`,
		`• منشورات مجتمع جديدة أمس: ${newCommunityPosts}`,
		`• بلاغات بانتظار المراجعة: ${pendingReports}`,
		`• اقتراحات تصحيح معلّقة: ${pendingSuggestions}`,
		`• أعضاء المجموعة: ${membersCount}`,
		newContent + newCommunityPosts > 0
			? 'أحسنتم — استمرّوا! 👏'
			: 'لنجعل اليوم أكثر نشاطاً 💪'
	];
	await postSystemMessage(lines.join('\n'));
	await notifyAdmins(
		'الموجز اليومي 📊',
		`محتوى جديد: ${newContent} • مجتمع: ${newCommunityPosts} • بلاغات: ${pendingReports}`
	);

	return { newContent, newCommunityPosts, pendingReports, pendingSuggestions, membersCount };
}
