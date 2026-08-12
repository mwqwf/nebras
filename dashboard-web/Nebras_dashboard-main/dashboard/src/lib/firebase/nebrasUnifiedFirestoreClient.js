/**
 * قراءات/كتابات Firestore للمحتوى الموحّد — من متصفّح لوحة التحكّم (Firebase Web SDK).
 */
import {
	collection,
	doc,
	getDoc,
	setDoc,
	updateDoc,
	deleteField,
	getDocs,
	deleteDoc,
	writeBatch
} from 'firebase/firestore';
import { getNebrasFirestore } from '$lib/firebase/client.js';
import {
	NEBRAS_FS_SECTIONS,
	NEBRAS_FS_UPLOADS,
	NEBRAS_FS_CONTENT_FILES,
	NEBRAS_FS_CONTENT_YOUTUBE
} from '$lib/firebase/nebrasUnifiedPaths.js';
import { stripUndefinedDeep, clampContentTextFields } from '$lib/nebrasUnifiedSanitize.js';

function fs() {
	const db = getNebrasFirestore();
	if (!db) throw new Error('Firestore غير مهيأ — أضف VITE_FIREBASE_* في .env');
	return db;
}

/** @param {'main'|'sub'|'secondary'} level */
export async function clientFsReadSectionsLevel(level) {
	const snap = await getDoc(doc(fs(), NEBRAS_FS_SECTIONS, level));
	if (!snap.exists()) return [];
	return Object.values(snap.data() || {});
}

export async function clientFsReadSectionsSubMap() {
	const snap = await getDoc(doc(fs(), NEBRAS_FS_SECTIONS, 'sub'));
	return snap.exists() ? snap.data() || {} : {};
}

/** @param {'main'|'sub'|'secondary'} level */
export async function clientFsGetSectionRecord(level, id) {
	const snap = await getDoc(doc(fs(), NEBRAS_FS_SECTIONS, level));
	if (!snap.exists()) return null;
	const key = String(id);
	const d = snap.data() || {};
	return d[key] !== undefined ? d[key] : null;
}

/** @param {'main'|'sub'|'secondary'} level */
export async function clientFsSetSectionRecord(level, id, value) {
	const key = String(id);
	await setDoc(
		doc(fs(), NEBRAS_FS_SECTIONS, level),
		{ [key]: stripUndefinedDeep(value) },
		{ merge: true }
	);
}

/** @param {'main'|'sub'|'secondary'} level */
export async function clientFsDeleteSectionRecord(level, id) {
	const ref = doc(fs(), NEBRAS_FS_SECTIONS, level);
	const s = await getDoc(ref);
	if (!s.exists()) return;
	await updateDoc(ref, { [String(id)]: deleteField() });
}

// ⚠️ Legacy-cleanup only — ميزة يوتيوب أُزيلت بالكامل من اللوحة (لا إنشاء/تعديل).
// نُبقي القراءة والحذف فقط لتنظيف سجلّات `content_unified_youtube` القديمة عند
// حذف الأقسام، حتى لا تبقى وثائق يتيمة. لا تُستخدم لأيّ كتابة جديدة.
export async function clientFsListYoutubeRecords() {
	const snap = await getDocs(collection(fs(), NEBRAS_FS_CONTENT_YOUTUBE));
	return snap.docs.map((d) => {
		const data = d.data() || {};
		return { ...data, id: data.id ?? d.id };
	});
}

export async function clientFsDeleteYoutubeRecord(id) {
	await deleteDoc(doc(fs(), NEBRAS_FS_CONTENT_YOUTUBE, String(id)));
}

export async function clientFsListFileRowsMerged() {
	const db = fs();
	const [u1, u2] = await Promise.all([
		getDocs(collection(db, NEBRAS_FS_UPLOADS)),
		getDocs(collection(db, NEBRAS_FS_CONTENT_FILES))
	]);
	const rows = [];
	for (const d of u1.docs) {
		const data = d.data() || {};
		rows.push({
			...data,
			id: data.id ?? d.id,
			fileId: data.fileId ?? d.id
		});
	}
	for (const d of u2.docs) {
		const data = d.data() || {};
		rows.push({
			...data,
			id: data.id ?? d.id,
			fileId: data.fileId ?? d.id
		});
	}
	return rows;
}

export async function clientFsGetFileRow(fileId) {
	const id = String(fileId);
	const db = fs();
	const primary = await getDoc(doc(db, NEBRAS_FS_UPLOADS, id));
	if (primary.exists()) return primary.data() || {};
	const fallback = await getDoc(doc(db, NEBRAS_FS_CONTENT_FILES, id));
	return fallback.exists() ? fallback.data() || {} : null;
}

export async function clientFsWriteFileMirrorBoth(fileId, payload) {
	const db = fs();
	const id = String(fileId);
	// قصّ الوصف الضخم قبل الكتابة (يمنع تضخّم الوثيقة وانهيار قراءة الجوال).
	const data = stripUndefinedDeep(clampContentTextFields(payload));
	const batch = writeBatch(db);
	batch.set(doc(db, NEBRAS_FS_UPLOADS, id), data);
	batch.set(doc(db, NEBRAS_FS_CONTENT_FILES, id), data);
	await batch.commit();
}

export async function clientFsDeleteFileMirrorBoth(fileId) {
	const db = fs();
	const id = String(fileId);
	const batch = writeBatch(db);
	batch.delete(doc(db, NEBRAS_FS_UPLOADS, id));
	batch.delete(doc(db, NEBRAS_FS_CONTENT_FILES, id));
	await batch.commit();
}
