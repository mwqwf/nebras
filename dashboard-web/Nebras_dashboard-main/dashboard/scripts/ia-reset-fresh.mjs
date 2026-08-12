#!/usr/bin/env node
/**
 * ia-reset-fresh.mjs — مسح كامل لمحتوى محرّك Internet Archive ثمّ بداية من
 * الصفر. يطابق منطق engine.factoryReset() لكنّه يمسح أيضاً عقدة المحرّك
 * كاملةً (config) حتى يُعيد autoBootIfNeeded إنشاء DEFAULT_CONFIG نظيفاً.
 *
 * يحذف فقط ما يخصّ IA:
 *   - وثائق content_unified_files + dashboard_uploads بعلامة
 *     __provider==='internet_archive'
 *   - أقسام sections_unified بعلامة __createdBy==='ia_library_engine'
 *     (وأبناؤها)
 *   - RTDB: ia_library_engine (config+cursor+stats+log) + ia_library_registry
 *     + ia_library_failures
 *
 * لا يلمس المحتوى اليدويّ ولا الأقسام البشريّة. تشغيل لمرّة واحدة.
 */
import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { getDatabase } from 'firebase-admin/database';
import { resolveServiceAccount } from './load-admin-credential.mjs';

const { credentials } = resolveServiceAccount();
const dbUrl = process.env.FIREBASE_DATABASE_URL || process.env.NEBRAS_DATABASE_URL;
const app = initializeApp({
	credential: cert(credentials),
	projectId: credentials.project_id,
	databaseURL: dbUrl
});
const fs = getFirestore(app, process.env.NEBRAS_FIRESTORE_DATABASE_ID || 'default');
const rtdb = getDatabase(app);

const cleared = { uploads: 0, content_files: 0, mains: 0, subs: 0, secondaries: 0 };

const [uploadsSnap, contentFilesSnap, mainSnap, subSnap, secSnap] = await Promise.all([
	fs.collection('dashboard_uploads').get(),
	fs.collection('content_unified_files').get(),
	fs.collection('sections_unified').doc('main').get(),
	fs.collection('sections_unified').doc('sub').get(),
	fs.collection('sections_unified').doc('secondary').get()
]);

// 1) ملفّات IA — نحدّدها بـ __provider
const fileIdsToDelete = new Set();
for (const d of uploadsSnap.docs) {
	if (d.data()?.__provider === 'internet_archive') {
		fileIdsToDelete.add(d.id);
		cleared.uploads += 1;
	}
}
for (const d of contentFilesSnap.docs) {
	if (d.data()?.__provider === 'internet_archive') {
		fileIdsToDelete.add(d.id);
		cleared.content_files += 1;
	}
}

// 2) أقسام المحرّك — نحدّدها بـ __createdBy (+ الأبناء)
const iaMainIds = new Set();
const iaSubIds = new Set();
const iaSecIds = new Set();
const mains = mainSnap.exists ? mainSnap.data() || {} : {};
const subs = subSnap.exists ? subSnap.data() || {} : {};
const secs = secSnap.exists ? secSnap.data() || {} : {};
for (const [id, val] of Object.entries(mains)) {
	if (val?.__createdBy === 'ia_library_engine') {
		iaMainIds.add(String(id));
		cleared.mains += 1;
	}
}
for (const [id, val] of Object.entries(subs)) {
	const parent = String(val?.main_section ?? '');
	if (val?.__createdBy === 'ia_library_engine' || iaMainIds.has(parent)) {
		iaSubIds.add(String(id));
		cleared.subs += 1;
	}
}
for (const [id, val] of Object.entries(secs)) {
	const parent = String(val?.sub_section ?? '');
	if (val?.__createdBy === 'ia_library_engine' || iaSubIds.has(parent)) {
		iaSecIds.add(String(id));
		cleared.secondaries += 1;
	}
}

// 3) تنفيذ الحذف — Firestore
async function bulkDeleteFileIds(ids) {
	const arr = [...ids];
	for (let i = 0; i < arr.length; i += 200) {
		const batch = fs.batch();
		for (const id of arr.slice(i, i + 200)) {
			batch.delete(fs.collection('dashboard_uploads').doc(id));
			batch.delete(fs.collection('content_unified_files').doc(id));
		}
		await batch.commit();
	}
}
await bulkDeleteFileIds(fileIdsToDelete);

if (iaMainIds.size + iaSubIds.size + iaSecIds.size > 0) {
	const buildDelete = (ids) => {
		const obj = {};
		for (const id of ids) obj[String(id)] = FieldValue.delete();
		return obj;
	};
	const batch = fs.batch();
	if (iaMainIds.size > 0)
		batch.update(fs.collection('sections_unified').doc('main'), buildDelete(iaMainIds));
	if (iaSubIds.size > 0)
		batch.update(fs.collection('sections_unified').doc('sub'), buildDelete(iaSubIds));
	if (iaSecIds.size > 0)
		batch.update(fs.collection('sections_unified').doc('secondary'), buildDelete(iaSecIds));
	await batch.commit();
}

// 4) RTDB — امسح حالة المحرّك كاملةً + السجلّات (autoBoot يعيد البناء نظيفاً)
await rtdb.ref().update({
	ia_library_engine: null,
	ia_library_registry: null,
	ia_library_failures: null
});

console.log('=== IA RESET FRESH — DONE ===');
console.log(JSON.stringify(cleared, null, 2));
console.log(`deleted file docs (unique fileIds): ${fileIdsToDelete.size}`);
console.log('RTDB ia_library_engine/registry/failures cleared.');
console.log('autoBootIfNeeded سيعيد إنشاء config افتراضي (enabled=true) عند أوّل tick.');

await app.delete().catch(() => {});
