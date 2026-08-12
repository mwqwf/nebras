/**
 * /api/admin/community
 *
 * واجهة الإشراف على «مجتمع نبراس» لتطبيق لوحة Flutter. لا تعتمد على واجهة
 * الويب: تعيد القنوات، والمنشورات التي عليها بلاغات معلّقة، وتنفّذ إجراءات
 * التعليق/فكّه. الحذف النهائي محصور بالمالك، ولا يوجد مسار لتحويل محتوى المجتمع إلى محتوى رسمي.
 */
import { json } from '@sveltejs/kit';
import { FieldValue } from 'firebase-admin/firestore';
import { requireAdminRole } from '$lib/server/adminApiAuth.js';
import { getNebrasFirestoreAdmin, isAdminConfigured } from '$lib/server/firebaseAdmin.js';
import { deleteContentEverywhere } from '$lib/server/contentTakedown.js';

const CHANNELS = 'ugc_channels';
const POSTS = 'ugc_contents';
const REPORTS = 'content_reports';

/** @type {import('@sveltejs/kit').RequestHandler} */
export async function GET(event) {
	const gate = requireAdminRole(event);
	if (!gate.ok) return gate.response;
	if (!isAdminConfigured()) return json({ error: 'not_configured' }, { status: 501 });

	const fs = getNebrasFirestoreAdmin();
	const [channelsSnap, postsSnap, reportsSnap] = await Promise.all([
		fs.collection(CHANNELS).limit(1000).get(),
		fs.collection(POSTS).orderBy('created_at', 'desc').limit(1500).get(),
		pendingReports(fs)
	]);

	const postsById = new Map();
	const postCountByChannel = new Map();
	for (const doc of postsSnap.docs) {
		const post = normalizePost(doc.id, doc.data() || {});
		postsById.set(post.id, post);
		postCountByChannel.set(post.channelId, (postCountByChannel.get(post.channelId) || 0) + 1);
	}

	const reportedPosts = [];
	for (const doc of reportsSnap.docs) {
		const report = normalizeReport(doc.id, doc.data() || {});
		if (text(doc.data()?.status) && text(doc.data()?.status) !== 'pending') continue;
		if (!report.contentId.startsWith('ugc_') && report.contentType !== 'ugc') continue;
		const post = postsById.get(report.contentId);
		reportedPosts.push({
			report,
			post: post || {
				id: report.contentId,
				title: report.contentTitle,
				channelId: '',
				channelName: '',
				channelStatus: 'unknown',
				contentType: report.contentType || 'ugc',
				sourceUrl: report.sourceUrl,
				createdAtMs: 0
			}
		});
	}

	const channels = channelsSnap.docs
		.map((doc) => {
			const d = doc.data() || {};
			return {
				id: doc.id,
				name: text(d.name),
				bio: text(d.bio),
				photoUrl: text(d.photoUrl),
				status: text(d.status) || 'active',
				createdAtMs: toMs(d.createdAt),
				updatedAtMs: toMs(d.updatedAt),
				postCount: postCountByChannel.get(doc.id) || 0,
				pendingReports: 0
			};
		})
		.map((channel) => ({
			...channel,
			pendingReports: reportedPosts.filter((entry) => entry.post.channelId === channel.id).length
		}))
		.sort((a, b) => {
			if (a.status !== b.status) return a.status === 'suspended' ? -1 : 1;
			return b.updatedAtMs - a.updatedAtMs;
		});

	reportedPosts.sort((a, b) => b.report.createdAtMs - a.report.createdAtMs);
	return json({
		ok: true,
		canDelete: gate.auth.role === 'owner',
		channels,
		reportedPosts,
		counts: {
			channels: channels.length,
			suspended: channels.filter((c) => c.status === 'suspended').length,
			pendingReports: reportedPosts.length
		}
	});
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

	const action = text(body?.action);
	const fs = getNebrasFirestoreAdmin();
	if (action === 'suspend_channel' || action === 'unsuspend_channel') {
		const channelId = text(body?.channelId);
		if (!channelId) return json({ error: 'channel_id_required' }, { status: 400 });
		const status = action === 'suspend_channel' ? 'suspended' : 'active';
		const ref = fs.collection(CHANNELS).doc(channelId);
		const channel = await ref.get();
		if (!channel.exists) return json({ error: 'channel_not_found' }, { status: 404 });
		await ref.set(
			{
				status,
				moderatedAt: FieldValue.serverTimestamp(),
				moderatedBy: gate.auth.uid
			},
			{ merge: true }
		);
		// منشورات المجتمع لا تنضمّ إلى القناة عند العرض، لذلك نحفظ حالتها على
		// كل منشور أيضاً. بهذه الطريقة يختفي التعليق فوراً من كل الأجهزة.
		await setPostsChannelStatus(fs, channelId, status);
		return json({ ok: true, action, channelId, status });
	}

	if (action === 'delete_post') {
		if (gate.auth.role !== 'owner') {
			return json({ error: 'forbidden', reason: 'owner_required' }, { status: 403 });
		}
		const postId = text(body?.postId);
		if (!postId) return json({ error: 'post_id_required' }, { status: 400 });
		const postSnap = await fs.collection(POSTS).doc(postId).get();
		if (!postSnap.exists) return json({ error: 'post_not_found' }, { status: 404 });
		await deleteContentEverywhere(postId, 'ugc');
		return json({ ok: true, action, postId });
	}

	return json({ error: 'unknown_action' }, { status: 400 });
}

async function pendingReports(fs) {
	try {
		return await fs.collection(REPORTS).where('status', '==', 'pending').limit(500).get();
	} catch {
		return fs.collection(REPORTS).limit(500).get();
	}
}

async function setPostsChannelStatus(fs, channelId, status) {
	const snap = await fs.collection(POSTS).where('channelId', '==', channelId).get();
	for (let i = 0; i < snap.docs.length; i += 400) {
		const batch = fs.batch();
		for (const doc of snap.docs.slice(i, i + 400)) {
			batch.update(doc.ref, {
				channelStatus: status,
				updated_at: FieldValue.serverTimestamp()
			});
		}
		await batch.commit();
	}
}

function normalizePost(id, d) {
	return {
		id,
		title: text(d.title),
		description: text(d.description),
		channelId: text(d.channelId),
		channelName: text(d.channelName),
		channelStatus: text(d.channelStatus) || 'active',
		contentType: text(d.content_type),
		sourceUrl: text(d.source_url),
		createdAtMs: toMs(d.created_at)
	};
}

function normalizeReport(id, d) {
	return {
		id,
		contentId: text(d.contentId),
		contentTitle: text(d.contentTitle),
		contentType: text(d.contentType).toLowerCase(),
		reasonCode: text(d.reasonCode) || 'other',
		note: text(d.note),
		sourceUrl: text(d.sourceUrl),
		createdAtMs: toMs(d.createdAt)
	};
}

function text(value) {
	return String(value || '').trim();
}

function toMs(value) {
	if (!value) return 0;
	if (typeof value === 'number') return value;
	if (typeof value?.toMillis === 'function') return value.toMillis();
	if (typeof value?._seconds === 'number') return value._seconds * 1000;
	const parsed = Date.parse(String(value));
	return Number.isFinite(parsed) ? parsed : 0;
}
