<!--
  Internet Archive Engine — Admin Dashboard

  هذه الصفحة للمراقبة (read-only افتراضياً). المحرّك يعمل تلقائياً بدون
  ضغط أي زر — تكفي زيارة الصفحة ليُقلِع عبر autoBootIfNeeded في
  hooks.server.js + Vercel Cron + GitHub Action.

  الأزرار الإضافية موجودة فقط لتشخيص يدوي طارئ (Diagnose, Tick Now,
  Bootstrap, Factory Reset).
-->
<script>
	import { onDestroy, onMount } from 'svelte';
	import {
		getEngineStatus,
		bootstrapEngine,
		diagnoseEngine,
		runOneTick,
		resetEngine,
		startEngine,
		stopEngine
	} from '$lib/api/internetArchive.js';

	let status = $state(null);
	let loadingStatus = $state(true);
	let statusError = $state('');

	let actionInFlight = $state(''); // '' | 'bootstrap' | 'diagnose' | 'tick' | 'reset' | 'factory' | 'start' | 'stop'
	let actionResult = $state(null);
	let actionError = $state('');

	let diagnoseReport = $state(null);
	let autoRefreshTimer = null;

	const AUTO_REFRESH_MS = 15000;

	async function refreshStatus() {
		try {
			loadingStatus = true;
			statusError = '';
			const r = await getEngineStatus();
			if (r?.ok) {
				status = r.status;
			} else {
				statusError = r?.error || 'حالة غير معروفة';
			}
		} catch (err) {
			statusError = err?.message || String(err);
		} finally {
			loadingStatus = false;
		}
	}

	async function runAction(kind, fn) {
		if (actionInFlight) return;
		actionInFlight = kind;
		actionError = '';
		actionResult = null;
		try {
			actionResult = await fn();
		} catch (err) {
			actionError = err?.message || String(err);
		} finally {
			actionInFlight = '';
			refreshStatus();
		}
	}

	function onBootstrap() {
		runAction('bootstrap', bootstrapEngine);
	}
	function onTick() {
		runAction('tick', runOneTick);
	}
	function onStart() {
		runAction('start', startEngine);
	}
	function onStop() {
		runAction('stop', stopEngine);
	}
	function onResetCursor() {
		runAction('reset', () => resetEngine('cursor'));
	}
	async function onDiagnose() {
		if (actionInFlight) return;
		actionInFlight = 'diagnose';
		actionError = '';
		diagnoseReport = null;
		try {
			diagnoseReport = await diagnoseEngine();
		} catch (err) {
			actionError = err?.message || String(err);
		} finally {
			actionInFlight = '';
			refreshStatus();
		}
	}

	function fmtDate(ts) {
		if (!ts) return '—';
		try {
			return new Date(ts).toLocaleString('ar-EG', {
				dateStyle: 'short',
				timeStyle: 'medium'
			});
		} catch {
			return String(ts);
		}
	}

	function logColor(level) {
		switch (level) {
			case 'error':
				return 'text-red-700 bg-red-50 border-red-200';
			case 'warn':
				return 'text-amber-700 bg-amber-50 border-amber-200';
			case 'success':
				return 'text-green-700 bg-green-50 border-green-200';
			default:
				return 'text-slate-700 bg-slate-50 border-slate-200';
		}
	}

	onMount(() => {
		refreshStatus();
		autoRefreshTimer = setInterval(refreshStatus, AUTO_REFRESH_MS);
	});

	onDestroy(() => {
		if (autoRefreshTimer) clearInterval(autoRefreshTimer);
	});
</script>

<svelte:head>
	<title>محرّك Internet Archive — Nebras Admin</title>
</svelte:head>

<div class="mx-auto max-w-6xl space-y-6 p-4" dir="rtl">
	<header class="space-y-1">
		<h1 class="text-2xl font-bold text-slate-900">محرّك Internet Archive</h1>
		<p class="text-sm text-slate-600">
			يعمل بالخلفية تلقائياً — لا حاجة لأي تدخّل يدوي. الأزرار أدناه للتشخيص الطارئ فقط.
			تحديث تلقائي كل {AUTO_REFRESH_MS / 1000} ثانية.
		</p>
	</header>

	<!-- شريط الإجراءات السريعة (اختيارية) -->
	<section class="flex flex-wrap gap-2 rounded-lg border border-slate-200 bg-white p-3 shadow-sm">
		<button
			class="rounded bg-blue-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-blue-700 disabled:opacity-50"
			disabled={Boolean(actionInFlight)}
			onclick={onBootstrap}
		>
			{actionInFlight === 'bootstrap' ? '⏳ Bootstrap…' : '🚀 Bootstrap (يضع البذور + يطلق tick فوراً)'}
		</button>
		<button
			class="rounded bg-emerald-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-emerald-700 disabled:opacity-50"
			disabled={Boolean(actionInFlight)}
			onclick={onTick}
		>
			{actionInFlight === 'tick' ? '⏳ Tick…' : '⚡ Tick الآن'}
		</button>
		<button
			class="rounded bg-violet-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-violet-700 disabled:opacity-50"
			disabled={Boolean(actionInFlight)}
			onclick={onDiagnose}
		>
			{actionInFlight === 'diagnose' ? '⏳ Diagnose…' : '🔍 Diagnose'}
		</button>
		<button
			class="rounded bg-slate-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-slate-700 disabled:opacity-50"
			disabled={Boolean(actionInFlight)}
			onclick={onStart}
		>
			Start
		</button>
		<button
			class="rounded bg-slate-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-slate-700 disabled:opacity-50"
			disabled={Boolean(actionInFlight)}
			onclick={onStop}
		>
			Stop
		</button>
		<button
			class="rounded bg-amber-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-amber-700 disabled:opacity-50"
			disabled={Boolean(actionInFlight)}
			onclick={onResetCursor}
		>
			Reset Cursor
		</button>
		<button
			class="ml-auto rounded border border-slate-300 px-3 py-1.5 text-sm font-medium text-slate-700 hover:bg-slate-50"
			onclick={refreshStatus}
		>
			🔄 تحديث الحالة
		</button>
	</section>

	{#if actionError}
		<div class="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-800">
			<strong>خطأ في الإجراء:</strong>
			{actionError}
		</div>
	{/if}

	{#if actionResult}
		<details class="rounded-lg border border-green-200 bg-green-50 p-3 text-sm text-green-800">
			<summary class="cursor-pointer font-medium">✅ نتيجة الإجراء</summary>
			<pre class="mt-2 overflow-x-auto whitespace-pre-wrap text-xs">{JSON.stringify(actionResult, null, 2)}</pre>
		</details>
	{/if}

	<!-- إحصائيات -->
	{#if loadingStatus && !status}
		<div class="rounded-lg border border-slate-200 bg-white p-4 text-sm text-slate-600">
			جارٍ التحميل…
		</div>
	{:else if statusError}
		<div class="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-800">
			تعذّر جلب الحالة: {statusError}
		</div>
	{:else if status}
		<section class="grid grid-cols-2 gap-3 md:grid-cols-4">
			<div class="rounded-lg border border-slate-200 bg-white p-3 shadow-sm">
				<div class="text-xs text-slate-500">مُستورد كلّياً</div>
				<div class="text-2xl font-bold text-emerald-600">{status.stats?.totalImported ?? 0}</div>
			</div>
			<div class="rounded-lg border border-slate-200 bg-white p-3 shadow-sm">
				<div class="text-xs text-slate-500">مُتخطّى</div>
				<div class="text-2xl font-bold text-slate-600">{status.stats?.totalSkipped ?? 0}</div>
			</div>
			<div class="rounded-lg border border-slate-200 bg-white p-3 shadow-sm">
				<div class="text-xs text-slate-500">فشل</div>
				<div class="text-2xl font-bold text-red-600">{status.stats?.totalFailed ?? 0}</div>
			</div>
			<div class="rounded-lg border border-slate-200 bg-white p-3 shadow-sm">
				<div class="text-xs text-slate-500">أقسام مُنشَأة</div>
				<div class="text-2xl font-bold text-blue-600">{status.stats?.sectionsCreated ?? 0}</div>
			</div>
		</section>

		<section class="grid gap-3 md:grid-cols-2">
			<div class="rounded-lg border border-slate-200 bg-white p-4 shadow-sm">
				<h2 class="mb-2 font-semibold text-slate-900">الإعدادات</h2>
				<dl class="space-y-1 text-sm">
					<div class="flex justify-between">
						<dt class="text-slate-500">مُفعَّل</dt>
						<dd class="font-medium">
							{status.config?.enabled ? '✅ نعم' : '❌ لا'}
						</dd>
					</div>
					<div class="flex justify-between">
						<dt class="text-slate-500">عدد البذور</dt>
						<dd class="font-medium">{status.config?.seeds?.length ?? 0}</dd>
					</div>
					<div class="flex justify-between">
						<dt class="text-slate-500">batchSize</dt>
						<dd class="font-medium">{status.config?.batchSize ?? '—'}</dd>
					</div>
					<div class="flex justify-between">
						<dt class="text-slate-500">scrapeCount</dt>
						<dd class="font-medium">{status.config?.scrapeCount ?? '—'}</dd>
					</div>
					<div class="flex justify-between">
						<dt class="text-slate-500">tickIntervalMs</dt>
						<dd class="font-medium">{status.config?.tickIntervalMs ?? '—'}</dd>
					</div>
				</dl>
			</div>

			<div class="rounded-lg border border-slate-200 bg-white p-4 shadow-sm">
				<h2 class="mb-2 font-semibold text-slate-900">حالة Tick</h2>
				<dl class="space-y-1 text-sm">
					<div class="flex justify-between">
						<dt class="text-slate-500">يعمل الآن (Node)</dt>
						<dd class="font-medium">{status.processRunning ? '✅' : '❌'}</dd>
					</div>
					<div class="flex justify-between">
						<dt class="text-slate-500">tick جارٍ</dt>
						<dd class="font-medium">{status.currentTickInFlight ? '🔄' : '⏸'}</dd>
					</div>
					<div class="flex justify-between">
						<dt class="text-slate-500">آخر بدء</dt>
						<dd class="font-medium">{fmtDate(status.lastTickStartedAt)}</dd>
					</div>
					<div class="flex justify-between">
						<dt class="text-slate-500">آخر تشغيل</dt>
						<dd class="font-medium">{fmtDate(status.stats?.lastRunAt)}</dd>
					</div>
					<div class="flex justify-between">
						<dt class="text-slate-500">runs</dt>
						<dd class="font-medium">{status.stats?.runsCount ?? 0}</dd>
					</div>
					<div class="flex justify-between">
						<dt class="text-slate-500">runs فارغة متتالية</dt>
						<dd class="font-medium">{status.stats?.consecutiveEmptyRuns ?? 0}</dd>
					</div>
				</dl>
			</div>
		</section>

		<section class="rounded-lg border border-slate-200 bg-white p-4 shadow-sm">
			<h2 class="mb-2 font-semibold text-slate-900">المؤشّر (Cursor)</h2>
			<dl class="grid grid-cols-2 gap-2 text-sm md:grid-cols-4">
				<div>
					<dt class="text-slate-500">seedIndex</dt>
					<dd class="font-medium">{status.cursor?.seedIndex ?? 0}</dd>
				</div>
				<div>
					<dt class="text-slate-500">tickMode</dt>
					<dd class="font-medium">{status.cursor?.tickMode ?? 'catalog'}</dd>
				</div>
				<div>
					<dt class="text-slate-500">queryIndex</dt>
					<dd class="font-medium">{status.cursor?.queryIndex ?? 0}</dd>
				</div>
				<div>
					<dt class="text-slate-500">scrapeCursors (بذور نشطة)</dt>
					<dd
						class="truncate font-mono text-xs"
						title={Object.keys(status.cursor?.scrapeCursors ?? {}).join(', ') || '—'}
					>
						{Object.keys(status.cursor?.scrapeCursors ?? {}).length || '—'}
					</dd>
				</div>
			</dl>
			{#if status.currentSeed}
				<div class="mt-2 text-xs text-slate-600">
					البذرة الحاليّة:
					<strong>{status.currentSeed.label || status.currentSeed.id}</strong>
				</div>
			{/if}
			{#if status.stats?.lastError}
				<div class="mt-2 rounded bg-red-50 p-2 text-xs text-red-700">
					آخر خطأ: {status.stats.lastError}
				</div>
			{/if}
		</section>

		<!-- سجلّ الأحداث -->
		<section class="rounded-lg border border-slate-200 bg-white p-4 shadow-sm">
			<h2 class="mb-2 font-semibold text-slate-900">السجلّ (آخر {status.log?.length ?? 0} حدث)</h2>
			{#if !status.log || status.log.length === 0}
				<p class="text-sm text-slate-500">لا توجد أحداث بعد.</p>
			{:else}
				<ul class="max-h-96 space-y-1 overflow-y-auto">
					{#each status.log as entry (entry.id)}
						<li class="rounded border px-3 py-1.5 text-xs {logColor(entry.level)}">
							<div class="flex justify-between">
								<span class="font-mono text-[10px] opacity-70">{fmtDate(entry.ts)}</span>
								<span class="font-bold uppercase">{entry.level || 'info'}</span>
							</div>
							<div class="mt-0.5">{entry.message}</div>
							{#if entry.reason || entry.identifier || entry.seedId}
								<div class="mt-0.5 text-[10px] opacity-70">
									{#if entry.reason}<span class="ml-2">سبب: {entry.reason}</span>{/if}
									{#if entry.identifier}<span class="ml-2">id: {entry.identifier}</span>{/if}
									{#if entry.seedId}<span class="ml-2">بذرة: {entry.seedId}</span>{/if}
								</div>
							{/if}
						</li>
					{/each}
				</ul>
			{/if}
		</section>
	{/if}

	<!-- نتيجة التشخيص -->
	{#if diagnoseReport}
		<section class="rounded-lg border border-violet-200 bg-violet-50 p-4 shadow-sm">
			<h2 class="mb-2 font-semibold text-violet-900">📋 تقرير التشخيص</h2>
			<pre class="max-h-96 overflow-auto whitespace-pre-wrap rounded bg-white p-3 text-xs text-slate-800">{JSON.stringify(diagnoseReport, null, 2)}</pre>
		</section>
	{/if}
</div>
