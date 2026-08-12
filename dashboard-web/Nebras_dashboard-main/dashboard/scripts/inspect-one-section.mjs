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

const sa = JSON.parse(
	process.env.NEBRAS_SERVICE_ACCOUNT_JSON ||
		process.env.FIREBASE_SERVICE_ACCOUNT_JSON ||
		fs.readFileSync(
			process.env.NEBRAS_SERVICE_ACCOUNT_PATH || process.env.FIREBASE_SERVICE_ACCOUNT_PATH,
			'utf8'
		)
);

if (getApps().length === 0) {
	initializeApp({
		credential: cert(sa),
		projectId: sa.project_id,
		databaseURL:
			process.env.FIREBASE_DATABASE_URL ||
			`https://${sa.project_id}-default-rtdb.firebaseio.com`
	});
}

const db = getDatabase();

async function main() {
	console.log('\n═══ FULL sections_unified JSON ═══\n');
	const snap = await db.ref('sections_unified').get();
	console.log(JSON.stringify(snap.val(), null, 2));
	process.exit(0);
}

main().catch((err) => {
	console.error(err);
	process.exit(1);
});
