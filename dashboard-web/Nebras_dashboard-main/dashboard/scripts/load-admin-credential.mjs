/**
 * يحمّل مفتاح خدمة Nebras من .env (مسار أو JSON مضمّن) ويُصدر access token
 * لـ Firebase Rules API — بدون طباعة محتوى المفتاح.
 */
import fs from 'node:fs';
import path from 'node:path';
import { GoogleAuth } from 'google-auth-library';
import { loadDashboardEnv } from './load-env.mjs';

const RULES_SCOPES = ['https://www.googleapis.com/auth/cloud-platform'];
const MATERIALIZED_SA = path.resolve('secrets', '.runtime-sa-from-env.json');

function readEnv(name) {
	return String(process.env[name] || '').trim();
}

/**
 * @param {string} inline
 * @param {string} filePath
 * @returns {{ credentials: Record<string, unknown>, sourcePath: string | null }}
 */
function parseServiceAccount(inline, filePath) {
	if (inline) {
		const trimmed = inline.trim();
		if (trimmed.startsWith('{')) {
			return { credentials: JSON.parse(trimmed), sourcePath: null };
		}
		const abs = path.resolve(trimmed);
		return {
			credentials: JSON.parse(fs.readFileSync(abs, 'utf8')),
			sourcePath: abs
		};
	}
	if (filePath) {
		const abs = path.resolve(filePath);
		return {
			credentials: JSON.parse(fs.readFileSync(abs, 'utf8')),
			sourcePath: abs
		};
	}
	throw new Error(
		'مفتاح الخدمة غير مُعرَّف — أضف NEBRAS_SERVICE_ACCOUNT_PATH أو FIREBASE_SERVICE_ACCOUNT_PATH أو JSON في .env.'
	);
}

/**
 * @returns {{ credentials: Record<string, unknown>, sourcePath: string | null }}
 */
export function resolveServiceAccount() {
	loadDashboardEnv();

	const combined = readEnv('NEBRAS_SERVICE_ACCOUNT');
	const jsonInline =
		readEnv('NEBRAS_SERVICE_ACCOUNT_JSON') || readEnv('FIREBASE_SERVICE_ACCOUNT_JSON');
	const jsonPath =
		readEnv('NEBRAS_SERVICE_ACCOUNT_PATH') || readEnv('FIREBASE_SERVICE_ACCOUNT_PATH');

	if (!combined && !jsonInline && !jsonPath) {
		throw new Error(
			'مفتاح الخدمة غير مُعرَّف — أضف NEBRAS_SERVICE_ACCOUNT_PATH أو FIREBASE_SERVICE_ACCOUNT_PATH في dashboard/.env.'
		);
	}

	return parseServiceAccount(combined || jsonInline, jsonPath);
}

/**
 * مسار ملف JSON لـ GOOGLE_APPLICATION_CREDENTIALS / firebase-tools.
 * إن كان المفتاح مضمّناً في .env فقط، يُكتب نسخة مؤقتة تحت secrets/ (مُستثناة من git).
 *
 * @returns {string}
 */
export function resolveServiceAccountFilePath() {
	const { credentials, sourcePath } = resolveServiceAccount();
	if (sourcePath && fs.existsSync(sourcePath)) {
		return path.resolve(sourcePath);
	}

	fs.mkdirSync(path.dirname(MATERIALIZED_SA), { recursive: true });
	fs.writeFileSync(MATERIALIZED_SA, JSON.stringify(credentials), { mode: 0o600 });
	return path.resolve(MATERIALIZED_SA);
}

/** @returns {Promise<string>} */
export async function getRulesAccessToken() {
	const { credentials, sourcePath } = resolveServiceAccount();
	const auth = new GoogleAuth({
		credentials,
		...(sourcePath ? { keyFile: sourcePath } : {}),
		scopes: RULES_SCOPES
	});
	const client = await auth.getClient();
	const token = await client.getAccessToken();
	if (!token.token) {
		throw new Error('تعذّر الحصول على access token من مفتاح الخدمة.');
	}
	return token.token;
}
