/**
 * قراءات/كتابات Firestore للمحتوى الموحّد — من خادم SvelteKit (firebase-admin).
 */
import { FieldValue } from 'firebase-admin/firestore';
import { getNebrasFirestoreAdmin } from '$lib/server/firebaseAdmin.js';
import {
	NEBRAS_FS_SECTIONS,
	NEBRAS_FS_UPLOADS,
	NEBRAS_FS_CONTENT_FILES
} from '$lib/firebase/nebrasUnifiedPaths.js';
import { stripUndefinedDeep, clampContentTextFields } from '$lib/nebrasUnifiedSanitize.js';

function adb() {
	return getNebrasFirestoreAdmin();
}

/** @param {'main'|'sub'|'secondary'} level */
export async function adminFsReadSectionsLevel(level) {
	const snap = await adb().collection(NEBRAS_FS_SECTIONS).doc(level).get();
	if (!snap.exists) return [];
	return Object.values(snap.data() || {});
}

export async function adminFsReadSectionsSubMap() {
	const snap = await adb().collection(NEBRAS_FS_SECTIONS).doc('sub').get();
	return snap.exists ? snap.data() || {} : {};
}

/** @param {'main'|'sub'|'secondary'} level */
export async function adminFsGetSectionRecord(level, id) {
	const snap = await adb().collection(NEBRAS_FS_SECTIONS).doc(level).get();
	if (!snap.exists) return null;
	const key = String(id);
	const d = snap.data() || {};
	return d[key] !== undefined ? d[key] : null;
}

/** @param {'main'|'sub'|'secondary'} level */
export async function adminFsSetSectionRecord(level, id, value) {
	const key = String(id);
	await adb()
		.collection(NEBRAS_FS_SECTIONS)
		.doc(level)
		.set({ [key]: stripUndefinedDeep(value) }, { merge: true });
}

/** @param {'main'|'sub'|'secondary'} level */
export async function adminFsDeleteSectionRecord(level, id) {
	const ref = adb().collection(NEBRAS_FS_SECTIONS).doc(level);
	const snap = await ref.get();
	if (!snap.exists) return;
	await ref.update({ [String(id)]: FieldValue.delete() });
}

export async function adminFsWriteFileMirrorBoth(fileId, payload) {
	const db = adb();
	const id = String(fileId);
	// قصّ الوصف الضخم قبل الكتابة (يمنع تضخّم الوثيقة وانهيار قراءة الجوال).
	const data = stripUndefinedDeep(clampContentTextFields(payload));
	const batch = db.batch();
	batch.set(db.collection(NEBRAS_FS_UPLOADS).doc(id), data);
	batch.set(db.collection(NEBRAS_FS_CONTENT_FILES).doc(id), data);
	await batch.commit();
}

export async function adminFsDeleteFileMirrorBoth(fileId) {
	const db = adb();
	const id = String(fileId);
	const batch = db.batch();
	batch.delete(db.collection(NEBRAS_FS_UPLOADS).doc(id));
	batch.delete(db.collection(NEBRAS_FS_CONTENT_FILES).doc(id));
	await batch.commit();
}

export async function adminFsListFileRowsForFactoryReset() {
	const db = adb();
	const [u1, u2] = await Promise.all([
		db.collection(NEBRAS_FS_UPLOADS).get(),
		db.collection(NEBRAS_FS_CONTENT_FILES).get()
	]);
	return { uploadsDocs: u1.docs, contentFileDocs: u2.docs };
}

export async function adminFsBulkDeleteSectionKeys(level, ids) {
	const uniq = [...new Set(ids.map(String))].filter(Boolean);
	if (!uniq.length) return;
	const ref = adb().collection(NEBRAS_FS_SECTIONS).doc(level);
	const snap = await ref.get();
	if (!snap.exists) return;
	for (let i = 0; i < uniq.length; i += 400) {
		const chunk = uniq.slice(i, i + 400);
		const upd = Object.fromEntries(chunk.map((id) => [id, FieldValue.delete()]));
		await ref.update(upd);
	}
}

export async function adminFsBulkDeleteFileMirrorIds(ids) {
	const uniq = [...new Set(ids.map(String))].filter(Boolean);
	if (!uniq.length) return;
	const db = adb();
	for (let i = 0; i < uniq.length; i += 200) {
		const batch = db.batch();
		for (const id of uniq.slice(i, i + 200)) {
			batch.delete(db.collection(NEBRAS_FS_UPLOADS).doc(id));
			batch.delete(db.collection(NEBRAS_FS_CONTENT_FILES).doc(id));
		}
		await batch.commit();
	}
}
