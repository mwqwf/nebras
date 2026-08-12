/**
 * mshcatBrowse.js — DISABLED.
 *
 * تمّ إلغاء جسر "Mshcat" نهائيًّا في مشروع نبراس. لا اتصال بأيّ مشروع
 * Firebase خارجي بعد الآن. لوحة التحكّم تعتمد حصراً على قاعدة Nebras
 * (Cloud Firestore + Cloud Storage).
 *
 * نُبقي هذا الملفّ كـ "وحدة معطّلة" لتفادي كسر `moderator.js` الذي ما زال
 * يستورد بعض الرموز التاريخيّة. كلّ الدوال تُعيد قِيَمًا آمنة تمنع تنفيذ
 * أيّ منطق مرتبط بـ Mshcat.
 *
 * ⚠️ ممنوع إعادة تفعيل المنطق هنا. أيّ كتابة جديدة يجب أن تذهب مباشرة إلى
 * مجموعات Firestore الموحَّدة لمشروع نبراس.
 */

export function isMshcatConfigured() {
	return false;
}

export function isMshcatId(_id) {
	return false;
}

export function parseMshcatId(_id) {
	return null;
}

export async function listMshcatMainSections(_opts) {
	return [];
}

export async function listMshcatSubSections(_mainId, _opts) {
	return [];
}

export async function listMshcatSecondarySections(_mainId, _subId, _opts) {
	return [];
}

export async function listMshcatBooksForCategory(_categoryDocId, _opts) {
	return [];
}

export async function listAllMshcatBooks(_opts) {
	return [];
}

export function classifyMshcatCategories(_categories) {
	return { main: [], sub: [], secondary: [] };
}

export async function createMshcatCategory(_payload) {
	throw new Error('Mshcat bridge disabled');
}

export async function updateMshcatCategory(_docId, _patch) {
	throw new Error('Mshcat bridge disabled');
}

export async function deleteMshcatCategory(_docId) {
	throw new Error('Mshcat bridge disabled');
}

export async function createMshcatBook(_payload) {
	throw new Error('Mshcat bridge disabled');
}

export async function updateMshcatBook(_docId, _patch) {
	throw new Error('Mshcat bridge disabled');
}

export async function deleteMshcatBook(_docId) {
	throw new Error('Mshcat bridge disabled');
}

export function adaptMshcatMain(_item) {
	return null;
}

export function adaptMshcatSub(_item) {
	return null;
}

export function adaptMshcatSecondary(_item) {
	return null;
}

export function adaptMshcatBookAsFile(_item) {
	return null;
}

export function adaptMshcatBookAsYoutube(_item) {
	return null;
}
