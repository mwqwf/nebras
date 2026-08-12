/**
 * تجميع الشعبيّة الأسبوعيّة — يكتب aggregates_popular/top_weekly.
 * يُستدعى من POST /api/admin/aggregates/popularity (Admin SDK).
 */
import { getNebrasFirestoreAdmin } from '$lib/server/firebaseAdmin.js';

const FILES = 'content_unified_files';
const AGG_DOC = 'aggregates_popular/top_weekly';

/**
 * @param {{ limit?: number }} opts
 * @returns {Promise<{ ids: string[], scores: Record<string, number>, scanned: number }>}
 */
export async function runAggregatePopularity({ limit = 50 } = {}) {
	const db = getNebrasFirestoreAdmin();
	const now = Date.now();
	const weekMs = 7 * 24 * 60 * 60 * 1000;
	const monthMs = 30 * 24 * 60 * 60 * 1000;

	const scored = [];

	const scoreRow = (id, data) => {
		const views = Number(data.view_count ?? data.viewCount ?? 0) || 0;
		const plays = Number(data.play_count ?? data.playCount ?? 0) || 0;
		const score7 =
			Number(data.popularity_score_7d ?? data.popularityScore7d ?? 0) ||
			views * 3 + plays * 2;
		const lastPlayed = data.last_played_at?.toDate?.() ?? null;
		let trend = score7;
		if (lastPlayed) {
			const age = now - lastPlayed.getTime();
			if (age > weekMs && age <= monthMs) trend += views;
		}
		scored.push({ id: String(id), score: trend, views, plays });
	};

	const filesSnap = await db.collection(FILES).get();

	for (const doc of filesSnap.docs) scoreRow(doc.id, doc.data());

	scored.sort((a, b) => b.score - a.score);
	const top = scored.slice(0, Math.max(1, limit));
	const ids = top.map((r) => r.id);
	const scores = Object.fromEntries(top.map((r) => [r.id, r.score]));

	await db.doc(AGG_DOC).set(
		{
			ids,
			scores,
			updated_at: new Date(),
			scanned: scored.length
		},
		{ merge: true }
	);

	return { ids, scores, scanned: scored.length };
}
