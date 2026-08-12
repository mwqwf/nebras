/**
 * استخراج عدّادات المشاهدة من صفّ Firestore الموحّد (جذر أو metadata).
 * يُستخدم في قوائم الملفّات/يوتيوب — راجع DASHBOARD_TODO.md.
 */

/** @param {Record<string, unknown> | null | undefined} row */
export function pickEngagementStats(row) {
	if (!row || typeof row !== 'object') {
		return { view_count: 0, play_count: 0, complete_count: 0 };
	}
	const meta = /** @type {Record<string, unknown>} */ (row.metadata || {});
	const num = (v) => {
		const n = Number(v);
		return Number.isFinite(n) && n > 0 ? Math.floor(n) : 0;
	};
	return {
		view_count: num(row.view_count ?? row.viewCount ?? meta.view_count ?? meta.viewCount),
		play_count: num(row.play_count ?? row.playCount ?? meta.play_count ?? meta.playCount),
		complete_count: num(
			row.complete_count ?? row.completeCount ?? meta.complete_count ?? meta.completeCount
		)
	};
}

/** @param {{ view_count?: number; play_count?: number; complete_count?: number }} stats */
export function hasEngagementSignal(stats) {
	return (stats?.view_count ?? 0) > 0 || (stats?.play_count ?? 0) > 0 || (stats?.complete_count ?? 0) > 0;
}
