/**
 * ينشر database.rules.json (قواعد Realtime Database) إلى مشروع nebras-9118c
 * عبر REST endpoint `.settings/rules.json` باستخدام رمز وصول مُولَّد من مفتاح
 * الخدمة (نطاق cloud-platform). لا firebase CLI ولا طباعة لأي سرّ.
 *
 *   node scripts/deploy-database-rules.mjs
 *
 * يتطلّب أن يملك مفتاح الخدمة صلاحيّة تحديث RTDB (Firebase Admin / Editor).
 */
import fs from 'node:fs';
import path from 'node:path';
import url from 'node:url';
import { GoogleAuth } from 'google-auth-library';
import { resolveServiceAccount } from './load-admin-credential.mjs';
import { loadDashboardEnv } from './load-env.mjs';

loadDashboardEnv();

// نطاقات RTDB REST `.settings/rules.json` — cloud-platform لا يكفي هنا.
const DB_SCOPES = [
	'https://www.googleapis.com/auth/firebase.database',
	'https://www.googleapis.com/auth/userinfo.email'
];

async function getDatabaseAccessToken() {
	const { credentials, sourcePath } = resolveServiceAccount();
	const auth = new GoogleAuth({
		credentials,
		...(sourcePath ? { keyFile: sourcePath } : {}),
		scopes: DB_SCOPES
	});
	const client = await auth.getClient();
	const token = await client.getAccessToken();
	if (!token.token) throw new Error('تعذّر الحصول على access token.');
	return token.token;
}

const PROJECT_ID =
	process.env.VITE_FIREBASE_PROJECT_ID?.trim() ||
	process.env.FIREBASE_PROJECT_ID?.trim() ||
	'nebras-9118c';

function databaseUrl() {
	const explicit =
		process.env.VITE_FIREBASE_DATABASE_URL?.trim() ||
		process.env.FIREBASE_DATABASE_URL?.trim();
	if (explicit) return explicit.replace(/\/+$/, '');
	return `https://${PROJECT_ID}-default-rtdb.firebaseio.com`;
}

const __dirname = path.dirname(url.fileURLToPath(import.meta.url));
// database.rules.json يقع في الطبقة الثانية بجانب firebase.json (..//.. من scripts)
const RULES_FILE = path.resolve(__dirname, '..', '..', 'database.rules.json');

async function main() {
	if (!fs.existsSync(RULES_FILE)) {
		throw new Error(`ملف القواعد غير موجود: ${RULES_FILE}`);
	}
	const content = fs.readFileSync(RULES_FILE, 'utf8');
	// تحقّق أنّه JSON صالح قبل الإرسال.
	JSON.parse(content);

	const dbUrl = databaseUrl();
	const token = await getDatabaseAccessToken();

	console.log(`[deploy:db-rules] مشروع: ${PROJECT_ID}`);
	console.log(`[deploy:db-rules] قاعدة: ${dbUrl}`);
	console.log(`[deploy:db-rules] ملف: ${RULES_FILE}`);

	const res = await fetch(`${dbUrl}/.settings/rules.json`, {
		method: 'PUT',
		headers: {
			Authorization: `Bearer ${token}`,
			'Content-Type': 'application/json'
		},
		body: content
	});
	const text = await res.text();
	if (!res.ok) {
		const err = new Error(text || res.statusText);
		err.status = res.status;
		throw err;
	}
	console.log('[deploy:db-rules] ✅ تم نشر قواعد RTDB بنجاح.');
}

main().catch((err) => {
	if (err.status === 401 || err.status === 403) {
		console.error(
			`[deploy:db-rules] مرفوض (${err.status}): مفتاح الخدمة يحتاج صلاحيّة تحديث Realtime Database ` +
				'(roles/firebasedatabase.admin أو Editor).'
		);
		console.error('  → أو انسخ database.rules.json يدوياً إلى Firebase Console → Realtime Database → Rules.');
	} else {
		console.error('[deploy:db-rules] فشل:', err?.message || err);
	}
	process.exit(1);
});
