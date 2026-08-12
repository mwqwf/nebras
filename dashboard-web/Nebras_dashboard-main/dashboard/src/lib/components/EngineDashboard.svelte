<!--
  EngineDashboard.svelte — لوحة تحكّم/مراقبة عامّة لمحرّكات الجلب
  (مكتبة نور / مؤسسة هنداوي). تعرض الحالة + الإحصاءات + السجلّ + أزرار
  التشغيل/الإيقاف/الدورة/الإعادة. تتلقّى دوال الـ API عبر prop `api`.

  شكل استجابة الحالة المتوقّع (flat):
    { ok, processRunning, config, cursor, stats:{ totalFetched, sectionsCreated,
      runsCount, lastRunAt, lastError }, log:[{ ts, level, message }] }
-->
<script>
	import { onMount, onDestroy } from 'svelte';

	let { title, subtitle = '', accent = '#2563eb', api } = $props();

	let status = $state(null);
	let loading = $state(true);
	let error = $state('');
	let actionInFlight = $state('');
	let actionError = $state('');
	let actionResult = $state(null);
	let diag = $state(null);
	let timer = null;

	const AUTO_REFRESH_MS = 15000;

	async function refresh() {
		try {
			loading = true;
			error = '';
			const r = await api.getStatus();
			if (r?.ok === false) error = r?.error || 'حالة غير معروفة';
			else status = r;
		} catch (e) {
			error = e?.message || String(e);
		} finally {
			loading = false;
		}
	}

	async function runAction(kind, fn) {
		if (actionInFlight) return;
		actionInFlight = kind;
		actionError = '';
		actionResult = null;
		try {
			actionResult = await fn();
		} catch (e) {
			actionError = e?.message || String(e);
		} finally {
			actionInFlight = '';
			refresh();
		}
	}

	async function onDiagnose() {
		if (actionInFlight || !api.diagnose) return;
		actionInFlight = 'diagnose';
		actionError = '';
		diag = null;
		try {
			diag = await api.diagnose();
		} catch (e) {
			actionError = e?.message || String(e);
		} finally {
			actionInFlight = '';
		}
	}

	function fmtDate(ts) {
		if (!ts) return '—';
		try {
			return new Date(ts).toLocaleString('ar-EG', { dateStyle: 'short', timeStyle: 'medium' });
		} catch {
			return String(ts);
		}
	}

	function levelClass(level) {
		if (level === 'error') return 'lg-error';
		if (level === 'warn') return 'lg-warn';
		if (level === 'success') return 'lg-success';
		return 'lg-info';
	}

	onMount(() => {
		refresh();
		timer = setInterval(refresh, AUTO_REFRESH_MS);
	});
	onDestroy(() => timer && clearInterval(timer));

	let running = $derived(Boolean(status?.processRunning));
	let stats = $derived(status?.stats || {});
	let log = $derived(status?.log || []);
</script>

<div class="eng" dir="rtl" style={`--accent:${accent}`}>
	<header class="eng-head">
		<div>
			<h1>{title}</h1>
			{#if subtitle}<p>{subtitle}</p>{/if}
		</div>
		<span class="state {running ? 'on' : 'off'}">
			<span class="dot"></span>{running ? 'يعمل' : 'متوقّف'}
		</span>
	</header>

	<div class="actions">
		<button class="btn primary" disabled={actionInFlight !== ''} onclick={() => runAction('start', api.startEngine)}>▶ تشغيل</button>
		<button class="btn" disabled={actionInFlight !== ''} onclick={() => runAction('stop', api.stopEngine)}>■ إيقاف</button>
		<button class="btn" disabled={actionInFlight !== ''} onclick={() => runAction('tick', api.runOneTick)}>⟳ دورة الآن</button>
		<button class="btn" disabled={actionInFlight !== ''} onclick={() => runAction('reset', () => api.resetEngine('cursor'))}>↺ تصفير المؤشّر</button>
		{#if api.diagnose}
			<button class="btn warn" disabled={actionInFlight !== ''} onclick={onDiagnose}>🔎 تشخيص السبب</button>
		{/if}
		<button class="btn ghost" disabled={loading} onclick={refresh}>تحديث</button>
	</div>

	{#if diag}
		<section class="diag">
			<div class="verdict">{diag.verdict}</div>
			{#if diag.nextStep}<div class="next">الخطوة التالية: {diag.nextStep}</div>{/if}
			<ul class="dsteps">
				{#each diag.steps as st (st.step)}
					<li>
						<strong>{st.step}</strong>:
						{#if st.step === 'crawl4ai_health'}
							مضبوطة={st.configured ? 'نعم' : 'لا'}، تستجيب={st.reachable ? 'نعم' : 'لا'} — {st.detail}
						{:else if st.step === 'fetch_listing'}
							نجح={st.ok ? 'نعم' : 'لا'}، الطريقة={st.method || '—'}، Cloudflare={st.cloudflareChallenge ? 'نعم' : 'لا'} — {st.detail}
						{:else if st.step === 'extract_book_links'}
							عدد الروابط={st.count}
						{/if}
					</li>
				{/each}
			</ul>
		</section>
	{/if}

	{#if actionInFlight}<div class="note">جارٍ تنفيذ: {actionInFlight}…</div>{/if}
	{#if actionError}<div class="alert">{actionError}</div>{/if}
	{#if actionResult?.processed !== undefined}
		<div class="note ok">آخر دورة: جُلِب {actionResult.processed} • تخطّى {actionResult.skipped ?? 0} • فشل {actionResult.failed ?? 0}</div>
	{/if}
	{#if error}<div class="alert">{error}</div>{/if}

	<section class="cards">
		<div class="card"><span>إجمالي المجلوب</span><strong>{stats.totalFetched ?? 0}</strong></div>
		<div class="card"><span>أقسام أُنشئت</span><strong>{stats.sectionsCreated ?? 0}</strong></div>
		<div class="card"><span>عدد الدورات</span><strong>{stats.runsCount ?? 0}</strong></div>
		<div class="card"><span>آخر تشغيل</span><strong class="sm">{fmtDate(stats.lastRunAt)}</strong></div>
	</section>

	{#if stats.lastError}
		<div class="alert soft">آخر خطأ: {stats.lastError}</div>
	{/if}

	<section class="log">
		<h2>السجلّ المباشر</h2>
		{#if log.length === 0}
			<p class="muted">لا سجلّات بعد. اضغط «دورة الآن» أو انتظر الـ cron.</p>
		{:else}
			<ul>
				{#each log as e (e.id || e.ts)}
					<li class={levelClass(e.level)}>
						<span class="ts">{fmtDate(e.ts)}</span>
						<span class="msg">{e.message}</span>
					</li>
				{/each}
			</ul>
		{/if}
	</section>
</div>

<style>
	.eng { padding: 1.5rem; max-width: 1000px; margin: 0 auto; }
	.eng-head { display: flex; justify-content: space-between; align-items: flex-start; gap: 1rem; margin-bottom: 1rem; }
	.eng-head h1 { font-size: 1.4rem; font-weight: 800; margin: 0; }
	.eng-head p { color: #64748b; margin: 0.25rem 0 0; font-size: 0.9rem; }
	.state { display: inline-flex; align-items: center; gap: 0.4rem; padding: 0.3rem 0.8rem; border-radius: 999px; font-weight: 700; font-size: 0.85rem; }
	.state .dot { width: 8px; height: 8px; border-radius: 50%; }
	.state.on { background: #dcfce7; color: #15803d; } .state.on .dot { background: #16a34a; }
	.state.off { background: #f1f5f9; color: #64748b; } .state.off .dot { background: #94a3b8; }
	.actions { display: flex; flex-wrap: wrap; gap: 0.5rem; margin-bottom: 1rem; }
	.btn { border: 1px solid #cbd5e1; background: #fff; border-radius: 0.6rem; padding: 0.5rem 0.9rem; cursor: pointer; font-weight: 600; font-size: 0.85rem; }
	.btn:disabled { opacity: 0.5; cursor: default; }
	.btn.primary { background: var(--accent); color: #fff; border-color: var(--accent); }
	.btn.danger { color: #b91c1c; border-color: #fecaca; }
	.btn.warn { color: #b45309; border-color: #fde68a; background: #fffbeb; }
	.btn.ghost { color: #64748b; }
	.diag { background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 0.7rem; padding: 0.9rem 1rem; margin-bottom: 1rem; }
	.diag .verdict { font-weight: 700; margin-bottom: 0.3rem; }
	.diag .next { color: #475569; font-size: 0.85rem; margin-bottom: 0.5rem; }
	.diag .dsteps { list-style: none; margin: 0; padding: 0; font-size: 0.82rem; }
	.diag .dsteps li { padding: 0.25rem 0; border-bottom: 1px dashed #e2e8f0; }
	.diag .dsteps li:last-child { border-bottom: none; }
	.note { color: #475569; font-size: 0.85rem; margin-bottom: 0.6rem; }
	.note.ok { color: #15803d; }
	.alert { background: #fef2f2; color: #b91c1c; border: 1px solid #fecaca; padding: 0.6rem 0.9rem; border-radius: 0.6rem; margin-bottom: 0.8rem; font-size: 0.85rem; }
	.alert.soft { background: #fffbeb; color: #b45309; border-color: #fde68a; }
	.cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 0.7rem; margin-bottom: 1rem; }
	.card { background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 0.7rem; padding: 0.8rem 1rem; display: flex; flex-direction: column; gap: 0.25rem; }
	.card span { color: #64748b; font-size: 0.78rem; }
	.card strong { font-size: 1.5rem; font-weight: 800; color: #0f172a; }
	.card strong.sm { font-size: 0.95rem; }
	.log { margin-top: 0.5rem; }
	.log h2 { font-size: 1.05rem; font-weight: 700; margin: 0 0 0.6rem; }
	.muted { color: #94a3b8; font-size: 0.85rem; }
	.log ul { list-style: none; margin: 0; padding: 0; max-height: 420px; overflow-y: auto; border: 1px solid #e2e8f0; border-radius: 0.6rem; }
	.log li { display: flex; gap: 0.6rem; padding: 0.45rem 0.7rem; border-bottom: 1px solid #f1f5f9; font-size: 0.82rem; }
	.log li:last-child { border-bottom: none; }
	.log .ts { color: #94a3b8; white-space: nowrap; font-variant-numeric: tabular-nums; }
	.log .msg { flex: 1; }
	.lg-error { background: #fef2f2; color: #b91c1c; }
	.lg-warn { background: #fffbeb; color: #b45309; }
	.lg-success { background: #f0fdf4; color: #15803d; }
	.lg-info { color: #334155; }
</style>
