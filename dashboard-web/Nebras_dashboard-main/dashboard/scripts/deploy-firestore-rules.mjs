/**
 * ينشر dashboard/firestore.rules إلى مشروع nebras-9118c عبر Firebase Rules API.
 * يتطلّب على مفتاح الخدمة دور Firebase Rules Admin (roles/firebaserules.admin).
 *
 *   npm run deploy:rules
 */
import fs from 'node:fs';
import path from 'node:path';
import url from 'node:url';
import { getRulesAccessToken } from './load-admin-credential.mjs';

const PROJECT_ID =
	process.env.VITE_FIREBASE_PROJECT_ID?.trim() ||
	process.env.FIREBASE_PROJECT_ID?.trim() ||
	'nebras-9118c';

/** Firestore (default) — يطابق ما يُرجعه check:rules (cloud.firestore/default). */
const RELEASE_ID = 'cloud.firestore/default';
const RULES_API = 'https://firebaserules.googleapis.com/v1';

const __dirname = path.dirname(url.fileURLToPath(import.meta.url));
const RULES_FILE = path.resolve(__dirname, '..', 'firestore.rules');

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

	console.log(`[deploy:rules] مشروع: ${PROJECT_ID}`);
	console.log(`[deploy:rules] ملف: ${RULES_FILE}`);

	const ruleset = await api('POST', `/projects/${PROJECT_ID}/rulesets`, token, {
		source: {
			files: [{ name: 'firestore.rules', content }]
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

	console.log(`[deploy:rules] تم — ruleset: ${rulesetName}`);
	console.log(`[deploy:rules] release: projects/${PROJECT_ID}/releases/${RELEASE_ID}`);
}

main().catch((err) => {
	if (err.status === 403) {
		console.error(
			'[deploy:rules] مرفوض (403): مفتاح الخدمة يحتاج دور Firebase Rules Admin على المشروع.'
		);
		console.error(
			'  → Google Cloud Console → IAM → أضف roles/firebaserules.admin لحساب firebase-adminsdk@...'
		);
		console.error('  → أو انسخ القواعد يدويّاً من firestore.rules إلى Firebase Console → Firestore → Rules');
	} else {
		console.error('[deploy:rules] فشل:', err?.message || err);
		if (err.step) console.error('[deploy:rules] خطوة:', err.step);
		if (err.details) console.error('[deploy:rules] تفاصيل:', JSON.stringify(err.details, null, 2));
	}
	process.exit(1);
});
