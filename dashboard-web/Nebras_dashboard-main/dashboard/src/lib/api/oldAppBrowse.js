/**
 * oldAppBrowse.js — DISABLED.
 *
 * تمّ إلغاء جسر "OldApp" نهائيًّا في مشروع نبراس. لم يعد التطبيق يقرأ أو
 * يكتب إلى أيّ مشروع Firebase خارجي. لوحة التحكّم تعتمد حصرياً على قاعدة
 * Nebras (Cloud Firestore + Cloud Storage) كما هو موثّق في
 * `firestore.rules` و `nebrasUnifiedFirestoreClient.js`.
 *
 * نُبقي على هذا الملفّ كـ "وحدة معطّلة" (stub) لتفادي كسر `moderator.js`
 * الذي ما زال يستورد بعض الرموز التاريخيّة. كلّ الدوال تُعيد قِيَمًا آمنة
 * تُغلق فروع التنفيذ المرتبطة بـ OldApp فلا يقع أيّ نداء شبكيّ خارجيّ.
 *
 * ⚠️ ممنوع إعادة تفعيل المنطق هنا. أيّ كتابة جديدة يجب أن تذهب مباشرة إلى
 * مجموعات Firestore الموحَّدة لمشروع نبراس.
 */

export function isOldAppConfigured() {
	return false;
}

export function resetOldAppBrowseCache() {
	/* no-op — لا يوجد كاش لجسر معطّل */
}

export async function getHostMainSectionId(_opts) {
	return null;
}

export function isOldAppId(_id) {
	return false;
}

export function parseOldAppId(_id) {
	return null;
}

export async function listOldAppMainSections(_opts) {
	return [];
}

export async function listOldAppSubSections(_mainId, _opts) {
	return [];
}

export async function listOldAppLessonsBySub(_mainDocId, _subDocId) {
	return [];
}

export async function createOldAppMainSection(_payload) {
	throw new Error('OldApp bridge disabled');
}

export async function updateOldAppMainSection(_mainDocId, _patch) {
	throw new Error('OldApp bridge disabled');
}

export async function deleteOldAppMainSection(_mainDocId, _opts) {
	throw new Error('OldApp bridge disabled');
}

export async function createOldAppSubSection(_mainDocId, _payload) {
	throw new Error('OldApp bridge disabled');
}

export async function updateOldAppSubSection(_mainDocId, _subDocId, _patch) {
	throw new Error('OldApp bridge disabled');
}

export async function deleteOldAppSubSection(_mainDocId, _subDocId, _opts) {
	throw new Error('OldApp bridge disabled');
}

export async function createOldAppLesson(_payload) {
	throw new Error('OldApp bridge disabled');
}

export async function updateOldAppLesson(_lessonDocId, _patch) {
	throw new Error('OldApp bridge disabled');
}

export async function deleteOldAppLesson(_lessonDocId) {
	throw new Error('OldApp bridge disabled');
}

export function adaptOldAppMainAsSub(_item, _hostMainId) {
	return null;
}

export function adaptOldAppSubAsSecondary(_item, _parentMainDocId) {
	return null;
}

export function adaptOldAppLessonAsFile(_item, _ctx) {
	return null;
}

export function adaptOldAppLessonAsYoutube(_item, _ctx) {
	return null;
}
