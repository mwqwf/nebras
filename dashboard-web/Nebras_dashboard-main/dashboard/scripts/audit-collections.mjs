/**
 * audit-collections.mjs — جرد شامل: كل مجموعات Firestore + عدد وثائقها،
 * وتوزيع __provider في مجموعات المحتوى. للتأكّد ألّا يبقى محتوى مجلوب آلياً
 * في أيّ مجموعة (بما فيها content_unified_youtube وأيّ مجموعة غير متوقّعة).
 *
 *   node scripts/audit-collections.mjs
 */
import admin from 'firebase-admin';
import { getFirestore } from 'firebase-admin/firestore';
import { resolveServiceAccount } from './load-admin-credential.mjs';
import { loadDashboardEnv } from './load-env.mjs';

loadDashboardEnv();

const FIRESTORE_DB_ID = process.env.NEBRAS_FIRESTORE_DATABASE_ID?.trim() || 'default';
const { credentials } = resolveServiceAccount();
const app = admin.initializeApp({ credential: admin.credential.cert(credentials) });
const fs = getFirestore(app, FIRESTORE_DB_ID);

async function main() {
	const cols = await fs.listCollections();
	console.log(`\n📚 عدد المجموعات العليا: ${cols.length}\n`);

	for (const c of cols) {
		let count = 0;
		try {
			const agg = await c.count().get();
			count = agg.data().count;
		} catch {
			const s = await c.select().get();
			count = s.size;
		}
		console.log(`• ${c.id.padEnd(34)} : ${count}`);

		// لو المجموعة فيها وثائق، نفحص توزيع __provider (عيّنة كاملة عبر select).
		if (count > 0 && count <= 60000) {
			try {
				const snap = await c.select('__provider', '__createdBy', 'source_type').get();
				const buckets = {};
				for (const d of snap.docs) {
					const p =
						d.data()?.__provider ?? d.data()?.__createdBy ?? d.data()?.source_type ?? null;
					if (p == null) continue;
					buckets[p] = (buckets[p] || 0) + 1;
				}
				const keys = Object.keys(buckets);
				if (keys.length) {
					for (const k of keys.sort((a, b) => buckets[b] - buckets[a])) {
						const susp = /archive|noor|hindawi|crawl|mshcat|oldapp|youtube|ingest|engine|bot/i.test(
							String(k)
						);
						console.log(`     ${susp ? '🚨' : '  '} __provider/__createdBy: ${k} → ${buckets[k]}`);
					}
				}
			} catch (e) {
				console.log(`     (تعذّر فحص الوسوم: ${e?.message || e})`);
			}
		}
	}
	console.log('\n✅ انتهى الجرد.');
	process.exit(0);
}

main().catch((e) => {
	console.error('[audit] فشل:', e?.stack || e?.message || e);
	process.exit(1);
});
