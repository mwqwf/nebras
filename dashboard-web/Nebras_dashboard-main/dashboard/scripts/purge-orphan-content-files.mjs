/**
 * purge-orphan-content-files.mjs — تنظيف الملفات اليتيمة تحت dashboard/content/
 * (صور مصغّرة/ملفات كتب حُذفت وثائقها). بطلب المالك (2026-07-23).
 *
 * آمن: يبني «قائمة إبقاء» من معرّفات الوثائق المتبقّية فعلياً في
 * content_unified_files (المحتوى اليدويّ المحفوظ)، ثمّ يحذف تحت
 * dashboard/content/{fileId}/ كلّ fileId **غير** موجود في القائمة.
 * لا يلمس مجلدات أخرى.
 *
 *   node scripts/purge-orphan-content-files.mjs            → عَدّ فقط
 *   node scripts/purge-orphan-content-files.mjs --execute  → حذف فعليّ
 */
import admin from 'firebase-admin';
import { getFirestore } from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { resolveServiceAccount } from './load-admin-credential.mjs';
import { loadDashboardEnv } from './load-env.mjs';

loadDashboardEnv();

const EXECUTE = process.argv.includes('--execute');
const PROJECT_ID =
	process.env.VITE_FIREBASE_PROJECT_ID?.trim() || process.env.FIREBASE_PROJECT_ID?.trim() || 'nebras-9118c';
const BUCKET =
	process.env.VITE_FIREBASE_STORAGE_BUCKET?.trim() || 'nebras-9118c.firebasestorage.app';
const FIRESTORE_DB_ID = process.env.NEBRAS_FIRESTORE_DATABASE_ID?.trim() || 'default';

const { credentials } = resolveServiceAccount();
const app = admin.initializeApp({
	credential: admin.credential.cert(credentials),
	storageBucket: BUCKET
});
const fs = getFirestore(app, FIRESTORE_DB_ID);
const bucket = getStorage(app).bucket();

const CONTENT_PREFIX = 'dashboard/content/';

function fmtBytes(n) {
	const u = ['B', 'KB', 'MB', 'GB', 'TB'];
	let i = 0;
	let x = Number(n) || 0;
	while (x >= 1024 && i < u.length - 1) { x /= 1024; i++; }
	return `${x.toFixed(1)} ${u[i]}`;
}

/** يستخرج fileId من مسار dashboard/content/{fileId}/... */
function fileIdOf(objectPath) {
	const rest = String(objectPath).slice(CONTENT_PREFIX.length);
	const seg = rest.split('/')[0];
	return seg || '';
}

async function buildKeepSet() {
	const keep = new Set();
	// كل الوثائق المتبقّية في المجموعتين = محتوى محفوظ (يدويّ). معرّف الوثيقة = fileId.
	for (const coll of ['content_unified_files', 'dashboard_uploads']) {
		const snap = await fs.collection(coll).select('__provider').get();
		for (const d of snap.docs) keep.add(String(d.id));
	}
	return keep;
}

async function main() {
	console.log(`[orphans] المشروع: ${PROJECT_ID} | الحاوية: ${BUCKET}`);
	console.log(`[orphans] الوضع: ${EXECUTE ? '🔴 حذف فعليّ' : '🟢 عدّ فقط (dry-run)'}`);

	const keep = await buildKeepSet();
	console.log(`\n🔒 معرّفات محفوظة (محتوى يدويّ باقٍ): ${keep.size}`);
	for (const id of keep) console.log('   • dashboard/content/' + id + '/');

	const [files] = await bucket.getFiles({ prefix: CONTENT_PREFIX, autoPaginate: true });
	const toDelete = [];
	let keepCount = 0;
	let keepSize = 0;
	let delSize = 0;
	for (const f of files) {
		const id = fileIdOf(f.name);
		if (id && keep.has(id)) {
			keepCount++;
			keepSize += Number(f.metadata?.size || 0);
		} else {
			toDelete.push(f);
			delSize += Number(f.metadata?.size || 0);
		}
	}

	console.log(`\n📁 ${CONTENT_PREFIX} إجمالي: ${files.length} ملف`);
	console.log(`   ✅ يُحفَظ: ${keepCount} ملف (${fmtBytes(keepSize)})`);
	console.log(`   🗑️ يتيم للحذف: ${toDelete.length} ملف (${fmtBytes(delSize)})`);

	if (!EXECUTE) {
		console.log('\n🟢 عدّ فقط — لم يُحذف شيء. للتنفيذ: أضف --execute');
		process.exit(0);
	}

	console.log('\n🔴 بدء حذف اليتامى...');
	let n = 0;
	const CONCURRENCY = 20;
	for (let i = 0; i < toDelete.length; i += CONCURRENCY) {
		const batch = toDelete.slice(i, i + CONCURRENCY);
		await Promise.all(batch.map((f) => f.delete({ ignoreNotFound: true }).catch(() => {})));
		n += batch.length;
		if (n % 500 === 0 || n === toDelete.length) console.log(`   حُذف ${n}/${toDelete.length}...`);
	}
	console.log(`\n✅ اكتمل: حُذف ${n} ملف يتيم. المحتوى اليدويّ (${keepCount} ملف) سليم.`);
	process.exit(0);
}

main().catch((e) => {
	console.error('[orphans] فشل:', e?.stack || e?.message || e);
	process.exit(1);
});
