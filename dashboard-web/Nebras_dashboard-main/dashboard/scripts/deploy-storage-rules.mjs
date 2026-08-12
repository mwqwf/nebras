/**
 * ينشر storage.rules إلى مشروع nebras-9118c عبر Firebase Rules API.
 * يتطلّب على مفتاح الخدمة دور Firebase Rules Admin (roles/firebaserules.admin).
 *
 * نظير deploy-firestore-rules.mjs لكنّه يستهدف إصدار Cloud Storage.
 * نستعمل Rules API مباشرةً بدل `firebase deploy --only storage` لأنّ الأخير
 * يفحص serviceusage.googleapis.com (تفعيل API) وهي صلاحية لا يملكها مفتاح
 * النشر؛ بينما Rules API هو ما يملك المفتاح صلاحيّته فعلاً.
 *
 *   npm run deploy:storage-rules
 */
import fs from 'node:fs';
import path from 'node:path';
import url from 'node:url';
import { getRulesAccessToken } from './load-admin-credential.mjs';

const PROJECT_ID =
	process.env.VITE_FIREBASE_PROJECT_ID?.trim() ||
	process.env.FIREBASE_PROJECT_ID?.trim() ||
	'nebras-9118c';

/**
 * إصدار Cloud Storage — يطابق ما يُرجعه check:rules
 * (firebase.storage/<bucket>). الـ bucket الافتراضيّ للمشروع.
 */
const STORAGE_BUCKET =
	process.env.VITE_FIREBASE_STORAGE_BUCKET?.trim() ||
	process.env.FIREBASE_STORAGE_BUCKET?.trim() ||
	`${PROJECT_ID}.firebasestorage.app`;
const RELEASE_ID = `firebase.storage/${STORAGE_BUCKET}`;
const RULES_API = 'https://firebaserules.googleapis.com/v1';

const __dirname = path.dirname(url.fileURLToPath(import.meta.url));
// storage.rules يقع في جذر firebase.json (مستوى أعلى من dashboard/).
const RULES_FILE = path.resolve(__dirname, '..', '..', 'storage.rules');

async function api(method, urlPath, token, body) {
	const res = await fetch(`${RULES_API}${urlPath}`, {
		method,
		headers: {
			Authorization: `Bearer ${token}`,
			'Content-Type': 'application/json'
		},
		...(body ? { body: JSON.stringify(body) } : {})
	});
	const text = await res.text();
	let json;
	try {
		json = text ? JSON.parse(text) : {};
	} catch {
		json = { raw: text };
	}
	if (!res.ok) {
		const err = new Error(json?.error?.message || text || res.statusText);
		err.status = res.status;
		err.details = json?.error;
		err.step = urlPath;
		throw err;
	}
	return json;
}

async function main() {
	if (!fs.existsSync(RULES_FILE)) {
		throw new Error(`ملف القواعد غير موجود: ${RULES_FILE}`);
	}

	const content = fs.readFileSync(RULES_FILE, 'utf8');
	const token = await getRulesAccessToken();

	console.log(`[deploy:storage-rules] مشروع: ${PROJECT_ID}`);
	console.log(`[deploy:storage-rules] bucket: ${STORAGE_BUCKET}`);
	console.log(`[deploy:storage-rules] ملف: ${RULES_FILE}`);

	const ruleset = await api('POST', `/projects/${PROJECT_ID}/rulesets`, token, {
		source: {
			files: [{ name: 'storage.rules', content }]
		}
	});

	const rulesetName = ruleset.name;
	if (!rulesetName) {
		throw new Error('لم يُرجع API اسم ruleset بعد الإنشاء.');
	}

	const releaseResource = `projects/${PROJECT_ID}/releases/${RELEASE_ID}`;
	await api(
		'PATCH',
		`/projects/${PROJECT_ID}/releases/${encodeURIComponent(RELEASE_ID)}?updateMask=rulesetName`,
		token,
		{
			release: {
				name: releaseResource,
				rulesetName
			}
		}
	);

	console.log(`[deploy:storage-rules] تم — ruleset: ${rulesetName}`);
	console.log(`[deploy:storage-rules] release: projects/${PROJECT_ID}/releases/${RELEASE_ID}`);
}

main().catch((err) => {
	if (err.status === 403) {
		console.error(
			'[deploy:storage-rules] مرفوض (403): مفتاح الخدمة يحتاج دور Firebase Rules Admin على المشروع.'
		);
		console.error(
			'  → Google Cloud Console → IAM → أضف roles/firebaserules.admin لحساب firebase-adminsdk@...'
		);
		console.error('  → أو انسخ القواعد يدويّاً من storage.rules إلى Firebase Console → Storage → Rules');
	} else {
		console.error('[deploy:storage-rules] فشل:', err?.message || err);
		if (err.step) console.error('[deploy:storage-rules] خطوة:', err.step);
		if (err.details) console.error('[deploy:storage-rules] تفاصيل:', JSON.stringify(err.details, null, 2));
	}
	process.exit(1);
});
