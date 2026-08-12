/**
 * يحاكي بدقة ما يفعله home_datasource.dart في تطبيق نبراس عند بناء
 * الصفحة الرئيسية، ثمّ يُطبع كلّ قسم سيظهر / يُحذف ولماذا.
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

const sa = JSON.parse(
	process.env.NEBRAS_SERVICE_ACCOUNT_JSON ||
		fs.readFileSync(process.env.NEBRAS_SERVICE_ACCOUNT_PATH, 'utf8')
);

if (getApps().length === 0) {
	initializeApp({
		credential: cert(sa),
		projectId: sa.project_id,
		databaseURL: `https://${sa.project_id}-default-rtdb.firebaseio.com`
	});
}

const db = getDatabase();
const PAGE = 20;

function isExplicitlyHidden(rec) {
	const v = rec?.is_listed;
	if (v == null) return false;
	if (typeof v === 'boolean') return !v;
	const s = String(v).trim().toLowerCase();
	return s === 'false' || s === '0';
}

async function main() {
	console.log('\n═══════ MUHAKAT تطبيق نبراس — بناء الصفحة الرئيسية ═══════\n');

	// 1) محاكاة: orderByKey().limitToFirst(20) على sections_unified
	const snap = await db
		.ref('sections_unified')
		.orderByKey()
		.limitToFirst(PAGE)
		.get();
	const root = snap.val() || {};

	console.log(`◉ root مفاتيح بعد limitToFirst(${PAGE}):`, Object.keys(root));

	const main = root.main || {};
	const sub = root.sub || {};
	const secondary = root.secondary || {};

	// 2) استخراج الأقسام الرئيسية كما يفعل _parseFlatSections
	console.log('\n──── parseFlatSections(main) ────');
	const mainSections = [];
	for (const [key, rec] of Object.entries(main)) {
		const id = String(rec?.id ?? key).trim();
		const name = String(rec?.name ?? rec?.title ?? id).trim();
		if (isExplicitlyHidden(rec)) {
			console.log(`  ✗ ${name} (${id}) — HIDDEN by is_listed`);
			continue;
		}
		if (!id || !name) {
			console.log(`  ✗ ${key} — empty id/name`);
			continue;
		}
		mainSections.push({ id, name });
		console.log(`  ✓ ${name} (${id})`);
	}

	// 3) محاكاة: home_screen.dart filter type=='main_section'
	console.log('\n──── ما يصل إلى home_screen.dart (where type==main_section) ────');
	const displaySections = mainSections; // كلها main_section
	console.log(`  العدد المتوقّع في الواجهة الرئيسيّة: ${displaySections.length}`);
	for (const s of displaySections) {
		console.log(`    • ${s.name} (${s.id})`);
	}

	// 4) فحص الأقسام الفرعية والثانوية تحت كل main
	console.log('\n──── الـ subs المرتبطة بكل main ────');
	for (const m of mainSections) {
		const linkedSubs = Object.values(sub).filter(
			(s) => String(s?.main_section ?? '') === m.id
		);
		const visibleSubs = linkedSubs.filter((s) => !isExplicitlyHidden(s));
		console.log(`  ${m.name} → ${visibleSubs.length} sub (مخفي: ${linkedSubs.length - visibleSubs.length})`);
		for (const s of visibleSubs) {
			console.log(`     - ${s.name}`);
		}
	}

	process.exit(0);
}

main().catch((e) => {
	console.error(e);
	process.exit(1);
});
