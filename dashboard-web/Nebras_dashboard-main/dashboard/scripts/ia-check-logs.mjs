/**
 * قراءة سجلات محرّك IA من RTDB (تشغيل محليّ مع .env).
 * node scripts/ia-check-logs.mjs
 */
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { cert, initializeApp, getApps } from 'firebase-admin/app';
import { getDatabase } from 'firebase-admin/database';

const __dir = dirname(fileURLToPath(import.meta.url));
const envPath = resolve(__dir, '../.env');
let envRaw = '';
try {
	envRaw = readFileSync(envPath, 'utf8');
} catch (e) {
	console.error('لا يوجد .env:', e.message);
	process.exit(1);
}

function env(name) {
	const m = envRaw.match(new RegExp(`^${name}=(.*)$`, 'm'));
	if (!m) return '';
	let v = m[1].trim();
	if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) {
		v = v.slice(1, -1);
	}
	return v;
}

const jsonInline = env('NEBRAS_SERVICE_ACCOUNT_JSON') || env('FIREBASE_SERVICE_ACCOUNT_JSON');
const jsonPath = env('NEBRAS_SERVICE_ACCOUNT_PATH') || env('FIREBASE_SERVICE_ACCOUNT_PATH');
let sa = null;
if (jsonInline && jsonInline.startsWith('{')) sa = JSON.parse(jsonInline);
else if (jsonPath) sa = JSON.parse(readFileSync(resolve(__dir, '..', jsonPath), 'utf8'));

if (!sa) {
	console.error('Service account غير موجود في .env');
	process.exit(1);
}

if (!getApps().length) {
	initializeApp({
		credential: cert(sa),
		databaseURL:
			env('NEBRAS_FIREBASE_DATABASE_URL') ||
			env('FIREBASE_DATABASE_URL') ||
			`https://${sa.project_id}-default-rtdb.firebaseio.com`
	});
}

const db = getDatabase();

const [stats, config, cursor, logSnap, failSnap, regSnap] = await Promise.all([
	db.ref('ia_library_engine/stats').get(),
	db.ref('ia_library_engine/config').get(),
	db.ref('ia_library_engine/cursor').get(),
	db.ref('ia_library_engine/log').get(),
	db.ref('ia_library_failures').get(),
	db.ref('ia_library_registry').get()
]);

console.log('\n=== STATS ===');
console.log(JSON.stringify(stats.val(), null, 2));

console.log('\n=== CONFIG (enabled, scrapeCount) ===');
const cfg = config.val() || {};
console.log({
	enabled: cfg.enabled,
	scrapeCount: cfg.scrapeCount,
	batchSize: cfg.batchSize,
	seedsCount: Array.isArray(cfg.seeds) ? cfg.seeds.length : 0
});

console.log('\n=== CURSOR ===');
console.log(JSON.stringify(cursor.val(), null, 2));

console.log('\n=== LAST LOG (25) ===');
const logEntries = Object.entries(logSnap.val() || {})
	.sort((a, b) => Number(b[1]?.ts || 0) - Number(a[1]?.ts || 0))
	.slice(0, 25);
for (const [, e] of logEntries) {
	console.log(
		`[${new Date(e.ts).toISOString()}] ${e.level} ${e.message}${e.reason ? ` (${e.reason})` : ''}`
	);
}

console.log('\n=== LAST FAILURES (15) ===');
const fails = Object.entries(failSnap.val() || {})
	.sort((a, b) => Number(b[1]?.ts || 0) - Number(a[1]?.ts || 0))
	.slice(0, 15);
for (const [id, f] of fails) {
	console.log(`- ${id}: ${f.reason} — ${(f.message || '').slice(0, 120)}`);
}

console.log('\n=== REGISTRY (last 5 imported) ===');
const reg = Object.entries(regSnap.val() || {})
	.sort((a, b) => Number(b[1]?.importedAt || 0) - Number(a[1]?.importedAt || 0))
	.slice(0, 5);
for (const [id, r] of reg) {
	console.log(`- ${id}: ${r.title || ''} fileId=${r.fileId || ''}`);
}

console.log('\n=== REGISTRY COUNT ===');
console.log(regSnap.exists() ? Object.keys(regSnap.val()).length : 0);

process.exit(0);
