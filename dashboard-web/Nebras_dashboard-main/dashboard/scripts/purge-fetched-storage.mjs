/**
 * purge-fetched-storage.mjs — حذف ملفات الكتب المجلوبة من Cloud Storage
 * (نور + هنداوي) بطلب المالك (2026-07-23). الأرشيف يُبَثّ من archive.org غالباً
 * (لا ملفات تخزين) — الفحص يؤكّد.
 *
 * يحذف بالبادئات التي تخصّ المحرّكات فقط:
 *   • dashboard/hindawi/        (ملفات كتب هنداوي)
 *   • dashboard/noor-library/   (ملفات كتب نور)
 *   • dashboard/internet-archive/ (إن وُجدت)
 * لا يلمس:
 *   • dashboard/content/  → مختلط: رفعك اليدويّ + صور مصغّرة (صغيرة) — يُحفَظ
 *   • أيّ مجلد UGC/آخر
 *
 * وضعان:
 *   node scripts/purge-fetched-storage.mjs            → عَدّ فقط (dry-run)
 *   node scripts/purge-fetched-storage.mjs --execute  → حذف فعليّ لا رجعة فيه
 */
import admin from 'firebase-admin';
import { getStorage } from 'firebase-admin/storage';
import { resolveServiceAccount } from './load-admin-credential.mjs';
import { loadDashboardEnv } from './load-env.mjs';

loadDashboardEnv();

const EXECUTE = process.argv.includes('--execute');
const BUCKET =
	process.env.VITE_FIREBASE_STORAGE_BUCKET?.trim() ||
	process.env.FIREBASE_STORAGE_BUCKET?.trim() ||
	'nebras-9118c.firebasestorage.app';

const { credentials } = resolveServiceAccount();
const app = admin.initializeApp({
	credential: admin.credential.cert(credentials),
	storageBucket: BUCKET
});
const bucket = getStorage(app).bucket();

// بادئات المحرّكات (ملفات الكتب الكبيرة) — آمنة للحذف الكامل.
const ENGINE_PREFIXES = [
	'dashboard/hindawi/',
	'dashboard/noor-library/',
	'dashboard/internet-archive/'
];

function fmtBytes(n) {
	const u = ['B', 'KB', 'MB', 'GB', 'TB'];
	let i = 0;
	let x = Number(n) || 0;
	while (x >= 1024 && i < u.length - 1) {
		x /= 1024;
		i++;
	}
	return `${x.toFixed(1)} ${u[i]}`;
}

async function listTopStructure() {
	const [, , api] = await bucket.getFiles({
		prefix: 'dashboard/',
		delimiter: '/',
		autoPaginate: false,
		maxResults: 1000
	});
	const prefixes = api?.prefixes || [];
	console.log('\n📂 المجلدات المباشرة تحت dashboard/:');
	if (!prefixes.length) console.log('   (لا مجلدات فرعية ظاهرة في الصفحة الأولى)');
	for (const p of prefixes) console.log('   •', p);
	return prefixes;
}

async function countPrefix(prefix) {
	const [files] = await bucket.getFiles({ prefix, autoPaginate: true });
	let size = 0;
	for (const f of files) size += Number(f.metadata?.size || 0);
	return { count: files.length, size };
}

async function main() {
	console.log(`[storage] الحاوية: ${BUCKET}`);
	console.log(`[storage] الوضع: ${EXECUTE ? '🔴 حذف فعليّ' : '🟢 عدّ فقط (dry-run)'}`);

	await listTopStructure();

	let grandCount = 0;
	let grandSize = 0;
	const targets = [];
	for (const prefix of ENGINE_PREFIXES) {
		const { count, size } = await countPrefix(prefix);
		console.log(`\n🗑️ ${prefix} → ${count} ملف (${fmtBytes(size)})`);
		grandCount += count;
		grandSize += size;
		if (count > 0) targets.push(prefix);
	}

	const content = await countPrefix('dashboard/content/');
	console.log(
		`\n✅ dashboard/content/ (يُحفَظ — يدوي + مصغّرات) → ${content.count} ملف (${fmtBytes(content.size)})`
	);

	console.log('\n══════════════════════════════════════════════');
	console.log(`للحذف: ${grandCount} ملف (${fmtBytes(grandSize)}) من ${targets.length} بادئة.`);
	console.log('══════════════════════════════════════════════');

	if (!EXECUTE) {
		console.log('\n🟢 عدّ فقط — لم يُحذف شيء. للتنفيذ: أضف --execute');
		process.exit(0);
	}

	console.log('\n🔴 بدء الحذف الفعليّ...');
	for (const prefix of targets) {
		await bucket.deleteFiles({ prefix, force: true });
		console.log(`   حُذف: ${prefix}`);
	}
	console.log('\n✅ اكتمل حذف ملفات التخزين المجلوبة.');
	process.exit(0);
}

main().catch((e) => {
	console.error('[storage] فشل:', e?.stack || e?.message || e);
	process.exit(1);
});
