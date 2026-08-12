/**
 * audit-rtdb.mjs — جرد بقايا محرّكات الجلب في Realtime Database
 * (سجلّات/مؤشّرات/قوائم سوداء تركناها بعد التطهير).
 *
 *   node scripts/audit-rtdb.mjs             → عَدّ فقط
 *   node scripts/audit-rtdb.mjs --execute   → حذف مسارات المحرّكات
 */
import admin from 'firebase-admin';
import { resolveServiceAccount } from './load-admin-credential.mjs';
import { loadDashboardEnv } from './load-env.mjs';

loadDashboardEnv();

const EXECUTE = process.argv.includes('--execute');
const PROJECT_ID =
	process.env.VITE_FIREBASE_PROJECT_ID?.trim() || process.env.FIREBASE_PROJECT_ID?.trim() || 'nebras-9118c';
const DB_URL =
	process.env.VITE_FIREBASE_DATABASE_URL?.trim() ||
	process.env.FIREBASE_DATABASE_URL?.trim() ||
	`https://${PROJECT_ID}-default-rtdb.firebaseio.com`;

const { credentials } = resolveServiceAccount();
const app = admin.initializeApp({ credential: admin.credential.cert(credentials), databaseURL: DB_URL });
const rtdb = admin.database();

/** مسارات تخصّ محرّكات الجلب فقط (لا نلمس dashboard_users ولا الدردشة). */
const ENGINE_KEY_RE = /(noor|hindawi|internet_archive|ia_library|archive)/i;

async function main() {
	console.log(`[rtdb] ${DB_URL}`);
	console.log(`[rtdb] الوضع: ${EXECUTE ? '🔴 حذف' : '🟢 عدّ فقط'}\n`);

	const rootSnap = await rtdb.ref('/').once('value');
	const root = rootSnap.val() || {};
	const keys = Object.keys(root);
	console.log(`📚 مفاتيح الجذر (${keys.length}):`);

	const targets = [];
	for (const k of keys) {
		const v = root[k];
		const n = v && typeof v === 'object' ? Object.keys(v).length : 1;
		const isEngine = ENGINE_KEY_RE.test(k);
		console.log(`  ${isEngine ? '🗑️' : '✅'} ${k.padEnd(34)} : ${n} مفتاح فرعي`);
		if (isEngine) targets.push(k);
	}

	console.log(`\n══════════════════════════════════════`);
	console.log(`بقايا محرّكات للحذف: ${targets.length} مسار`);
	console.log(`══════════════════════════════════════`);

	if (!EXECUTE) {
		console.log('\n🟢 عدّ فقط. للتنفيذ: --execute');
		process.exit(0);
	}

	for (const k of targets) {
		await rtdb.ref(k).remove();
		console.log(`   حُذف: /${k}`);
	}
	console.log(`\n✅ حُذفت ${targets.length} بقيّة من RTDB.`);
	process.exit(0);
}

main().catch((e) => {
	console.error('[rtdb] فشل:', e?.stack || e?.message || e);
	process.exit(1);
});
