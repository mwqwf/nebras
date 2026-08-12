<script>
	import { onMount, onDestroy } from 'svelte';
	import {
		getCrawl4aiStatus,
		crawl4aiControl,
		enqueueCrawl4aiUrl,
		getCrawl4aiJobs
	} from '$lib/api/crawl4ai.js';

	let loading = $state(true);
	let busy = $state(false);
	let error = $state(/** @type {string|null} */ (null));
	let status = $state(/** @type {any} */ (null));
	let jobs = $state(/** @type {any} */ (null));
	let urlInput = $state('https://example.com');
	let pollTimer = /** @type {ReturnType<typeof setInterval>|null} */ (null);

	async function refresh() {
		try {
			const [s, j] = await Promise.all([getCrawl4aiStatus(), getCrawl4aiJobs(80)]);
			status = s;
			jobs = j;
			error = null;
		} catch (e) {
			error = e?.message || String(e);
		} finally {
			loading = false;
		}
	}

	function startPolling() {
		if (pollTimer) clearInterval(pollTimer);
		pollTimer = setInterval(() => {
			refresh().catch(() => {});
		}, 4000);
	}

	onMount(async () => {
		await refresh();
		startPolling();
	});

	onDestroy(() => {
		if (pollTimer) clearInterval(pollTimer);
	});

	async function handleStart() {
		busy = true;
		try {
			status = await crawl4aiControl('start');
			error = null;
			startPolling();
		} catch (e) {
			error = e?.message || String(e);
		} finally {
			busy = false;
		}
	}

	async function handleStop() {
		busy = true;
		try {
			status = await crawl4aiControl('stop');
			error = null;
		} catch (e) {
			error = e?.message || String(e);
		} finally {
			busy = false;
		}
	}

	async function handleEnqueue() {
		const u = String(urlInput || '').trim();
		if (!u) return;
		busy = true;
		try {
			await enqueueCrawl4aiUrl(u);
			error = null;
			await refresh();
		} catch (e) {
			error = e?.message || String(e);
		} finally {
			busy = false;
		}
	}

	let workerOn = $derived(Boolean(status?.worker_enabled));
	let stats = $derived(status?.stats || {});
</script>

<svelte:head>
	<title>Crawl4AI — Nebras</title>
</svelte:head>

<div class="page-container">
	<div class="page-header">
		<div>
			<h1 class="page-title">Crawl4AI</h1>
			<p class="page-desc">
				تشغيل خدمة الزحف كعملية Python منفصلة، والتحكم بها من لوحة التحكم (للمالك فقط). تأكد من
				تشغيل السكربت داخل مجلد <code>crawl4ai_service</code> ومن ضبط
				<code>CRAWL4AI_SERVICE_URL</code> في ملف <code>.env</code> للوحة.
			</p>
		</div>
	</div>

	{#if loading}
		<div class="loading-state">
			<span class="spinner-lg"></span>
			<p>جاري التحميل…</p>
		</div>
	{:else}
		{#if error}
			<div class="alert alert-error">{error}</div>
		{/if}

		<div class="panel">
			<div class="panel-header">
				<h2>الحالة والتحكم</h2>
				<div class="badge" class:on={workerOn} class:off={!workerOn}>
					{workerOn ? 'المعالج يعمل' : 'متوقف'}
				</div>
			</div>

			<div class="actions">
				<button class="btn btn-primary" type="button" disabled={busy} onclick={handleStart}>
					بدء المعالج
				</button>
				<button class="btn btn-danger" type="button" disabled={busy} onclick={handleStop}>
					إيقاف المعالج
				</button>
				<button class="btn btn-ghost" type="button" disabled={busy} onclick={refresh}>
					تحديث
				</button>
			</div>

			<div class="stats-grid">
				<div class="stat">
					<p class="stat-label">صفحات ناجحة</p>
					<p class="stat-value">{stats.urls_ok ?? 0}</p>
				</div>
				<div class="stat">
					<p class="stat-label">فاشلة</p>
					<p class="stat-value">{stats.urls_failed ?? 0}</p>
				</div>
				<div class="stat">
					<p class="stat-label">عمق الطابور</p>
					<p class="stat-value">{status?.queue_depth ?? 0}</p>
				</div>
				<div class="stat">
					<p class="stat-label">مهام مسجّلة</p>
					<p class="stat-value">{stats.jobs_total ?? 0}</p>
				</div>
			</div>

			{#if status?.current_job}
				<p class="muted">
					جاري الآن: <span class="mono">{status.current_job.url}</span>
				</p>
			{/if}
		</div>

		<div class="panel">
			<h2>إضافة رابط للطابور</h2>
			<p class="muted small">
				لن يُقبل الرابط إلا عندما يكون المعالج في وضع التشغيل. النتائج تُحفظ كإحصاءات وأحجام نصوص
				داخل الخدمة (Markdown / HTML) وليس داخل Firebase.
			</p>
			<div class="row">
				<input class="input" type="url" bind:value={urlInput} placeholder="https://…" />
				<button class="btn btn-primary" type="button" disabled={busy || !workerOn} onclick={handleEnqueue}>
					إرسال للزحف
				</button>
			</div>
		</div>

		<div class="panel">
			<h2>آخر المهام</h2>
			{#if !jobs?.recent?.length}
				<p class="muted">لا توجد مهام مكتملة بعد.</p>
			{:else}
				<div class="table-wrap">
					<table class="table">
						<thead>
							<tr>
								<th>الحالة</th>
								<th>الرابط</th>
								<th>Markdown</th>
								<th>HTML</th>
								<th>خطأ</th>
							</tr>
						</thead>
						<tbody>
							{#each jobs.recent as j}
								<tr>
									<td><span class="pill">{j.status}</span></td>
									<td class="mono small">{j.url}</td>
									<td>{j.markdown_chars ?? '—'}</td>
									<td>{j.html_chars ?? '—'}</td>
									<td class="err">{j.error || ''}</td>
								</tr>
							{/each}
						</tbody>
					</table>
				</div>
			{/if}
		</div>
	{/if}
</div>

<style>
	.page-container {
		display: flex;
		flex-direction: column;
		gap: 1.25rem;
	}

	.page-header {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: 1rem;
	}

	.page-title {
		font-size: 1.5rem;
		font-weight: 700;
		color: var(--color-surface-100);
		letter-spacing: -0.02em;
	}

	.page-desc {
		font-size: 0.8125rem;
		color: var(--color-surface-400);
		margin-top: 0.25rem;
		line-height: 1.5;
	}

	.page-desc code {
		font-size: 0.75rem;
		background: var(--color-surface-900);
		padding: 0.1rem 0.35rem;
		border-radius: 6px;
		border: 1px solid var(--color-surface-700);
	}

	.panel {
		background: var(--color-surface-800);
		border: 1px solid var(--color-surface-700);
		border-radius: 12px;
		padding: 1.25rem;
		display: flex;
		flex-direction: column;
		gap: 0.75rem;
	}

	.panel h2 {
		font-size: 1.05rem;
		font-weight: 600;
		color: var(--color-surface-50);
		margin: 0;
	}

	.panel-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 0.75rem;
	}

	.badge {
		font-size: 0.75rem;
		font-weight: 700;
		padding: 0.25rem 0.6rem;
		border-radius: 999px;
		border: 1px solid var(--color-surface-600);
		color: var(--color-surface-300);
	}
	.badge.on {
		border-color: rgba(16, 185, 129, 0.45);
		color: #6ee7b7;
		background: rgba(16, 185, 129, 0.08);
	}
	.badge.off {
		border-color: rgba(248, 113, 113, 0.35);
		color: #fecaca;
		background: rgba(239, 68, 68, 0.08);
	}

	.actions {
		display: flex;
		flex-wrap: wrap;
		gap: 0.5rem;
	}

	.btn {
		border-radius: 10px;
		padding: 0.55rem 0.9rem;
		font-size: 0.8125rem;
		font-weight: 600;
		border: 1px solid var(--color-surface-600);
		background: var(--color-surface-900);
		color: var(--color-surface-100);
		cursor: pointer;
	}
	.btn:disabled {
		opacity: 0.55;
		cursor: not-allowed;
	}
	.btn-primary {
		background: var(--color-primary-600);
		border-color: var(--color-primary-500);
		color: #fff;
	}
	.btn-danger {
		background: rgba(220, 38, 38, 0.15);
		border-color: rgba(220, 38, 38, 0.45);
		color: #fecaca;
	}
	.btn-ghost {
		background: transparent;
	}

	.stats-grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
		gap: 0.75rem;
		margin-top: 0.25rem;
	}

	.stat {
		background: var(--color-surface-900);
		border: 1px solid var(--color-surface-700);
		border-radius: 10px;
		padding: 0.75rem;
	}
	.stat-label {
		font-size: 0.75rem;
		color: var(--color-surface-400);
		margin: 0 0 0.25rem 0;
	}
	.stat-value {
		font-size: 1.25rem;
		font-weight: 800;
		color: var(--color-surface-50);
		margin: 0;
	}

	.muted {
		color: var(--color-surface-400);
		font-size: 0.8125rem;
		margin: 0;
	}
	.muted.small {
		font-size: 0.75rem;
	}
	.mono {
		font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, 'Liberation Mono', 'Courier New',
			monospace;
		font-size: 0.75rem;
		word-break: break-all;
	}

	.row {
		display: flex;
		flex-wrap: wrap;
		gap: 0.5rem;
		align-items: center;
	}

	.input {
		flex: 1;
		min-width: 220px;
		border-radius: 10px;
		border: 1px solid var(--color-surface-700);
		background: var(--color-surface-900);
		color: var(--color-surface-100);
		padding: 0.55rem 0.75rem;
		font-size: 0.8125rem;
		outline: none;
	}
	.input:focus {
		border-color: var(--color-primary-600);
		box-shadow: 0 0 0 3px rgba(5, 150, 105, 0.12);
	}

	.table-wrap {
		overflow: auto;
		border: 1px solid var(--color-surface-700);
		border-radius: 10px;
	}
	.table {
		width: 100%;
		border-collapse: collapse;
		font-size: 0.78rem;
	}
	.table th,
	.table td {
		padding: 0.55rem 0.65rem;
		border-bottom: 1px solid var(--color-surface-700);
		vertical-align: top;
		text-align: start;
	}
	.table th {
		color: var(--color-surface-300);
		font-weight: 600;
		background: var(--color-surface-900);
		position: sticky;
		top: 0;
	}
	.pill {
		display: inline-flex;
		padding: 0.1rem 0.45rem;
		border-radius: 999px;
		border: 1px solid var(--color-surface-600);
		color: var(--color-surface-200);
		font-size: 0.72rem;
		font-weight: 700;
	}
	.err {
		color: #fecaca;
		max-width: 320px;
		word-break: break-word;
	}
</style>
