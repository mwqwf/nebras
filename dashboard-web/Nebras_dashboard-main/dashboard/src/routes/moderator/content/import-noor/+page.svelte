
<!--
  Noor Library Autonomous Fetcher — Control Center
  =================================================
  لوحة قيادة محرّك الجلب الآلي من مكتبة نور.

  ميزات:
    • زرّ تشغيل/إيقاف رئيسي يقلب علامة enabled في RTDB.
    • 4 بطاقات إحصائيّة تتحدّث لحظيّاً (إجمالي الكتب، الأقسام الجديدة،
      عدد الدورات، آخر تشغيل).
    • سجل حيّ (Live Log) يُحدَّث كلّ 3 ثوانٍ بآخر 30 حدث.
    • تحرير قائمة بذور الزحف (seed URLs).
    • زرّ "تشغيل دورة الآن" للاختبار اليدوي.

  معماريّاً: لا تكتب هذه الصفحة في Firebase مباشرةً — كلّ شيء يمرّ عبر
  /api/admin/noor-library/engine/* المحميّ بـ hooks.server.js +
  Admin SDK لمشروع نبراس فقط.
-->

<script>
	import { onMount, onDestroy } from 'svelte';
	import {
		getEngineStatus,
		startEngineRemote,
		stopEngineRemote,
		updateEngineSeeds,
		resetEngineCursor
	} from '$lib/api/noorLibrary.js';

	// ─── State ─────────────────────────────────────────────────
	/** @type {any} */
	let status = $state(null);
	let isLoading = $state(true);
	let isToggling = $state(false);
	let isSavingSeeds = $state(false);
	let isResettingCursor = $state(false);

	let topError = $state('');
	let topNotice = $state('');

	// تحرير seedUrls كـ multi-line text
	let seedsText = $state('');
	let seedsDirty = $state(false);

	let pollTimer = /** @type {ReturnType<typeof setInterval>|null} */ (null);
	const POLL_INTERVAL_MS = 3000;

	// ─── Derived ───────────────────────────────────────────────
	let cfg = $derived(status?.config || null);
	let stats = $derived(
		status?.stats || { totalFetched: 0, sectionsCreated: 0, runsCount: 0, lastRunAt: null, lastError: null }
	);
	let cursor = $derived(status?.cursor || { seedIndex: 0, page: 1 });
	let log = $derived(status?.log || []);
	let engineActive = $derived(!!status?.config?.enabled);
	let processAlive = $derived(!!status?.processRunning);
	/** حالة شريط الحالة — يُستخدم data-variant حتى يلتقط المُجمّع أنماط CSS الصحيحة */
	let metaChipVariant = $derived(processAlive ? 'on' : engineActive ? 'warn' : 'off');

	// ─── Lifecycle ─────────────────────────────────────────────
	onMount(async () => {
		await refresh();
		startPolling();
	});

	onDestroy(() => {
		stopPolling();
	});

	function startPolling() {
		stopPolling();
		pollTimer = setInterval(() => {
			refresh().catch(() => {});
		}, POLL_INTERVAL_MS);
	}

	function stopPolling() {
		if (pollTimer) {
			clearInterval(pollTimer);
			pollTimer = null;
		}
	}

	async function refresh() {
		try {
			const data = await getEngineStatus(30);
			status = data;
			// لا نُغيّر seedsText إن كان المستخدم في خضمّ التعديل (dirty)
			if (!seedsDirty && Array.isArray(data?.config?.seedUrls)) {
				seedsText = data.config.seedUrls.join('\n');
			}
			topError = '';
		} catch (err) {
			topError = err?.message || 'فشل تحميل حالة المحرّك.';
		} finally {
			isLoading = false;
		}
	}

	// ─── Handlers ──────────────────────────────────────────────
	async function handleToggle() {
		if (isToggling) return;
		isToggling = true;
		topError = '';
		topNotice = '';
		try {
			if (engineActive) {
				await stopEngineRemote();
				topNotice = 'تمّ إرسال أمر الإيقاف. أيّ دورة جارية ستُكمَل ثم يتوقّف المحرّك.';
			} else {
				await startEngineRemote();
				topNotice = 'بدأ المحرّك. ستظهر النتائج في السجلّ خلال ثوانٍ.';
			}
			await refresh();
		} catch (err) {
			topError = err?.message || 'تعذّر تنفيذ الأمر.';
		} finally {
			isToggling = false;
		}
	}

	async function handleSaveSeeds() {
		if (isSavingSeeds) return;
		isSavingSeeds = true;
		topError = '';
		topNotice = '';
		try {
			const lines = seedsText
				.split('\n')
				.map((s) => s.trim())
				.filter(Boolean);
			const result = await updateEngineSeeds(lines);
			seedsDirty = false;
			topNotice = `تمّ حفظ ${result.config.seedUrls.length} بذرة وإعادة المؤشّر للبدء.`;
			await refresh();
		} catch (err) {
			topError = err?.message || 'فشل حفظ البذور.';
		} finally {
			isSavingSeeds = false;
		}
	}

	async function handleResetCursor() {
		if (isResettingCursor) return;
		isResettingCursor = true;
		topError = '';
		topNotice = '';
		try {
			await resetEngineCursor();
			topNotice = 'تمّ إعادة المؤشّر إلى البذرة الأولى/صفحة 1.';
			await refresh();
		} catch (err) {
			topError = err?.message || 'فشل إعادة المؤشّر.';
		} finally {
			isResettingCursor = false;
		}
	}

	function handleSeedsInput() {
		seedsDirty = true;
	}

	// ─── Formatters ────────────────────────────────────────────
	function formatDate(ts) {
		if (!ts) return '—';
		try {
			return new Date(Number(ts)).toLocaleString('ar', {
				year: 'numeric',
				month: 'short',
				day: '2-digit',
				hour: '2-digit',
				minute: '2-digit',
				second: '2-digit'
			});
		} catch {
			return '—';
		}
	}

	function relativeTime(ts) {
		if (!ts) return 'لم يحدث بعد';
		const diff = Date.now() - Number(ts);
		if (diff < 0) return formatDate(ts);
		if (diff < 5000) return 'الآن';
		if (diff < 60_000) return `منذ ${Math.floor(diff / 1000)} ث`;
		if (diff < 3_600_000) return `منذ ${Math.floor(diff / 60_000)} د`;
		if (diff < 86_400_000) return `منذ ${Math.floor(diff / 3_600_000)} س`;
		return formatDate(ts);
	}

	function logIcon(level) {
		if (level === 'success') return '✓';
		if (level === 'error') return '✕';
		return 'ℹ';
	}

	function logLevelClass(level) {
		if (level === 'success') return 'log-success';
		if (level === 'error') return 'log-error';
		return 'log-info';
	}
</script>

<svelte:head><title>محرّك جلب مكتبة نور — Nebras</title></svelte:head>

<div class="page">
	<!-- ═══════════════ Header + Master Toggle ═══════════════ -->
	<header class="page-header">
		<div>
			<h1 class="page-title">محرّك الجلب الآلي — مكتبة نور</h1>
			<p class="page-desc">
				محرّك مستقلّ يتصفّح أقسام مكتبة نور في الخلفية، يصنّف الكتب آليّاً،
				ويرفعها مباشرةً إلى قاعدة بيانات نبراس مع إنشاء أقسام جديدة عند الحاجة.
				بمجرّد التشغيل، الدورات تتجدّد تلقائياً إلى ما لا نهاية ولا تتوقّف
				إلا حين تضغط زرّ الإيقاف. عند الفشل المتتالي يُطبَّق back-off (تباطؤ
				الفترة بين الدورات) دون إيقاف المحرّك.
			</p>
		</div>
		<div class="header-meta">
			<!-- الذكاء الاصطناعي محذوف حالياً -->
			<span class="meta-chip" data-variant={metaChipVariant}>
				<span class="dot"></span>
				{#if processAlive}
					الحلقة الداخليّة تعمل
				{:else if engineActive}
					الإعدادات مفعّلة لكنّ الحلقة لا تدور — انتظر الفحص التلقائي
				{:else}
					الحلقة الداخليّة متوقّفة
				{/if}
			</span>
		</div>
	</header>

	<!-- alerts -->
	{#if topError}
		<div class="alert alert-error">{topError}</div>
	{/if}
	{#if topNotice}
		<div class="alert alert-notice">{topNotice}</div>
	{/if}

	<!-- ═══════════════ Master Toggle Card ═══════════════ -->
	<section class="card master-card" class:active={engineActive}>
		<div class="master-row">
			<div class="master-info">
				<div class="master-status">
					<span class="status-pulse" class:on={engineActive}></span>
					<span class="status-text">
						{engineActive ? 'المحرّك يعمل' : 'المحرّك متوقّف'}
					</span>
				</div>
				<div class="master-meta">
					{#if cfg}
						يجلب {cfg.batchSize} كتاب لكلّ دورة، فاصل {Math.round(cfg.tickIntervalMs / 1000)} ث،
						على {cfg.seedUrls?.length || 0} بذور.
					{:else}
						جارِ تحميل الإعدادات...
					{/if}
				</div>
			</div>

			<div class="master-actions">
				<button
					class="btn btn-master {engineActive ? 'btn-stop' : 'btn-start'}"
					onclick={handleToggle}
					disabled={isToggling || isLoading}
				>
					{#if isToggling}
						جارِ...
					{:else if engineActive}
						<span class="btn-icon">⏸</span> إيقاف المحرّك
					{:else}
						<span class="btn-icon">▶</span> تشغيل المحرّك
					{/if}
				</button>
			</div>
		</div>
	</section>

	<!-- ═══════════════ Stats Cards ═══════════════ -->
	<div class="stats-grid">
		<div class="stat-card">
			<div class="stat-label">إجمالي الكتب المُجلَبة</div>
			<div class="stat-value primary">{stats.totalFetched.toLocaleString('ar')}</div>
			<div class="stat-sub">منذ بدء المحرّك</div>
		</div>

		<div class="stat-card">
			<div class="stat-label">الأقسام الجديدة المُنشَأة</div>
			<div class="stat-value accent">{stats.sectionsCreated.toLocaleString('ar')}</div>
			<div class="stat-sub">آليّاً</div>
		</div>

		<div class="stat-card">
			<div class="stat-label">عدد الدورات المنفّذة</div>
			<div class="stat-value">{stats.runsCount.toLocaleString('ar')}</div>
			<div class="stat-sub">دورة جلب لـ batch</div>
		</div>

		<div class="stat-card">
			<div class="stat-label">آخر تشغيل</div>
			<div class="stat-value sm">{relativeTime(stats.lastRunAt)}</div>
			<div class="stat-sub" title={formatDate(stats.lastRunAt)}>
				{stats.lastError ? `آخر خطأ: ${stats.lastError}` : 'بلا أخطاء'}
			</div>
		</div>
	</div>

	<!-- ═══════════════ Cursor + Current Seed ═══════════════ -->
	<section class="card">
		<div class="card-header">
			<div>
				<h2 class="card-title">المؤشّر الحالي</h2>
				<p class="card-desc">
					يوضّح أين توقّف المحرّك آخر مرّة. عند إعادة التشغيل يكمل من نفس النقطة.
				</p>
			</div>
			<button
				class="btn btn-secondary btn-sm"
				onclick={handleResetCursor}
				disabled={isResettingCursor}
			>
				{isResettingCursor ? '...' : 'إعادة المؤشّر للبداية'}
			</button>
		</div>

		<div class="cursor-row">
			<div class="cursor-item">
				<div class="cursor-label">البذرة #</div>
				<div class="cursor-value">{cursor.seedIndex + 1}</div>
			</div>
			<div class="cursor-item grow">
				<div class="cursor-label">الرابط الحالي</div>
				<div class="cursor-value mono trunc" title={status?.currentSeedUrl || ''}>
					{status?.currentSeedUrl || '—'}
				</div>
			</div>
			<div class="cursor-item">
				<div class="cursor-label">الصفحة</div>
				<div class="cursor-value">{cursor.page}</div>
			</div>
		</div>
	</section>

	<!-- ═══════════════ Seed URLs Editor ═══════════════ -->
	<section class="card">
		<div class="card-header">
			<div>
				<h2 class="card-title">روابط البذور (Seed URLs)</h2>
				<p class="card-desc">
					رابط واحد لكلّ سطر. كلّها يجب أن تنتمي لـ <code>noor-book.com</code>.
					تغييرها يُعيد المؤشّر للبداية ولا يمسح ما جُلِب سابقاً.
				</p>
			</div>
		</div>

		<textarea
			class="seeds-textarea"
			rows="8"
			bind:value={seedsText}
			oninput={handleSeedsInput}
			placeholder="https://www.noor-book.com/category/..."
			disabled={isSavingSeeds}
		></textarea>

		<div class="seeds-actions">
			<span class="seeds-count">
				{seedsText.split('\n').filter((s) => s.trim()).length} بذرة
				{#if seedsDirty}<span class="dirty-mark">• غير محفوظة</span>{/if}
			</span>
			<button
				class="btn btn-primary btn-sm"
				onclick={handleSaveSeeds}
				disabled={!seedsDirty || isSavingSeeds}
			>
				{isSavingSeeds ? 'حفظ...' : 'حفظ البذور'}
			</button>
		</div>
	</section>

	<!-- ═══════════════ Live Log ═══════════════ -->
	<section class="card">
		<div class="card-header">
			<div>
				<h2 class="card-title">السجلّ الحيّ</h2>
				<p class="card-desc">
					آخر 30 حدث (يتحدّث كلّ {Math.round(POLL_INTERVAL_MS / 1000)} ث).
				</p>
			</div>
			<span class="live-indicator">
				<span class="dot pulse"></span> Live
			</span>
		</div>

		{#if log.length === 0}
			<div class="empty">
				لا توجد أحداث بعد. شغّل المحرّك أو دورةً يدويّة لرؤية النتائج هنا.
			</div>
		{:else}
			<ul class="log-list">
				{#each log as entry (entry.id)}
					<li class="log-entry {logLevelClass(entry.level)}">
						<span class="log-icon">{logIcon(entry.level)}</span>
						<div class="log-body">
							<div class="log-message">{entry.message}</div>
							{#if entry.hierarchy}
								<div class="log-meta">
									<strong>{entry.hierarchy.main?.name || '—'}</strong>
									› {entry.hierarchy.sub?.name || '—'}
									{#if entry.hierarchy.secondary}› {entry.hierarchy.secondary.name}{/if}
									{#if entry.decision === 'create_sub' || entry.decision === 'create_secondary'}
										<span class="badge new-section">قسم جديد</span>
									{/if}
								</div>
							{/if}
							{#if entry.url}
								<a class="log-url" href={entry.url} target="_blank" rel="noreferrer">{entry.url}</a>
							{/if}
							{#if entry.reason}
								<div class="log-reason"><code>{entry.reason}</code></div>
							{/if}
						</div>
						<div class="log-time" title={formatDate(entry.ts)}>{relativeTime(entry.ts)}</div>
					</li>
				{/each}
			</ul>
		{/if}
	</section>
</div>


<style>
	.page { display: flex; flex-direction: column; gap: 1.25rem; max-width: 1280px; }

	/* ── Header ─────────────────────────── */
	.page-header { display: flex; justify-content: space-between; align-items: flex-start; gap: 1rem; flex-wrap: wrap; }
	.page-title { font-size: 1.625rem; font-weight: 800; color: var(--color-surface-100); letter-spacing: -0.02em; }
	.page-desc { font-size: 0.875rem; color: var(--color-surface-400); margin-top: 0.5rem; max-width: 760px; line-height: 1.65; }
	.header-meta { display: flex; flex-direction: column; gap: 0.5rem; align-items: flex-end; }
	.meta-chip { font-size: 0.75rem; padding: 0.35rem 0.7rem; background: var(--color-surface-800); border: 1px solid var(--color-surface-700); border-radius: 100px; color: var(--color-surface-300); display: inline-flex; align-items: center; gap: 0.5rem; }
	.meta-chip .dot { width: 8px; height: 8px; border-radius: 50%; background: var(--color-surface-500); }
	.meta-chip[data-variant="on"] { color: var(--color-primary-300); border-color: var(--color-primary-700); }
	.meta-chip[data-variant="on"] .dot { background: var(--color-primary-400); box-shadow: 0 0 8px var(--color-primary-500); }
	.meta-chip[data-variant="warn"] { color: #fbbf24; border-color: rgba(245,158,11,0.4); }
	.meta-chip[data-variant="warn"] .dot { background: #fbbf24; }

	/* ── Alerts ─────────────────────────── */
	.alert { padding: 0.75rem 1rem; border-radius: 10px; font-size: 0.8125rem; }
	.alert-error { background: rgba(244,63,94,0.1); border: 1px solid rgba(244,63,94,0.25); color: var(--color-danger-400); }
	.alert-notice { background: rgba(59,130,246,0.1); border: 1px solid rgba(59,130,246,0.25); color: #93c5fd; }

	/* ── Card base ─────────────────────────── */
	.card { background: var(--color-surface-800); border: 1px solid var(--color-surface-700); border-radius: 14px; padding: 1.25rem 1.5rem; display: flex; flex-direction: column; gap: 1rem; }
	.card-header { display: flex; justify-content: space-between; align-items: flex-start; gap: 1rem; }
	.card-title { font-size: 1.125rem; font-weight: 700; color: var(--color-surface-100); }
	.card-desc { font-size: 0.8125rem; color: var(--color-surface-400); margin-top: 0.25rem; line-height: 1.55; }
	.card-desc code { background: var(--color-surface-900); padding: 0.05rem 0.3rem; border-radius: 4px; }

	/* ── Master toggle ─────────────────────────── */
	.master-card { padding: 1.5rem 1.75rem; transition: border-color 0.2s; }
	.master-card.active { border-color: var(--color-primary-600); background: linear-gradient(180deg, rgba(5,150,105,0.06), var(--color-surface-800)); }
	.master-row { display: flex; justify-content: space-between; align-items: center; gap: 1.5rem; flex-wrap: wrap; }
	.master-info { display: flex; flex-direction: column; gap: 0.4rem; min-width: 240px; }
	.master-status { display: flex; align-items: center; gap: 0.65rem; }
	.status-pulse { width: 14px; height: 14px; border-radius: 50%; background: var(--color-surface-500); transition: background 0.2s, box-shadow 0.2s; }
	.status-pulse.on { background: var(--color-primary-400); box-shadow: 0 0 0 4px rgba(5,150,105,0.18); animation: pulse 1.6s ease-in-out infinite; }
	@keyframes pulse {
		0%, 100% { box-shadow: 0 0 0 4px rgba(5,150,105,0.18); }
		50%      { box-shadow: 0 0 0 9px rgba(5,150,105,0.06); }
	}
	.status-text { font-size: 1.125rem; font-weight: 700; color: var(--color-surface-100); }
	.master-meta { font-size: 0.8125rem; color: var(--color-surface-400); }
	.master-actions { display: flex; gap: 0.5rem; flex-wrap: wrap; }

	/* ── Stats ─────────────────────────── */
	.stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 0.85rem; }
	.stat-card { background: var(--color-surface-800); border: 1px solid var(--color-surface-700); border-radius: 12px; padding: 1.1rem 1.25rem; display: flex; flex-direction: column; gap: 0.35rem; }
	.stat-label { font-size: 0.75rem; color: var(--color-surface-400); text-transform: uppercase; letter-spacing: 0.04em; }
	.stat-value { font-size: 2rem; font-weight: 800; color: var(--color-surface-100); line-height: 1.1; }
	.stat-value.sm { font-size: 1.125rem; }
	.stat-value.primary { color: var(--color-primary-400); }
	.stat-value.accent { color: #60a5fa; }
	.stat-sub { font-size: 0.75rem; color: var(--color-surface-500); }

	/* ── Cursor row ─────────────────────────── */
	.cursor-row { display: flex; gap: 1rem; flex-wrap: wrap; align-items: stretch; }
	.cursor-item { background: var(--color-surface-900); border: 1px solid var(--color-surface-700); border-radius: 10px; padding: 0.6rem 0.85rem; min-width: 90px; display: flex; flex-direction: column; gap: 0.25rem; }
	.cursor-item.grow { flex: 1; min-width: 200px; }
	.cursor-label { font-size: 0.7rem; color: var(--color-surface-400); text-transform: uppercase; letter-spacing: 0.05em; }
	.cursor-value { font-size: 0.9375rem; font-weight: 600; color: var(--color-surface-100); }
	.cursor-value.mono { font-family: ui-monospace, SFMono-Regular, Consolas, monospace; font-size: 0.8125rem; font-weight: 500; }
	.cursor-value.trunc { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 100%; }

	/* ── Seeds editor ─────────────────────────── */
	.seeds-textarea { width: 100%; padding: 0.85rem 1rem; background: var(--color-surface-900); border: 1px solid var(--color-surface-600); border-radius: 10px; color: var(--color-surface-100); font-family: ui-monospace, SFMono-Regular, Consolas, monospace; font-size: 0.8125rem; line-height: 1.55; outline: none; resize: vertical; }
	.seeds-textarea:focus { border-color: var(--color-primary-500); }
	.seeds-actions { display: flex; justify-content: space-between; align-items: center; margin-top: 0.25rem; }
	.seeds-count { font-size: 0.75rem; color: var(--color-surface-400); }
	.dirty-mark { color: #fbbf24; margin-inline-start: 0.4rem; font-weight: 600; }

	/* ── Live log ─────────────────────────── */
	.live-indicator { display: inline-flex; align-items: center; gap: 0.4rem; font-size: 0.7rem; color: var(--color-primary-400); font-weight: 600; padding: 0.25rem 0.6rem; background: rgba(5,150,105,0.12); border-radius: 100px; }
	.live-indicator .dot { width: 6px; height: 6px; background: var(--color-primary-400); border-radius: 50%; }
	.live-indicator .dot.pulse { animation: pulse-dot 1.4s ease-in-out infinite; }
	@keyframes pulse-dot {
		0%, 100% { opacity: 1; }
		50%      { opacity: 0.3; }
	}

	.empty { padding: 2rem; text-align: center; color: var(--color-surface-500); font-size: 0.875rem; }

	.log-list { list-style: none; padding: 0; margin: 0; display: flex; flex-direction: column; gap: 0.4rem; max-height: 600px; overflow-y: auto; }
	.log-entry { display: grid; grid-template-columns: 28px 1fr auto; gap: 0.75rem; padding: 0.65rem 0.85rem; background: var(--color-surface-900); border: 1px solid var(--color-surface-700); border-radius: 8px; align-items: flex-start; font-size: 0.8125rem; }
	.log-icon { width: 22px; height: 22px; border-radius: 50%; display: inline-flex; align-items: center; justify-content: center; font-weight: 800; flex-shrink: 0; }
	.log-success .log-icon { background: rgba(5,150,105,0.18); color: var(--color-primary-400); }
	.log-error .log-icon { background: rgba(244,63,94,0.15); color: var(--color-danger-400); }
	.log-info .log-icon { background: rgba(59,130,246,0.15); color: #60a5fa; }
	.log-body { display: flex; flex-direction: column; gap: 0.2rem; min-width: 0; }
	.log-message { color: var(--color-surface-200); font-weight: 500; }
	.log-meta { font-size: 0.75rem; color: var(--color-surface-400); display: inline-flex; flex-wrap: wrap; gap: 0.4rem; align-items: center; }
	.log-meta strong { color: var(--color-surface-300); }
	.badge { display: inline-flex; align-items: center; padding: 0.05rem 0.4rem; border-radius: 100px; font-size: 0.65rem; font-weight: 700; }
	.badge.new-section { background: rgba(96,165,250,0.18); color: #93c5fd; }
	.log-url { font-size: 0.7rem; color: var(--color-surface-500); text-decoration: none; word-break: break-all; }
	.log-url:hover { color: var(--color-primary-400); text-decoration: underline; }
	.log-reason { font-size: 0.7rem; color: var(--color-surface-500); }
	.log-reason code { background: var(--color-surface-800); padding: 0.05rem 0.3rem; border-radius: 4px; }
	.log-time { font-size: 0.7rem; color: var(--color-surface-500); white-space: nowrap; flex-shrink: 0; }

	/* ── Buttons ─────────────────────────── */
	.btn { display: inline-flex; align-items: center; gap: 0.5rem; padding: 0.65rem 1.125rem; border-radius: 10px; font-size: 0.8125rem; font-weight: 600; font-family: inherit; cursor: pointer; border: none; transition: all 0.15s; }
	.btn-sm { padding: 0.4rem 0.75rem; font-size: 0.75rem; }
	.btn-master { padding: 0.85rem 1.5rem; font-size: 0.9375rem; min-width: 180px; justify-content: center; }
	.btn-icon { font-size: 1rem; }
	.btn-primary { background: linear-gradient(135deg, var(--color-primary-700), var(--color-primary-600)); color: white; }
	.btn-primary:hover:not(:disabled) { box-shadow: 0 4px 12px rgba(5,150,105,0.25); }
	.btn-primary:disabled { opacity: 0.5; cursor: not-allowed; }
	.btn-start { background: linear-gradient(135deg, #047857, #059669); color: white; }
	.btn-start:hover:not(:disabled) { box-shadow: 0 6px 16px rgba(5,150,105,0.35); transform: translateY(-1px); }
	.btn-stop { background: linear-gradient(135deg, #b91c1c, #dc2626); color: white; }
	.btn-stop:hover:not(:disabled) { box-shadow: 0 6px 16px rgba(220,38,38,0.35); transform: translateY(-1px); }
	.btn-secondary { background: var(--color-surface-700); color: var(--color-surface-300); border: 1px solid var(--color-surface-600); }
	.btn-secondary:hover:not(:disabled) { background: var(--color-surface-600); }
	.btn:disabled { opacity: 0.5; cursor: not-allowed; }

	/* ── Danger Zone ─────────────────────────── */
	.danger-card {
		border-color: rgba(220, 38, 38, 0.45);
		background: linear-gradient(180deg, rgba(220, 38, 38, 0.06), var(--color-surface-800));
	}
	.danger-title { color: #fca5a5; }
	.danger-card .card-desc strong { color: #fca5a5; }
	.danger-card .card-desc code {
		background: rgba(0, 0, 0, 0.35);
		padding: 0.05rem 0.35rem;
		border-radius: 4px;
		font-size: 0.78rem;
		color: #fde68a;
	}
	.danger-actions { display: flex; justify-content: flex-end; }
	.btn-nuclear {
		background: linear-gradient(135deg, #991b1b, #dc2626);
		color: white;
		font-weight: 800;
		letter-spacing: 0.01em;
		box-shadow: 0 6px 16px rgba(220, 38, 38, 0.32);
		padding: 0.85rem 1.5rem;
	}
	.btn-nuclear:hover:not(:disabled) {
		box-shadow: 0 8px 22px rgba(220, 38, 38, 0.45);
		transform: translateY(-1px);
	}
	.btn-nuclear:disabled { opacity: 0.55; cursor: not-allowed; }

	/* ── Modal ─────────────────────────── */
	.modal-backdrop {
		position: fixed;
		inset: 0;
		background: rgba(0, 0, 0, 0.65);
		backdrop-filter: blur(4px);
		display: flex;
		align-items: center;
		justify-content: center;
		z-index: 1000;
		padding: 1rem;
	}
	.modal-card {
		background: var(--color-surface-800);
		border: 1px solid rgba(220, 38, 38, 0.45);
		border-radius: 14px;
		max-width: 520px;
		width: 100%;
		display: flex;
		flex-direction: column;
		gap: 0;
		overflow: hidden;
		box-shadow: 0 24px 60px rgba(0, 0, 0, 0.55);
	}
	.modal-header {
		padding: 1.1rem 1.4rem;
		border-bottom: 1px solid var(--color-surface-700);
		background: linear-gradient(180deg, rgba(220, 38, 38, 0.12), transparent);
	}
	.modal-title {
		display: flex;
		align-items: center;
		gap: 0.6rem;
		font-size: 1.1rem;
		font-weight: 800;
		color: #fca5a5;
		margin: 0;
	}
	.modal-icon { font-size: 1.4rem; }
	.modal-body {
		padding: 1.2rem 1.4rem;
		display: flex;
		flex-direction: column;
		gap: 0.85rem;
		font-size: 0.875rem;
		color: var(--color-surface-200);
		line-height: 1.65;
	}
	.modal-body p { margin: 0; }
	.modal-body strong { color: var(--color-surface-100); }
	.modal-warning {
		padding: 0.6rem 0.8rem;
		background: rgba(220, 38, 38, 0.1);
		border: 1px solid rgba(220, 38, 38, 0.25);
		border-radius: 8px;
		color: #fecaca;
		font-size: 0.8125rem;
	}
	.modal-confirm {
		display: flex;
		flex-direction: column;
		gap: 0.4rem;
		font-size: 0.8125rem;
		color: var(--color-surface-300);
	}
	.modal-confirm code {
		background: var(--color-surface-900);
		padding: 0.05rem 0.35rem;
		border-radius: 4px;
		color: #fde68a;
		font-weight: 700;
	}
	.modal-confirm input {
		padding: 0.6rem 0.85rem;
		background: var(--color-surface-900);
		border: 1px solid var(--color-surface-600);
		border-radius: 8px;
		color: var(--color-surface-100);
		font-family: inherit;
		font-size: 0.95rem;
		outline: none;
		text-align: center;
		letter-spacing: 0.05em;
	}
	.modal-confirm input:focus { border-color: #dc2626; }
	.modal-footer {
		display: flex;
		justify-content: flex-end;
		gap: 0.5rem;
		padding: 1rem 1.4rem;
		border-top: 1px solid var(--color-surface-700);
		background: var(--color-surface-900);
	}
</style>
