/**
 * GET /api/admin/aggregates/overview
 *
 * إحصائيات عامة **حقيقية** محسوبة من Firestore مباشرة (بديل عن backend
 * Django القديم المعطّل). تعكس ما يراه المستخدم فعلاً في التطبيق:
 *   - الأقسام: رئيسي / فرعي / ثانوي.
 *   - المحتوى: إجمالي + توزيع حسب النوع (كتاب/صوت/فيديو/يوتيوب).
 *   - أعلى الأقسام الرئيسيّة بعدد العناصر.
 *   - حصّة محتوى الأرشيف (__provider='internet_archive').
 */
import { json } from '@sveltejs/kit';
import { getNebrasFirestoreAdmin, isAdminConfigured } from '$lib/server/firebaseAdmin.js';
import {
	NEBRAS_FS_SECTIONS,
	NEBRAS_FS_CONTENT_FILES
} from '$lib/firebase/nebrasUnifiedPaths.js';
import { requireAdminRole } from '$lib/server/adminApiAuth.js';

function pickType(d) {
	return String(d?.content_type || d?.metadata?.content_type || 'document')
		.trim()
		.toLowerCase();
}

/** @type {import('@sveltejs/kit').RequestHandler} */
export async function GET(event) {
	const gate = requireAdminRole(event);
	if (!gate.ok) return gate.response;
	if (!isAdminConfigured()) {
		return json({ error: 'not_configured' }, { status: 501 });
	}

	const fs = getNebrasFirestoreAdmin();
	const [mainDoc, subDoc, secDoc, filesSnap] = await Promise.all([
		fs.collection(NEBRAS_FS_SECTIONS).doc('main').get(),
		fs.collection(NEBRAS_FS_SECTIONS).doc('sub').get(),
		fs.collection(NEBRAS_FS_SECTIONS).doc('secondary').get(),
		fs.collection(NEBRAS_FS_CONTENT_FILES).get()
	]);

	const mains = mainDoc.exists ? mainDoc.data() || {} : {};
	const subs = subDoc.exists ? subDoc.data() || {} : {};
	const secs = secDoc.exists ? secDoc.data() || {} : {};

	const mainNameById = {};
	for (const [id, v] of Object.entries(mains)) mainNameById[String(id)] = String(v?.name || id);
	const subToMain = {};
	for (const [id, v] of Object.entries(subs)) subToMain[String(id)] = String(v?.main_section ?? '');

	// ميزة يوتيوب أُزيلت — نُبقي المفتاح youtube=0 لتوافق الواجهات القديمة.
	const byType = { document: 0, audio: 0, video: 0, youtube: 0 };
	const contentByMain = {};
	let iaCount = 0;

	for (const doc of filesSnap.docs) {
		const d = doc.data() || {};
		const t = pickType(d);
		if (byType[t] !== undefined) byType[t] += 1;
		else byType.document += 1; // نوع غير متوقّع → احسبه ضمن الوثائق
		if (d.__provider === 'internet_archive') iaCount += 1;
		const subId = String(d.subsection ?? d.metadata?.subsection ?? '');
		const mainId = subToMain[subId] || String(d.main_section ?? d.metadata?.main_section ?? '');
		if (mainId) contentByMain[mainId] = (contentByMain[mainId] || 0) + 1;
	}

	const totalContent = filesSnap.size;
	const topSections = Object.entries(contentByMain)
		.map(([id, count]) => ({ id, name: mainNameById[id] || id, content_count: count }))
		.sort((a, b) => b.content_count - a.content_count)
		.slice(0, 8);

	return json({
		ok: true,
		sections: {
			main: Object.keys(mains).length,
			sub: Object.keys(subs).length,
			secondary: Object.keys(secs).length,
			total: Object.keys(mains).length + Object.keys(subs).length + Object.keys(secs).length
		},
		content: {
			total: totalContent,
			files: filesSnap.size,
			youtube: 0,
			fromInternetArchive: iaCount
		},
		byType,
		topSections
	});
}
