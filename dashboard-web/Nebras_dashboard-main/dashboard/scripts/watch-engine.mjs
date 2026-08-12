/**
 * watch-engine.mjs — قراءة فورية لحالة محرّك Noor Library من RTDB.
 * يطبع الإحصائيات + آخر N سجلّ ثمّ يخرج.
 *
 * تشغيل:  node scripts/watch-engine.mjs [limit]
 */
import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { initializeApp, cert, getApps, getApp } from 'firebase-admin/app';
import { getDatabase } from 'firebase-admin/database';

// قراءة .env يدوياً (لا حاجة لمكتبة dotenv).
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
		if (
			(val.startsWith('"') && val.endsWith('"')) ||
			(val.startsWith("'") && val.endsWith("'"))
		) {
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

function loadCert() {
	const txt = readFileSync(resolve(KEY_PATH), 'utf8');
	return cert(JSON.parse(txt));
}

function appOnce() {
	if (getApps().length === 0) {
		initializeApp({ credential: loadCert(), databaseURL: DB_URL }, 'watch');
	}
	return getApp('watch');
}

const limit = Math.max(1, Math.min(60, Number(process.argv[2]) || 15));

const db = getDatabase(appOnce());

const [statsSnap, cursorSnap, configSnap, logSnap] = await Promise.all([
	db.ref('noor_library_engine/stats').get(),
	db.ref('noor_library_engine/cursor').get(),
	db.ref('noor_library_engine/config').get(),
	db.ref('noor_library_engine/log').orderByChild('ts').limitToLast(limit).get()
]);

const stats = statsSnap.val() || {};
const cursor = cursorSnap.val() || {};
const config = configSnap.val() || {};
const logEntries = Object.entries(logSnap.val() || {})
	.map(([id, v]) => ({ id, ...(v || {}) }))
	.sort((a, b) => Number(a.ts || 0) - Number(b.ts || 0));

const fmt = (ts) =>
	ts ? new Date(Number(ts)).toLocaleString('en-GB', { hour12: false }) : '—';

console.log('═══════════════════════════════════════════════════════════════════════');
console.log('CONFIG');
console.log('  enabled        :', config.enabled);
console.log('  batchSize      :', config.batchSize);
console.log('  tickIntervalMs :', config.tickIntervalMs);
console.log('  seedUrls       :', (config.seedUrls || []).length, 'بذرة');
console.log('───────────────────────────────────────────────────────────────────────');
console.log('CURSOR');
console.log('  seedIndex      :', cursor.seedIndex);
console.log('  page           :', cursor.page);
console.log('  currentSeed    :', (config.seedUrls || [])[cursor.seedIndex] || '—');
console.log('───────────────────────────────────────────────────────────────────────');
console.log('STATS');
console.log('  totalFetched     :', stats.totalFetched ?? 0);
console.log('  sectionsCreated  :', stats.sectionsCreated ?? 0);
console.log('  runsCount        :', stats.runsCount ?? 0);
console.log('  lastRunAt        :', fmt(stats.lastRunAt));
console.log('  lastError        :', stats.lastError || '—');
console.log('═══════════════════════════════════════════════════════════════════════');
console.log(`LAST ${logEntries.length} LOG ENTRIES (chronological)`);
console.log('───────────────────────────────────────────────────────────────────────');
for (const e of logEntries) {
	const lvl = (e.level || 'info').toUpperCase().padEnd(7);
	const tag = e.kind || e.reason || e.decision || '';
	const url = e.url ? `\n           ↳ ${e.url}` : '';
	const hier = e.hierarchy
		? `\n           ↳ ${e.hierarchy.main?.name || ''} › ${e.hierarchy.sub?.name || ''}${
				e.hierarchy.secondary?.name ? ' › ' + e.hierarchy.secondary.name : ''
			}`
		: '';
	console.log(`[${fmt(e.ts)}] ${lvl} ${tag ? `(${tag}) ` : ''}${e.message || ''}${url}${hier}`);
}
console.log('═══════════════════════════════════════════════════════════════════════');

process.exit(0);
