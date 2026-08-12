/**
 * purge-fetched-content.mjs — حذف كل المحتوى المجلوب آلياً (Internet Archive +
 * مكتبة نور + مؤسسة هنداوي) من Firestore الإنتاج، بطلب المالك (2026-07-23).
 *
 * يمسح فقط الوثائق المُوسَّمة بمزوّد جلب (__provider يحوي: internet_archive /
 * archive.org / noor / hindawi). لا يمسّ:
 *   • المحتوى اليدوي (__provider = 'manual' أو بلا وسم)
 *   • محتوى المجتمع UGC (مجموعات ugc_* منفصلة، غير مشمولة أصلاً)
 *
 * وضعان:
 *   node scripts/purge-fetched-content.mjs            → عَدّ فقط (dry-run، لا حذف)
 *   node scripts/purge-fetched-content.mjs --execute  → حذف فعليّ لا رجعة فيه
 *
 * الأقسام: يُبلّغ عن الأقسام التي أنشأتها المحرّكات (__createdBy) ويحذفها في وضع
 * --execute فقط (مفتاح FieldValue.delete داخل مستندات sections_unified الثلاثة).
 * لا يلمس RTDB (سجلّات المحرّكات تبقى — تمنع إعادة الجلب لو أُلغي التجميد لاحقاً).
 */
import admin from 'firebase-admin';
import { getFirestore } from 'firebase-admin/firestore';
import { resolveServiceAccount } from './load-admin-credential.mjs';
import { loadDashboardEnv } from './load-env.mjs';

loadDashboardEnv();

const EXECUTE = process.argv.includes('--execute');
const PROJECT_ID =
	process.env.VITE_FIREBASE_PROJECT_ID?.trim() ||
	process.env.FIREBASE_PROJECT_ID?.trim() ||
	'nebras-9118c';
const DB_URL =
	process.env.VITE_FIREBASE_DATABASE_URL?.trim() ||
	process.env.FIREBASE_DATABASE_URL?.trim() ||
	`https://${PROJECT_ID}-default-rtdb.firebaseio.com`;
const FIRESTORE_DB_ID = process.env.NEBRAS_FIRESTORE_DATABASE_ID?.trim() || 'default';

const { credentials } = resolveServiceAccount();
const app = admin.initializeApp({
	credential: admin.credential.cert(credentials),
	databaseURL: DB_URL
});
// قاعدة Firestore مسمّاة `default` (لا `(default)`) — نمرّر المعرّف صراحةً.
const fs = getFirestore(app, FIRESTORE_DB_ID);
const FieldValue = admin.firestore.FieldValue;

const CONTENT_COLLECTIONS = ['content_unified_files', 'dashboard_uploads'];

/** هل هذا المزوّد محتوى مجلوب يجب حذفه؟ */
function isFetchedProvider(p) {
	const v = String(p ?? '').toLowerCase();
	if (!v) return false;
	return (
		v.includes('internet_archive') ||
		v.includes('archive.org') ||
		v.includes('noor') ||
		v.includes('hindawi')
	);
}

/** هل هذا القسم أنشأه محرّك جلب؟ */
function isEngineCreated(createdBy) {
	const v = String(createdBy ?? '').toLowerCase();
	if (!v) return false;
	return (
		v.includes('engine') ||
		v.includes('internet_archive') ||
		v.includes('archive') ||
		v.includes('noor') ||
		v.includes('hindawi')
	);
}

async function scanContent(coll) {
	// نجلب حقل __provider وحده (لا الأوصاف الضخمة 200KB+) — أسرع بمراحل ويتجنّب OOM.
	const snap = await fs.collection(coll).select('__provider').get();
	const byProvider = {};
	const toDelete = [];
	for (const d of snap.docs) {
		const p = d.data()?.__provider ?? '(بلا وسم)';
		byProvider[p] = (byProvider[p] || 0) + 1;
		if (isFetchedProvider(p)) toDelete.push(d.ref);
	}
	return { total: snap.size, byProvider, toDelete };
}

async function scanSections() {
	const ref = fs.collection('sections_unified');
	const out = {};
	for (const docId of ['main', 'sub', 'secondary']) {
		const snap = await ref.doc(docId).get();
		const data = snap.exists ? snap.data() || {} : {};
		const byCreator = {};
		const engineIds = [];
		for (const [id, rec] of Object.entries(data)) {
			const c = rec?.__createdBy ?? '(بلا وسم)';
			byCreator[c] = (byCreator[c] || 0) + 1;
			if (isEngineCreated(rec?.__createdBy)) engineIds.push(id);
		}
		out[docId] = { total: Object.keys(data).length, byCreator, engineIds };
	}
	return out;
}

async function deleteRefs(refs) {
	let n = 0;
	let batch = fs.batch();
	for (const ref of refs) {
		batch.delete(ref);
		n++;
		if (n % 400 === 0) {
			await batch.commit();
			batch = fs.batch();
		}
	}
	if (n % 400 !== 0) await batch.commit();
	return n;
}

async function deleteSectionKeys(docId, ids) {
	if (!ids.length) return 0;
	const ref = fs.collection('sections_unified').doc(docId);
	let n = 0;
	let updates = {};
	for (const id of ids) {
		updates[id] = FieldValue.delete();
		n++;
		if (n % 400 === 0) {
			await ref.update(updates);
			updates = {};
		}
	}
	if (Object.keys(updates).length) await ref.update(updates);
	return n;
}

function printBuckets(title, buckets) {
	console.log(`\n${title}`);
	const entries = Object.entries(buckets).sort((a, b) => b[1] - a[1]);
	for (const [k, v] of entries) {
		const mark = isFetchedProvider(k) || isEngineCreated(k) ? '  🗑️ ' : '  ✅ ';
		console.log(`${mark}${String(k).padEnd(28)} : ${v}`);
	}
}

async function main() {
	console.log(`[purge] المشروع: ${PROJECT_ID} | قاعدة: ${FIRESTORE_DB_ID}`);
	console.log(`[purge] الوضع: ${EXECUTE ? '🔴 حذف فعليّ' : '🟢 عدّ فقط (dry-run)'}`);

	// ── المحتوى ──────────────────────────────────────────────────────────
	let totalToDelete = 0;
	const contentDeletes = [];
	for (const coll of CONTENT_COLLECTIONS) {
		const r = await scanContent(coll);
		printBuckets(`📁 ${coll} (إجمالي ${r.total}) — التوزيع حسب __provider:`, r.byProvider);
		console.log(`   → للحذف من ${coll}: ${r.toDelete.length}`);
		totalToDelete += r.toDelete.length;
		contentDeletes.push({ coll, refs: r.toDelete });
	}

	// ── الأقسام ──────────────────────────────────────────────────────────
	const sections = await scanSections();
	let totalEngineSections = 0;
	for (const docId of ['main', 'sub', 'secondary']) {
		const s = sections[docId];
		printBuckets(
			`🗂️ sections_unified/${docId} (إجمالي ${s.total}) — حسب __createdBy:`,
			s.byCreator
		);
		console.log(`   → أقسام من المحرّكات في ${docId}: ${s.engineIds.length}`);
		totalEngineSections += s.engineIds.length;
	}

	console.log('\n══════════════════════════════════════════════');
	console.log(`الإجمالي للحذف: ${totalToDelete} وثيقة محتوى + ${totalEngineSections} قسم.`);
	console.log('══════════════════════════════════════════════');

	if (!EXECUTE) {
		console.log('\n🟢 عدّ فقط — لم يُحذف شيء. للتنفيذ: أضف --execute');
		process.exit(0);
	}

	// ── تنفيذ الحذف ──────────────────────────────────────────────────────
	console.log('\n🔴 بدء الحذف الفعليّ...');
	let deletedContent = 0;
	for (const { coll, refs } of contentDeletes) {
		const n = await deleteRefs(refs);
		deletedContent += n;
		console.log(`   حُذف من ${coll}: ${n}`);
	}
	let deletedSections = 0;
	for (const docId of ['secondary', 'sub', 'main']) {
		const n = await deleteSectionKeys(docId, sections[docId].engineIds);
		deletedSections += n;
		console.log(`   حُذف أقسام ${docId}: ${n}`);
	}
	console.log(`\n✅ اكتمل: ${deletedContent} وثيقة محتوى + ${deletedSections} قسم. (RTDB لم يُمَسّ.)`);
	process.exit(0);
}

main().catch((e) => {
	console.error('[purge] فشل:', e?.stack || e?.message || e);
	process.exit(1);
});
