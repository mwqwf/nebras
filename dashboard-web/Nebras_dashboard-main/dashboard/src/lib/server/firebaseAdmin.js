/**
 * Firebase Admin SDK — خادم فقط (SvelteKit server).
 *
 * مشروع Nebras الأساسي فقط — التحقّق من ID tokens، RTDB، FCM، إلخ.
 *
 * متغيّرات البيئة (server-side فقط — لا بادئة VITE_):
 *
 *   Nebras:
 *     NEBRAS_SERVICE_ACCOUNT_JSON   أو   NEBRAS_SERVICE_ACCOUNT_PATH
 *     (توافق رجعيّ) FIREBASE_SERVICE_ACCOUNT_JSON  /  FIREBASE_SERVICE_ACCOUNT_PATH
 *     (اختياري)     NEBRAS_SERVICE_ACCOUNT  ← يقبل JSON مدمجاً أو مساراً (Heuristic).
 *     (اختياري)     FIREBASE_DATABASE_URL   ← إن لم يُحدَّد نبنيه من project_id.
 */

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { cert, getApps, initializeApp } from 'firebase-admin/app';
import { getMessaging } from 'firebase-admin/messaging';
import { getAuth as getAdminAuth } from 'firebase-admin/auth';
import { getDatabase as getAdminRtdb } from 'firebase-admin/database';
import { getFirestore as getAdminFirestore } from 'firebase-admin/firestore';
import { env } from '$env/dynamic/private';

/** @type {import('firebase-admin/app').App|null} */
let cachedNebrasApp = null;
/** @type {Error|null} */
let nebrasInitError = null;

function readEnv(name) {
	return String(env[name] || process.env[name] || '').trim();
}

/**
 * @param {string} inline
 * @param {string} path
 * @returns {null | Record<string, any>}
 */
function parseServiceAccount(inline, path) {
	if (inline) {
		const trimmed = inline.trim();
		if (trimmed.startsWith('{')) {
			try {
				return JSON.parse(trimmed);
			} catch (err) {
				throw new Error(
					'service account inline JSON غير صالح: ' + (err?.message || err)
				);
			}
		}
		const abs = resolve(trimmed);
		const raw = readFileSync(abs, 'utf8');
		try {
			return JSON.parse(raw);
		} catch (err) {
			throw new Error(`الملف ${abs} ليس JSON صالحاً: ` + (err?.message || err));
		}
	}
	if (path) {
		const abs = resolve(path);
		const raw = readFileSync(abs, 'utf8');
		try {
			return JSON.parse(raw);
		} catch (err) {
			throw new Error(`الملف ${abs} ليس JSON صالحاً: ` + (err?.message || err));
		}
	}
	return null;
}

function loadNebrasServiceAccount() {
	const combined = readEnv('NEBRAS_SERVICE_ACCOUNT');
	const jsonInline =
		readEnv('NEBRAS_SERVICE_ACCOUNT_JSON') || readEnv('FIREBASE_SERVICE_ACCOUNT_JSON');
	const jsonPath =
		readEnv('NEBRAS_SERVICE_ACCOUNT_PATH') || readEnv('FIREBASE_SERVICE_ACCOUNT_PATH');
	if (!combined && !jsonInline && !jsonPath) return null;
	return parseServiceAccount(combined || jsonInline, jsonPath);
}

function initNebrasApp() {
	if (cachedNebrasApp) return cachedNebrasApp;
	if (nebrasInitError) throw nebrasInitError;

	try {
		if (getApps().length > 0) {
			const def = getApps().find((a) => a.name === '[DEFAULT]');
			if (def) {
				cachedNebrasApp = def;
				return def;
			}
		}

		const sa = loadNebrasServiceAccount();
		if (!sa) {
			throw new Error(
				'Service Account غير مُعرَّف — أضف NEBRAS_SERVICE_ACCOUNT_JSON / NEBRAS_SERVICE_ACCOUNT_PATH أو FIREBASE_SERVICE_ACCOUNT_JSON / FIREBASE_SERVICE_ACCOUNT_PATH في ملف .env.'
			);
		}

		/** @type {import('firebase-admin/app').AppOptions} */
		const options = {
			credential: cert(sa),
			projectId: sa.project_id,
			databaseURL:
				env.FIREBASE_DATABASE_URL ||
				process.env.FIREBASE_DATABASE_URL ||
				`https://${sa.project_id}-default-rtdb.firebaseio.com`
		};

		const bucketEnv = readEnv('NEBRAS_STORAGE_BUCKET') || readEnv('FIREBASE_STORAGE_BUCKET');
		const bucketFromSa = typeof sa.storage_bucket === 'string' ? sa.storage_bucket : '';
		// Firebase changed the default bucket naming for projects created after
		// October 2024: <project>.firebasestorage.app instead of <project>.appspot.com.
		// nebras-9118c falls in this new naming. We default to the new format and
		// require NEBRAS_STORAGE_BUCKET env to override if the project uses the
		// legacy appspot.com bucket.
		const bucket = bucketEnv || bucketFromSa || (sa.project_id ? `${sa.project_id}.firebasestorage.app` : '');
		if (bucket) options.storageBucket = bucket;

		const app = initializeApp(options);
		cachedNebrasApp = app;
		return app;
	} catch (err) {
		nebrasInitError = /** @type {Error} */ (err);
		throw err;
	}
}

/**
 * يُرجع تطبيق Admin للمشروع الأساسي (Nebras). محفوظ للتوافق مع الكود القائم.
 * @returns {import('firebase-admin/app').App}
 */
export function getAdminApp() {
	return initNebrasApp();
}

export function getNebrasAdminApp() {
	return initNebrasApp();
}

/** Admin Auth (Nebras) — يستخدم لفكّ وتوثيق Firebase ID tokens. */
export function getAdminAuthService() {
	return getAdminAuth(getAdminApp());
}

/** Realtime Database (Nebras) — لقراءة/كتابة dashboard_users وسواه. */
export function getAdminDatabase() {
	return getAdminRtdb(getAdminApp());
}

/** Firestore (Nebras) — قاعدة Firestore في nebras-9118c مسمّاة `default`
 *  (بدون أقواس)، فنمرّر الاسم صراحةً بدل الاعتماد على `(default)`. */
const NEBRAS_FIRESTORE_DATABASE_ID = String(
	env.NEBRAS_FIRESTORE_DATABASE_ID ||
		process.env.NEBRAS_FIRESTORE_DATABASE_ID ||
		'default'
);

export function getNebrasFirestoreAdmin() {
	return getAdminFirestore(initNebrasApp(), NEBRAS_FIRESTORE_DATABASE_ID);
}

/**
 * يتحقّق من Firebase ID token. يرمي `Error` إن لم يكن صالحاً.
 * @param {string} idToken
 * @returns {Promise<import('firebase-admin/auth').DecodedIdToken>}
 */
export async function verifyIdToken(idToken) {
	const token = (idToken || '').toString().trim();
	if (!token) throw new Error('missing_id_token');
	return getAdminAuthService().verifyIdToken(token, true);
}

export function isAdminConfigured() {
	return Boolean(
		readEnv('NEBRAS_SERVICE_ACCOUNT') ||
			readEnv('NEBRAS_SERVICE_ACCOUNT_JSON') ||
			readEnv('NEBRAS_SERVICE_ACCOUNT_PATH') ||
			readEnv('FIREBASE_SERVICE_ACCOUNT_JSON') ||
			readEnv('FIREBASE_SERVICE_ACCOUNT_PATH')
	);
}

/**
 * إرسال رسالة FCM إلى topic محدّد عبر مشروع Nebras.
 *
 * @param {{ topic: string, title: string, body: string, data?: Record<string, unknown> }} options
 */
export async function sendTopicMessage({ topic, title, body, data = {} }) {
	const app = getAdminApp();
	const messaging = getMessaging(app);

	const safeData = /** @type {Record<string,string>} */ ({});
	for (const [k, v] of Object.entries(data || {})) {
		if (v === null || v === undefined) continue;
		safeData[k] = typeof v === 'string' ? v : String(v);
	}
	// نضع العنوان والنصّ داخل `data` لأنّ التطبيق هو من يبني الإشعار المحلّيّ.
	if (title !== undefined && title !== null) safeData.title = String(title);
	if (body !== undefined && body !== null) safeData.body = String(body);

	// 🔑 رسالة **data-only** (بلا كتلة `notification`): لا يعرضها نظام أندرويد
	// تلقائياً في الخلفية؛ بل يستقبلها معالج الخلفية في التطبيق ويقرّر العرض
	// حسب تفضيل المستخدم. هذا يجعل زرّ إيقاف الإشعارات يوقف التدفّق فعلاً —
	// حتى في الخلفية — بدل الاعتماد على سريان إلغاء اشتراك الـ topic فقط.
	// ⚠️ ملاحظة نشر: يجب أن يصاحب هذا التغييرَ إصدارُ التطبيق الذي يَعرض
	// رسائل data-only؛ وإلّا فلن تُعرض إشعارات الخلفية على النسخ الأقدم.
	/** @type {import('firebase-admin/messaging').Message} */
	const message = {
		topic,
		data: safeData,
		android: {
			priority: 'high'
		},
		apns: {
			headers: {
				'apns-priority': '5',
				'apns-push-type': 'background'
			},
			payload: {
				aps: {
					'content-available': 1
				}
			}
		}
	};

	return messaging.send(message);
}

export { getApp as _internalGetApp } from 'firebase-admin/app';
