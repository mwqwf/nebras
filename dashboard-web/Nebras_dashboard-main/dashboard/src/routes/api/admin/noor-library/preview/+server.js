/**
 * POST /api/admin/noor-library/preview
 *
 * يجلب metadata كتاب من مكتبة نور **دون رفعه**. يصنّفه محلّياً (مطابقة
 * نصّيّة عربيّة على شجرة الأقسام الحاليّة) ويُعيد:
 *   { metadata, classification, validation, tree }
 *
 * الواجهة تعرض التصنيف المقترح، ويستطيع المستخدم تعديله أو اعتماده ثمّ
 * إرسال الطلب إلى /api/admin/noor-library/import.
 *
 * Body:
 *   { url: string }    رابط صفحة كتاب على noor-book.com
 */

import { json } from '@sveltejs/kit';
import { buildSectionsTree } from '$lib/server/noorLibrary/sectionsTree.js';
import { fetchBookMetadata } from '$lib/server/noorLibrary/fetcher.js';
import { classifyBookIntoHierarchy } from '$lib/server/noorLibrary/classifier.js';

/** @type {import('@sveltejs/kit').RequestHandler} */
export async function POST(event) {
	const auth = event.locals?.auth;
	if (!auth) return json({ error: 'unauthenticated' }, { status: 401 });
	if (auth.role !== 'owner' && auth.role !== 'supervisor') {
		return json({ error: 'forbidden', reason: 'role_not_allowed' }, { status: 403 });
	}

	let body;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'bad_request', reason: 'invalid_json' }, { status: 400 });
	}

	const url = String(body?.url || '').trim();
	if (!url) {
		return json({ error: 'bad_request', reason: 'url_required' }, { status: 400 });
	}

	let metadata;
	try {
		metadata = await fetchBookMetadata(url);
	} catch (err) {
		return json(
			{
				error: 'fetch_failed',
				reason: err?.reason || 'fetch_failed',
				message: err?.message || String(err)
			},
			{ status: err?.status || 502 }
		);
	}

	let sections;
	try {
		sections = await buildSectionsTree();
	} catch (err) {
		return json(
			{ error: 'sections_read_failed', message: err?.message || String(err) },
			{ status: 500 }
		);
	}

	let classification;
	try {
		classification = await classifyBookIntoHierarchy(sections, metadata);
	} catch (err) {
		// لا نُسقط الـ preview بسبب فشل التصنيف — نعيد metadata + شجرة الأقسام
		// للمستخدم ليختار يدوياً.
		return json({
			ok: true,
			metadata,
			classification: null,
			classificationError: {
				reason: err?.reason || 'classifier_failed',
				message: err?.message || String(err),
				status: err?.status || 502
			},
			tree: sections.tree
		});
	}

	return json({
		ok: true,
		metadata,
		classification,
		tree: sections.tree
	});
}
