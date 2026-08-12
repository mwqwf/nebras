/**
 * يطبع بنية sections_unified الكاملة (main/sub/secondary) كما هي في RTDB.
 * يساعد على معرفة لماذا التطبيق يُخفي بعض الأقسام.
 */

import { cert, getApps, initializeApp } from 'firebase-admin/app';
import { getDatabase } from 'firebase-admin/database';
import fs from 'node:fs';
import path from 'node:path';
import url from 'node:url';

const __dirname = path.dirname(url.fileURLToPath(import.meta.url));
const envFile = path.resolve(__dirname, '..', '.env');
if (fs.existsSync(envFile)) {
	for (const line of fs.readFileSync(envFile, 'utf8').split(/\r?\n/)) {
		const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/i);
		if (!m) continue;
		let val = m[2];
		if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
			val = val.slice(1, -1);
		}
		if (!(m[1] in process.env)) process.env[m[1]] = val;
	}
}

function readEnv(n) {
	return (process.env[n] || '').trim();
}

const sa = JSON.parse(
	readEnv('NEBRAS_SERVICE_ACCOUNT_JSON') || readEnv('FIREBASE_SERVICE_ACCOUNT_JSON') ||
		fs.readFileSync(
			readEnv('NEBRAS_SERVICE_ACCOUNT_PATH') || readEnv('FIREBASE_SERVICE_ACCOUNT_PATH'),
			'utf8'
		)
);

if (getApps().length === 0) {
	initializeApp({
		credential: cert(sa),
		projectId: sa.project_id,
		databaseURL:
			readEnv('FIREBASE_DATABASE_URL') ||
			`https://${sa.project_id}-default-rtdb.firebaseio.com`
	});
}

const db = getDatabase();

async function main() {
	console.log('\n═══════ sections_unified ═══════\n');

	const snap = await db.ref('sections_unified').get();
	if (!snap.exists()) {
		console.log('(empty)');
		process.exit(0);
	}

	const root = snap.val() || {};

	for (const level of ['main', 'sub', 'secondary']) {
		const items = root[level] || {};
		const keys = Object.keys(items);
		console.log(`\n──── ${level.toUpperCase()} (${keys.length} items) ────`);
		for (const k of keys) {
			const r = items[k] || {};
			const flags = [];
			if (r.is_listed === false || r.is_listed === 'false' || r.is_listed === 0) {
				flags.push('HIDDEN');
			}
			if (r.__createdBy) flags.push(`by:${r.__createdBy}`);
			if (r.__provider) flags.push(`prov:${r.__provider}`);
			const parent = r.main_section || r.sub_section || '';
			const flagStr = flags.length ? ` [${flags.join(', ')}]` : '';
			const parentStr = parent ? ` parent=${parent}` : '';
			console.log(`  • ${k}: "${r.name || r.title || '?'}"${parentStr}${flagStr}`);
		}
	}

	process.exit(0);
}

main().catch((err) => {
	console.error('FATAL:', err);
	process.exit(1);
});
