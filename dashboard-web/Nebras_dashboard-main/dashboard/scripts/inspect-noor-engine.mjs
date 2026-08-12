/**
 * سكربت تشخيصي: يقرأ حالة محرّك Noor Library كاملةً من RTDB ويطبعها.
 *   - config (enabled, seedUrls, throttle…)
 *   - cursor (seedIndex, page)
 *   - stats (totalFetched, sectionsCreated, lastError, consecutiveEmptyRuns…)
 *   - log (آخر 60 إدخالاً مع level/reason/url)
 *   - failures (الكتب التي فشلت ⌐ كم مرّة + آخر سبب)
 *   - registry (إحصائيّات سريعة: كم كتاباً مُجلب فعلاً)
 *
 * الاستعمال:
 *   node scripts/inspect-noor-engine.mjs
 */

import { cert, getApps, initializeApp } from 'firebase-admin/app';
import { getDatabase } from 'firebase-admin/database';
import fs from 'node:fs';
import path from 'node:path';
import url from 'node:url';

// تحميل .env يدوياً (لا يوجد dotenv في devDependencies المتاحة)
const __dirname = path.dirname(url.fileURLToPath(import.meta.url));
const envFile = path.resolve(__dirname, '..', '.env');
if (fs.existsSync(envFile)) {
	const raw = fs.readFileSync(envFile, 'utf8');
	for (const line of raw.split(/\r?\n/)) {
		const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/i);
		if (!m) continue;
		const key = m[1];
		let val = m[2];
		if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
			val = val.slice(1, -1);
		}
		if (!(key in process.env)) process.env[key] = val;
	}
}

function readEnv(name) {
	const v = process.env[name];
	return typeof v === 'string' && v.trim() ? v.trim() : '';
}

function loadServiceAccount() {
	const inline =
		readEnv('NEBRAS_SERVICE_ACCOUNT_JSON') ||
		readEnv('FIREBASE_SERVICE_ACCOUNT_JSON');
	if (inline) return JSON.parse(inline);

	const path =
		readEnv('NEBRAS_SERVICE_ACCOUNT_PATH') ||
		readEnv('FIREBASE_SERVICE_ACCOUNT_PATH');
	if (path) return JSON.parse(fs.readFileSync(path, 'utf8'));

	throw new Error('No service account env var found');
}

function pad(s, n) {
	const str = String(s ?? '');
	return str.length >= n ? str : str + ' '.repeat(n - str.length);
}

function fmtTime(ts) {
	if (!ts) return '—';
	try {
		return new Date(Number(ts)).toISOString().replace('T', ' ').slice(0, 19);
	} catch {
		return String(ts);
	}
}

const sa = loadServiceAccount();
const databaseURL =
	readEnv('FIREBASE_DATABASE_URL') ||
	`https://${sa.project_id}-default-rtdb.firebaseio.com`;

if (getApps().length === 0) {
	initializeApp({ credential: cert(sa), projectId: sa.project_id, databaseURL });
}

const db = getDatabase();

async function main() {
	const root = 'noor_library_engine';

	const [cfgSnap, curSnap, statsSnap, logSnap, failSnap, regSnap] =
		await Promise.all([
			db.ref(`${root}/config`).get(),
			db.ref(`${root}/cursor`).get(),
			db.ref(`${root}/stats`).get(),
			db.ref(`${root}/log`).limitToLast(60).get(),
			db.ref('noor_library_failures').get(),
			db.ref('noor_library_registry').get()
		]);

	console.log('\n═══════════ CONFIG ═══════════');
	console.log(JSON.stringify(cfgSnap.val(), null, 2));

	console.log('\n═══════════ CURSOR ═══════════');
	console.log(JSON.stringify(curSnap.val(), null, 2));

	console.log('\n═══════════ STATS ═══════════');
	const stats = statsSnap.val() || {};
	console.log({
		totalFetched: stats.totalFetched || 0,
		sectionsCreated: stats.sectionsCreated || 0,
		runsCount: stats.runsCount || 0,
		consecutiveEmptyRuns: stats.consecutiveEmptyRuns || 0,
		lastRunAt: fmtTime(stats.lastRunAt),
		lastError: stats.lastError || null
	});

	console.log('\n═══════════ REGISTRY (كتب نجحت) ═══════════');
	const reg = regSnap.val() || {};
	const regKeys = Object.keys(reg);
	console.log(`عدد الكتب المُجلبة بنجاح: ${regKeys.length}`);
	if (regKeys.length > 0) {
		console.log('أحدث 5:');
		const sortedReg = regKeys
			.map((k) => ({ id: k, t: Number(reg[k]?.importedAt || 0), title: reg[k]?.title }))
			.sort((a, b) => b.t - a.t)
			.slice(0, 5);
		for (const r of sortedReg) {
			console.log(`  • [${fmtTime(r.t)}] ${r.title || r.id}`);
		}
	}

	console.log('\n═══════════ FAILURES (كتب فشلت) ═══════════');
	const failures = failSnap.val() || {};
	const failKeys = Object.keys(failures);
	console.log(`عدد الكتب الفاشلة: ${failKeys.length}`);

	// مجمّع حسب reason
	const byReason = new Map();
	for (const k of failKeys) {
		const f = failures[k] || {};
		const reason = f.lastReason || f.reason || 'unknown';
		const arr = byReason.get(reason) || [];
		arr.push({ id: k, ...f });
		byReason.set(reason, arr);
	}
	console.log('\nالتوزيع حسب السبب:');
	for (const [reason, arr] of [...byReason.entries()].sort((a, b) => b[1].length - a[1].length)) {
		console.log(`  ${pad(reason, 28)} = ${arr.length} كتاب`);
	}

	console.log('\nآخر 5 فشلٍ مع تفاصيل:');
	const recentFails = failKeys
		.map((k) => ({ id: k, ...(failures[k] || {}) }))
		.sort((a, b) => Number(b.lastFailedAt || 0) - Number(a.lastFailedAt || 0))
		.slice(0, 5);
	for (const f of recentFails) {
		console.log(`  • [${fmtTime(f.lastFailedAt)}] count=${f.count} reason=${f.lastReason || f.reason}`);
		console.log(`    url: ${f.url || '—'}`);
		console.log(`    msg: ${(f.lastMessage || f.message || '').slice(0, 200)}`);
	}

	console.log('\n═══════════ LOG (آخر 60) ═══════════');
	const log = logSnap.val() || {};
	const entries = Object.values(log)
		.sort((a, b) => Number(a.ts || 0) - Number(b.ts || 0));
	for (const e of entries) {
		const lvl = pad(e.level || '?', 7);
		const ts = fmtTime(e.ts);
		const reason = e.reason ? `[${e.reason}]` : '';
		const url = e.url ? ` ← ${e.url}` : '';
		console.log(`${ts} ${lvl} ${reason} ${e.message}${url}`);
	}

	process.exit(0);
}

main().catch((err) => {
	console.error('FATAL:', err);
	process.exit(1);
});
