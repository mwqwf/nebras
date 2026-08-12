/**
 * إعادة ضبط محتوى هنداوي: يحذف كل ما رفعه محرّك هنداوي (__provider==='hindawi')
 * من content_unified_files و dashboard_uploads، ويصفّر registry/cursor في RTDB،
 * ويزيل أقسام «مؤسسة هنداوي»/«كتب عامة» القديمة (التصنيف الخطأ السابق).
 * بعدها يعيد المحرّك جلب الكتب ضمن تصنيفاتها الحقيقيّة.
 *
 *   node scripts/hindawi-reset.mjs
 */
import admin from 'firebase-admin';
import { getFirestore } from 'firebase-admin/firestore';
import { resolveServiceAccount } from './load-admin-credential.mjs';
import { loadDashboardEnv } from './load-env.mjs';

loadDashboardEnv();

const PROJECT_ID =
	process.env.VITE_FIREBASE_PROJECT_ID?.trim() || process.env.FIREBASE_PROJECT_ID?.trim() || 'nebras-9118c';
const DB_URL =
	process.env.VITE_FIREBASE_DATABASE_URL?.trim() ||
	process.env.FIREBASE_DATABASE_URL?.trim() ||
	`https://${PROJECT_ID}-default-rtdb.firebaseio.com`;

const FIRESTORE_DB_ID = process.env.NEBRAS_FIRESTORE_DATABASE_ID?.trim() || 'default';

const { credentials } = resolveServiceAccount();
const app = admin.initializeApp({ credential: admin.credential.cert(credentials), databaseURL: DB_URL });

// قاعدة Firestore مسمّاة `default` (لا `(default)`) — نمرّر المعرّف صراحةً.
const fs = getFirestore(app, FIRESTORE_DB_ID);
const rtdb = admin.database();

async function deleteProviderDocs(collection) {
	const snap = await fs.collection(collection).where('__provider', '==', 'hindawi').get();
	let n = 0;
	let batch = fs.batch();
	for (const doc of snap.docs) {
		batch.delete(doc.ref);
		n++;
		if (n % 400 === 0) { await batch.commit(); batch = fs.batch(); }
	}
	if (n % 400 !== 0) await batch.commit();
	return n;
}

async function removeOldHindawiSections() {
	const ref = fs.collection('sections_unified');
	const [mainSnap, subSnap] = await Promise.all([ref.doc('main').get(), ref.doc('sub').get()]);
	const mains = mainSnap.exists ? mainSnap.data() || {} : {};
	const subs = subSnap.exists ? subSnap.data() || {} : {};
	const FieldValue = admin.firestore.FieldValue;

	// أقسام رئيسيّة باسم «مؤسسة هنداوي» (الدمج القديم).
	const mainUpdates = {};
	const removedMainIds = new Set();
	for (const [id, rec] of Object.entries(mains)) {
		if (String(rec?.name || '').trim() === 'مؤسسة هنداوي') { mainUpdates[id] = FieldValue.delete(); removedMainIds.add(String(id)); }
	}
	// أقسام فرعيّة «كتب عامة» أو يتيمة تحت main محذوف.
	const subUpdates = {};
	for (const [id, rec] of Object.entries(subs)) {
		const parent = String(rec?.main_section ?? '');
		if (String(rec?.name || '').trim() === 'كتب عامة' || removedMainIds.has(parent)) {
			subUpdates[id] = FieldValue.delete();
		}
	}
	if (Object.keys(mainUpdates).length) await ref.doc('main').update(mainUpdates);
	if (Object.keys(subUpdates).length) await ref.doc('sub').update(subUpdates);
	return { mains: Object.keys(mainUpdates).length, subs: Object.keys(subUpdates).length };
}

async function main() {
	console.log('[hindawi-reset] مشروع:', PROJECT_ID);
	const files = await deleteProviderDocs('content_unified_files');
	const uploads = await deleteProviderDocs('dashboard_uploads');
	const sections = await removeOldHindawiSections();
	await rtdb.ref('hindawi_library_registry').remove().catch(() => {});
	await rtdb.ref('hindawi_library_failures').remove().catch(() => {});
	await rtdb.ref('hindawi_library_engine/cursor').remove().catch(() => {});
	await rtdb.ref('hindawi_library_engine/stats').set({
		totalFetched: 0, sectionsCreated: 0, runsCount: 0, lastRunAt: null, lastError: 'reset_for_categories', consecutiveEmptyRuns: 0
	}).catch(() => {});

	console.log(`[hindawi-reset] ✅ حُذف: ${files} ملف + ${uploads} مرآة + أقسام(${sections.mains} رئيسي/${sections.subs} فرعي). صُفّر السجلّ والمؤشّر.`);
	process.exit(0);
}

main().catch((e) => { console.error('[hindawi-reset] فشل:', e?.message || e); process.exit(1); });
