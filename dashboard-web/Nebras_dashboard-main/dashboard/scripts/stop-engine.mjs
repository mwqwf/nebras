/**
 * stop-engine.mjs — إيقاف فوري للمحرّك (enabled=false) من خارج الواجهة.
 * يفيد عند الحاجة لإيقاف المحرّك دون الدخول للوحة التحكّم.
 */
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { initializeApp, cert, getApps, getApp } from 'firebase-admin/app';
import { getDatabase } from 'firebase-admin/database';

function loadDotEnv() {
	const envPath = resolve('.env');
	if (!existsSync(envPath)) return;
	for (const line of readFileSync(envPath, 'utf8').split(/\r?\n/)) {
		const trimmed = line.trim();
		if (!trimmed || trimmed.startsWith('#')) continue;
		const eq = trimmed.indexOf('=');
		if (eq < 0) continue;
		const key = trimmed.slice(0, eq).trim();
		let val = trimmed.slice(eq + 1).trim();
		if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
			val = val.slice(1, -1);
		}
		if (!process.env[key]) process.env[key] = val;
	}
}
loadDotEnv();

const KEY_PATH = process.env.NEBRAS_SERVICE_ACCOUNT_PATH || 'secrets/serviceAccountKey.json';
const DB_URL =
	process.env.NEBRAS_DATABASE_URL ||
	process.env.FIREBASE_DATABASE_URL ||
	'https://nebras-9118c-default-rtdb.firebaseio.com';

if (getApps().length === 0) {
	initializeApp({
		credential: cert(JSON.parse(readFileSync(resolve(KEY_PATH), 'utf8'))),
		databaseURL: DB_URL
	}, 'stop');
}
const db = getDatabase(getApp('stop'));

await db.ref('noor_library_engine/config/enabled').set(false);
await db.ref('noor_library_engine/log').push({
	ts: Date.now(),
	level: 'warn',
	message: 'إيقاف يدوي للمحرّك من scripts/stop-engine.mjs'
});
console.log('OK — engine.config.enabled = false');
process.exit(0);
