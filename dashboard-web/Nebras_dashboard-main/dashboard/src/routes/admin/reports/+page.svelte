<!--
  بلاغات المحتوى — واجهة الإشراف الخاصّة بالمالك.
  تعرض المحتوى المُبلَّغ عنه + سبب البلاغ + تصنيفه، مع زرّ حذف فعليّ
  للمحتوى المخالف وزرّ تجاهل للبلاغ الكاذب.
-->
<script>
	import { onMount } from 'svelte';
	import { listReports, deleteReportedContent, dismissReport } from '$lib/api/moderation.js';

	let reports = $state([]);
	let loading = $state(true);
	let error = $state('');
	let busyId = $state('');

	const REASONS = {
		copyright: { label: 'ملكية فكرية / حقوق نشر', color: '#b45309', bg: '#fef3c7' },
		sexual: { label: 'محتوى جنسيّ صريح', color: '#9d174d', bg: '#fce7f3' },
		child_safety: { label: 'يضرّ بالأطفال', color: '#7f1d1d', bg: '#fee2e2' },
		violence: { label: 'عنف', color: '#9a3412', bg: '#ffedd5' },
		terrorism: { label: 'إرهاب / تطرّف', color: '#7f1d1d', bg: '#fee2e2' },
		other: { label: 'أخرى', color: '#374151', bg: '#f3f4f6' }
	};

	function reasonMeta(code) {
		return REASONS[code] || REASONS.other;
	}

	async function loadReports() {
		loading = true;
		error = '';
		try {
			const data = await listReports();
			reports = data.items || [];
		} catch (e) {
			error = e?.status === 403 ? 'هذه الصفحة للمالك فقط.' : (e?.message || 'تعذّر تحميل البلاغات.');
			reports = [];
		} finally {
			loading = false;
		}
	}

	async function act(report, action) {
		if (action === 'delete') {
			const ok = confirm(
				`هل تريد حذف هذا المحتوى نهائيّاً؟\n\n"${report.contentTitle || report.contentId}"\n\nلا يمكن التراجع.`
			);
			if (!ok) return;
		}
		busyId = report.id;
		try {
			if (action === 'delete') {
				await deleteReportedContent({
					reportId: report.id,
					contentId: report.contentId,
					contentType: report.contentType
				});
			} else {
				await dismissReport({ reportId: report.id, contentId: report.contentId });
			}
			// أزل البلاغ من القائمة محليّاً.
			reports = reports.filter((r) => r.id !== report.id);
		} catch (e) {
			alert(e?.message || 'فشل تنفيذ الإجراء. حاول مجدّداً.');
		} finally {
			busyId = '';
		}
	}

	function fmtDate(ms) {
		if (!ms) return '';
		try {
			return new Date(ms).toLocaleString('ar');
		} catch {
			return '';
		}
	}

	onMount(loadReports);
</script>

<div class="reports-page">
	<header class="head">
		<h1>بلاغات المحتوى</h1>
		<button class="refresh" onclick={loadReports} disabled={loading}>تحديث</button>
	</header>

	<p class="hint">
		راجع كلّ بلاغ ثمّ احذف المحتوى إن كان مخالفاً فعلاً، أو تجاهل البلاغ إن كان كاذباً.
	</p>

	{#if loading}
		<p class="state">جارٍ التحميل…</p>
	{:else if error}
		<p class="state err">{error}</p>
	{:else if reports.length === 0}
		<p class="state">لا توجد بلاغات معلّقة. ✅</p>
	{:else}
		<ul class="list">
			{#each reports as r (r.id)}
				{@const meta = reasonMeta(r.reasonCode)}
				<li class="card">
					<div class="card-top">
						<span class="badge" style="color:{meta.color};background:{meta.bg}">{meta.label}</span>
						<span class="type">{r.contentType || '—'}</span>
						<span class="date">{fmtDate(r.createdAtMs)}</span>
					</div>
					<h3 class="title">{r.contentTitle || '(بدون عنوان)'}</h3>
					<p class="cid">المعرّف: <code>{r.contentId || '—'}</code></p>
					{#if r.sourceUrl}
						<p class="src"><a href={r.sourceUrl} target="_blank" rel="noreferrer">عرض المصدر ↗</a></p>
					{/if}
					{#if r.note}
						<p class="note">ملاحظة المُبلِّغ: {r.note}</p>
					{/if}
					<div class="actions">
						<button
							class="del"
							onclick={() => act(r, 'delete')}
							disabled={busyId === r.id}
						>
							{busyId === r.id ? '…' : 'حذف المحتوى'}
						</button>
						<button
							class="dismiss"
							onclick={() => act(r, 'dismiss')}
							disabled={busyId === r.id}
						>
							تجاهل البلاغ
						</button>
					</div>
				</li>
			{/each}
		</ul>
	{/if}
</div>

<style>
	.reports-page {
		max-width: 880px;
		margin: 0 auto;
		padding: 24px 16px;
	}
	.head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		margin-bottom: 8px;
	}
	.head h1 {
		font-size: 1.5rem;
		font-weight: 700;
	}
	.refresh {
		border: 1px solid #d1d5db;
		border-radius: 8px;
		padding: 6px 14px;
		background: #fff;
		cursor: pointer;
	}
	.hint {
		color: #6b7280;
		margin-bottom: 16px;
	}
	.state {
		padding: 32px;
		text-align: center;
		color: #6b7280;
	}
	.state.err {
		color: #b91c1c;
	}
	.list {
		display: flex;
		flex-direction: column;
		gap: 14px;
		list-style: none;
		padding: 0;
		margin: 0;
	}
	.card {
		border: 1px solid #e5e7eb;
		border-radius: 14px;
		padding: 16px;
		background: #fff;
	}
	.card-top {
		display: flex;
		align-items: center;
		gap: 10px;
		flex-wrap: wrap;
		margin-bottom: 8px;
	}
	.badge {
		font-size: 0.8rem;
		font-weight: 700;
		padding: 3px 10px;
		border-radius: 999px;
	}
	.type {
		font-size: 0.8rem;
		color: #6b7280;
		text-transform: uppercase;
	}
	.date {
		font-size: 0.78rem;
		color: #9ca3af;
		margin-inline-start: auto;
	}
	.title {
		font-size: 1.05rem;
		font-weight: 700;
		margin: 4px 0;
	}
	.cid,
	.src,
	.note {
		font-size: 0.85rem;
		color: #4b5563;
		margin: 2px 0;
	}
	.note {
		background: #f9fafb;
		padding: 8px 10px;
		border-radius: 8px;
		margin-top: 6px;
	}
	.actions {
		display: flex;
		gap: 10px;
		margin-top: 14px;
	}
	.del {
		background: #dc2626;
		color: #fff;
		border: none;
		border-radius: 8px;
		padding: 8px 18px;
		font-weight: 600;
		cursor: pointer;
	}
	.del:disabled {
		opacity: 0.6;
		cursor: default;
	}
	.dismiss {
		background: #fff;
		color: #374151;
		border: 1px solid #d1d5db;
		border-radius: 8px;
		padding: 8px 18px;
		cursor: pointer;
	}
</style>
