/**
 * /api/admin/content-audit — يراه فريق الإدارة، والحذف النهائي للمالك فقط.
 *
 * تفحص المحتوى الحاليّ وتُبرز **ما يحمل إشارات خطر حقيقيّة** ليراجعه
 * المالك ويحذف المخالف:
 *
 *   • terrorism   : أسماء إصدارات/تنظيمات متطرّفة (النبأ/دابق/داعش…).
 *   • copyright   : علامات تجاريّة/منصّات محميّة (YouTube/Netflix/MBC…)
 *                   أو إشارات حقوق صريحة.
 *   • sexual      : ألفاظ جنسيّة صريحة.
 *   • archive_link: رابط مصدره archive.org (يجب ألّا يُخدَم).
 *
 * لا نُعلّم المحتوى لمجرّد كونه رفعاً يدويّاً — الرفع اليدويّ مُراجَع أصلاً.
 *
 * GET  → قائمة العناصر المُعلَّمة (مع الفئات والكلمات المُطابِقة).
 * POST → { action: 'delete', contentId, contentType } يحذف العنصر فعليّاً.
 */
import { json } from '@sveltejs/kit';
import { requireAdminRole } from '$lib/server/adminApiAuth.js';
import { getNebrasFirestoreAdmin, isAdminConfigured } from '$lib/server/firebaseAdmin.js';
import { deleteContentEverywhere } from '$lib/server/contentTakedown.js';
import { scanRisk, DESCRIPTION_SAFE_PATTERNS } from '$lib/server/contentRiskLexicon.js';

const DESC_SAFE = new Set(DESCRIPTION_SAFE_PATTERNS.map((s) => s.trim()));
import { NEBRAS_FS_CONTENT_FILES } from '$lib/firebase/nebrasUnifiedPaths.js';

const SCAN_LIMIT = 1500;
const RETURN_LIMIT = 500;

/** @type {import('@sveltejs/kit').RequestHandler} */
export async function GET(event) {
	const gate = requireAdminRole(event);
	if (!gate.ok) return gate.response;
	if (!isAdminConfigured()) return json({ error: 'not_configured' }, { status: 501 });

	const fs = getNebrasFirestoreAdmin();
	const filesSnap = await fs.collection(NEBRAS_FS_CONTENT_FILES).limit(SCAN_LIMIT).get();

	const flagged = [];
	let scanned = 0;

	const consider = (id, data) => {
		scanned += 1;
		const { flags, matched } = computeFlags(data);
		if (flags.length === 0) return;
		flagged.push({
			contentId: String(data?.id || data?.fileId || id || ''),
			title: String(data?.title || data?.name || ''),
			contentType: String(data?.content_type || 'file'),
			sourceUrl: pickUrl(data),
			provider: String(data?.__provider || ''),
			flags,
			matched
		});
	};

	for (const d of filesSnap.docs) consider(d.id, d.data() || {});

	flagged.sort((a, b) => b.flags.length - a.flags.length);

	return json({
		ok: true,
		scanned,
		flaggedCount: flagged.length,
		items: flagged.slice(0, RETURN_LIMIT)
	});
}

/** @type {import('@sveltejs/kit').RequestHandler} */
export async function POST(event) {
	const gate = requireAdminRole(event);
	if (!gate.ok) return gate.response;
	if (gate.auth.role !== 'owner') {
		return json({ error: 'forbidden', reason: 'owner_required_for_delete' }, { status: 403 });
	}
	if (!isAdminConfigured()) return json({ error: 'not_configured' }, { status: 501 });

	let body;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'invalid_body' }, { status: 400 });
	}

	if (String(body?.action || '') !== 'delete') {
		return json({ error: 'unknown_action' }, { status: 400 });
	}
	const contentId = String(body?.contentId || '').trim();
	const contentType = String(body?.contentType || '').trim();
	if (!contentId) return json({ error: 'content_id_required' }, { status: 400 });

	await deleteContentEverywhere(contentId, contentType);
	return json({ ok: true, action: 'delete', contentId });
}

function pickUrl(data) {
	return String(
		data?.video_url ||
			data?.file_url ||
			data?.audio_url ||
			data?.sourceUrl ||
			data?.source_url ||
			data?.downloadUrl ||
			data?.url ||
			''
	);
}

/** منصّات محميّة بحقوق — إن كان مضيف رابط المصدر منها فالمحتوى مأخوذ منها. */
const COPYRIGHT_HOSTS = [
	'youtube.com',
	'youtu.be',
	'netflix.com',
	'disneyplus.com',
	'shahid.mbc.net',
	'hbomax.com',
	'primevideo.com'
];

function stripHtml(s) {
	return String(s || '').replace(/<[^>]*>/g, ' ');
}

function hostOf(url) {
	try {
		return new URL(String(url)).hostname.toLowerCase().replace(/^www\./, '');
	} catch {
		return '';
	}
}

/**
 * يحسب أعلام الخطر بدقّة عالية:
 *   • إرهاب/جنس: نفحص العنوان + الوصف (بعد تجريد HTML) + القسم — لأنّ
 *     الموضوع قد يُذكر في الوصف.
 *   • حقوق/علامات تجاريّة: نفحص **العنوان فقط** (لا الوصف — فالوصف يذكر
 *     روابط/منصّات بريئة كثيرة، وهذا سبب الإيجابيات الكاذبة)، بالإضافة
 *     إلى **مضيف رابط المصدر** إن كان منصّة محميّة.
 */
function computeFlags(data) {
	const title = String(data?.title || data?.name || '');
	const section = [data?.section_name, data?.subsection_name].filter(Boolean).join(' ');
	const desc = stripHtml(String(data?.description || ''));
	const author = String(data?.author || data?.created_by || '');

	const flagsSet = new Set();
	const matched = [];

	// إرهاب + جنس: من **العنوان** (+ القسم + المؤلّف) — الإشارة القويّة
	// المقصودة. لا نفحص الوصف لأسماء التنظيمات العامّة (داعش/القاعدة) لأنّها
	// تُذكر كثيراً في النقاش والذمّ والأخبار، فتُنتج إيجابيّات كاذبة.
	const titleScope = [title, section, author].filter(Boolean).join(' \n ');
	for (const r of scanRisk(titleScope)) {
		if (r.category === 'terrorism' || r.category === 'sexual') {
			flagsSet.add(r.category);
			matched.push(...r.terms);
		}
	}

	// الوصف: فقط أسماء الإصدارات المتطرّفة شديدة التحديد (مجلة دابق/صحيفة
	// النبأ…) التي لا تظهر إلّا في المادّة نفسها — لا أسماء التنظيمات العامّة.
	for (const r of scanRisk(desc)) {
		if (r.category !== 'terrorism') continue;
		const safe = r.terms.filter((t) => DESC_SAFE.has(t));
		if (safe.length) {
			flagsSet.add('terrorism');
			matched.push(...safe);
		}
	}

	// حقوق/علامات تجاريّة — العنوان فقط + مضيف الرابط.
	{
		const copyrightScope = [title, section].filter(Boolean).join(' \n ');
		for (const r of scanRisk(copyrightScope)) {
			if (r.category === 'copyright') {
				flagsSet.add('copyright');
				matched.push(...r.terms);
			}
		}
		const host = hostOf(pickUrl(data));
		const matchedHost = COPYRIGHT_HOSTS.find((h) => host === h || host.endsWith('.' + h));
		if (matchedHost) {
			flagsSet.add('copyright');
			matched.push(matchedHost);
		}
	}

	const url = pickUrl(data).toLowerCase();
	if (url.includes('archive.org')) flagsSet.add('archive_link');

	return { flags: [...flagsSet], matched: [...new Set(matched)] };
}
