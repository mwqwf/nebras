/**
 * POST /api/admin/internet-archive/cleanup-orphans
 *
 * يحذف من Firestore أيّ وثيقة محتوى لا تحوي sourceUrl / file_url / video_url
 * صالحاً — لأنّ التطبيق سيُظهر "No source available" عند الضغط عليها.
 *
 * يطبَّق على:
 *   • content_unified_files
 *   • dashboard_uploads
 *
 * body: { dryRun?: boolean }  (إن كان true: لا يحذف، يُرجع القائمة فقط)
 */
import { json } from '@sveltejs/kit';
import { getNebrasFirestoreAdmin, isAdminConfigured } from '$lib/server/firebaseAdmin.js';
import { adminFsDeleteFileMirrorBoth } from '$lib/server/nebrasUnifiedFirestoreAdmin.js';
import { requireAdminRole } from '$lib/server/adminApiAuth.js';

const URL_FIELDS = [
	'sourceUrl',
	'source_url',
	'file_url',
	'audio_url',
	'video_url',
	'downloadUrl',
	'youtube_url',
	'youtube_link',
	'youtube',
	'url',
	'link'
];

function pickUrl(doc) {
	for (const f of URL_FIELDS) {
		const v = doc?.[f];
		if (typeof v === 'string' && v.trim().length > 8) return v.trim();
	}
	// nested check (youtube_video.video_url / r2_file.file_url)
	const yv = doc?.youtube_video;
	if (yv && typeof yv === 'object') {
		const u = yv.video_url || yv.url || yv.link;
		if (typeof u === 'string' && u.trim().length > 8) return u.trim();
	}
	const r2 = doc?.r2_file;
	if (r2 && typeof r2 === 'object') {
		const u = r2.file_url || r2.url || r2.link;
		if (typeof u === 'string' && u.trim().length > 8) return u.trim();
	}
	// metadata fallback
	const meta = doc?.metadata;
	if (meta && typeof meta === 'object') {
		for (const f of URL_FIELDS) {
			const v = meta[f];
			if (typeof v === 'string' && v.trim().length > 8) return v.trim();
		}
	}
	return '';
}

/** @type {import('@sveltejs/kit').RequestHandler} */
export async function POST(event) {
	const gate = requireAdminRole(event);
	if (!gate.ok) return gate.response;
	if (!isAdminConfigured()) {
		return json({ error: 'not_configured' }, { status: 501 });
	}

	let body = {};
	try {
		body = await event.request.json();
	} catch {
		/* ignore — body optional */
	}
	const dryRun = Boolean(body?.dryRun);

	const fs = getNebrasFirestoreAdmin();

	const [filesSnap, uploadsSnap] = await Promise.all([
		fs.collection('content_unified_files').get(),
		fs.collection('dashboard_uploads').get()
	]);

	const orphanIds = new Set();
	const samples = [];

	function scan(snap, label) {
		for (const d of snap.docs) {
			const data = d.data() || {};
			const url = pickUrl(data);
			if (!url) {
				orphanIds.add(d.id);
				if (samples.length < 12) {
					samples.push({
						collection: label,
						id: d.id,
						title: data?.title || data?.metadata?.title || '',
						provider: data?.__provider || 'manual',
						licenseStatus: data?.__license_status || 'n/a'
					});
				}
			}
		}
	}

	scan(filesSnap, 'content_unified_files');
	scan(uploadsSnap, 'dashboard_uploads');

	if (dryRun) {
		return json({
			ok: true,
			dryRun: true,
			orphanCount: orphanIds.size,
			samples
		});
	}

	let deleted = 0;
	for (const id of orphanIds) {
		await adminFsDeleteFileMirrorBoth(id).catch(() => {});
		deleted += 1;
	}

	return json({
		ok: true,
		dryRun: false,
		orphanCount: orphanIds.size,
		deleted,
		samples
	});
}
