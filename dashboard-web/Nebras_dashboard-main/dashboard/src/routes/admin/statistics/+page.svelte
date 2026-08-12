<script>
	import { onMount } from 'svelte';
	import { getDashboardOverview, getLibrarySourceStats } from '$lib/api/admin.js';

	let loading = $state(true);
	let error = $state('');
	let overview = $state(null);
	let bySource = $state(null);

	const SOURCE_META = {
		internet_archive: { label: 'الأرشيف (Internet Archive)', color: '#2563eb', emoji: '🏛️' },
		'noor-library': { label: 'مكتبة نور', color: '#16a34a', emoji: '📗' },
		hindawi: { label: 'مؤسسة هنداوي', color: '#9333ea', emoji: '📘' },
		manual: { label: 'رفع يدويّ', color: '#d97706', emoji: '✍️' }
	};

	const TYPE_LABEL = { document: 'كتب', audio: 'صوت', video: 'فيديو' };

	async function load() {
		loading = true;
		error = '';
		try {
			const [ov, bs] = await Promise.all([
				getDashboardOverview().catch(() => null),
				getLibrarySourceStats()
			]);
			overview = ov;
			bySource = bs;
		} catch (e) {
			error = e?.message || 'تعذّر تحميل الإحصاءات.';
		} finally {
			loading = false;
		}
	}

	onMount(load);

	function meta(key) {
		return SOURCE_META[key] || { label: key, color: '#64748b', emoji: '📦' };
	}
</script>

<svelte:head>
	<title>الإحصاءات — Nebras Admin</title>
</svelte:head>

<div class="stats-wrap" dir="rtl">
	<header class="stats-head">
		<div>
			<h1>إحصاءات المحتوى الحقيقية</h1>
			<p>أرقام محسوبة مباشرةً من قاعدة البيانات — لكلّ مصدر جلب على حدة.</p>
		</div>
		<button class="refresh" onclick={load} disabled={loading}>
			{loading ? '...جارٍ التحميل' : '↻ تحديث'}
		</button>
	</header>

	{#if error}
		<div class="alert">{error}</div>
	{/if}

	{#if loading && !bySource}
		<div class="loading">جارٍ حساب الإحصاءات…</div>
	{:else if bySource}
		<!-- إجماليّات عامّة -->
		<section class="totals">
			<div class="tcard"><span>إجمالي المحتوى</span><strong>{bySource.totals.content}</strong></div>
			<div class="tcard"><span>ملفّات (كتب/صوت/فيديو)</span><strong>{bySource.totals.files}</strong></div>
			<div class="tcard">
				<span>الأقسام (رئيسي/فرعي/ثانوي)</span>
				<strong>{bySource.totals.sections.main} / {bySource.totals.sections.sub} / {bySource.totals.sections.secondary}</strong>
			</div>
			{#if bySource.neverViewedCount !== undefined}
				<div class="tcard">
					<span>محتوى لم يُشاهَد بعد</span>
					<strong>{bySource.neverViewedCount}</strong>
				</div>
			{/if}
		</section>

		<!-- بطاقة لكلّ مصدر -->
		<section class="sources">
			{#each bySource.sources as s (s.source)}
				{@const m = meta(s.source)}
				<article class="scard" style={`--accent:${m.color}`}>
					<div class="scard-head">
						<span class="emoji">{m.emoji}</span>
						<h2>{m.label}</h2>
						<span class="badge">{s.total} عنصر</span>
					</div>

					<div class="row">
						<span>الأنواع</span>
						<div class="chips">
							{#each Object.entries(s.byType) as [type, n] (type)}
								{#if n > 0}
									<span class="chip">{TYPE_LABEL[type] || type}: {n}</span>
								{/if}
							{/each}
							{#if s.total === 0}<span class="muted">لا محتوى بعد</span>{/if}
						</div>
					</div>

					<div class="row">
						<span>الأقسام الموضوع فيها</span>
						<div class="chips">
							<span class="chip">رئيسي: {s.sectionsOccupied.main}</span>
							<span class="chip">فرعي: {s.sectionsOccupied.sub}</span>
							<span class="chip">ثانوي: {s.sectionsOccupied.secondary}</span>
						</div>
					</div>

					{#if s.topMainSections.length > 0}
						<div class="row col">
							<span>أعلى الأقسام الرئيسيّة</span>
							<ul class="top">
								{#each s.topMainSections as ms (ms.id)}
									<li><span class="name">{ms.name}</span><span class="count">{ms.count}</span></li>
								{/each}
							</ul>
						</div>
					{/if}
				</article>
			{/each}
		</section>

		{#if bySource.topContent && bySource.topContent.length > 0}
			<section class="topviewed">
				<h3>الأكثر مشاهدةً (حسب المشاهدات والتشغيل)</h3>
				<ol class="tv-list">
					{#each bySource.topContent as c, i (c.id)}
						<li>
							<span class="tv-rank">{i + 1}</span>
							<span class="tv-title">{c.title}</span>
							<span class="tv-type">{TYPE_LABEL[c.type] || c.type}</span>
							<span class="tv-metric" title="مشاهدات">👁 {c.views}</span>
							<span class="tv-metric" title="تشغيل">▶ {c.plays}</span>
						</li>
					{/each}
				</ol>
			</section>
		{/if}

		{#if bySource.rawProviders}
			<section class="raw">
				<h3>توزيع الوسوم الخام (تشخيص: المصدر الفعليّ لكل عنصر)</h3>
				<div class="chips">
					{#each Object.entries(bySource.rawProviders) as [prov, n] (prov)}
						<span class="chip">{prov}: {n}</span>
					{/each}
				</div>
				<p class="hint">«(none/manual)» = محتوى بلا وسم مصدر = رفع يدويّ. يظهر ضمن بطاقة «رفع يدويّ».</p>
			</section>
		{/if}

		{#if overview?.byType}
			<section class="totals">
				<div class="tcard"><span>كتب</span><strong>{overview.byType.document}</strong></div>
				<div class="tcard"><span>صوت</span><strong>{overview.byType.audio}</strong></div>
				<div class="tcard"><span>فيديو</span><strong>{overview.byType.video}</strong></div>
			</section>
		{/if}
	{/if}
</div>

<style>
	.stats-wrap { padding: 1.5rem; max-width: 1100px; margin: 0 auto; }
	.stats-head { display: flex; justify-content: space-between; align-items: flex-start; gap: 1rem; margin-bottom: 1.25rem; }
	.stats-head h1 { font-size: 1.4rem; font-weight: 800; margin: 0; }
	.stats-head p { color: #64748b; margin: 0.25rem 0 0; font-size: 0.9rem; }
	.refresh { border: 1px solid #cbd5e1; background: #fff; border-radius: 0.6rem; padding: 0.5rem 0.9rem; cursor: pointer; font-weight: 600; }
	.refresh:disabled { opacity: 0.6; cursor: default; }
	.alert { background: #fef2f2; color: #b91c1c; border: 1px solid #fecaca; padding: 0.75rem 1rem; border-radius: 0.6rem; margin-bottom: 1rem; }
	.loading { color: #64748b; padding: 2rem; text-align: center; }
	.totals { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 0.8rem; margin-bottom: 1.25rem; }
	.tcard { background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 0.75rem; padding: 0.9rem 1rem; display: flex; flex-direction: column; gap: 0.3rem; }
	.tcard span { color: #64748b; font-size: 0.8rem; }
	.tcard strong { font-size: 1.5rem; font-weight: 800; color: #0f172a; }
	.sources { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 1rem; margin-bottom: 1.25rem; }
	.scard { border: 1px solid #e2e8f0; border-top: 4px solid var(--accent); border-radius: 0.85rem; padding: 1rem 1.1rem; background: #fff; }
	.scard-head { display: flex; align-items: center; gap: 0.5rem; margin-bottom: 0.75rem; }
	.scard-head .emoji { font-size: 1.3rem; }
	.scard-head h2 { font-size: 1.05rem; font-weight: 700; margin: 0; flex: 1; }
	.badge { background: var(--accent); color: #fff; border-radius: 999px; padding: 0.15rem 0.7rem; font-size: 0.8rem; font-weight: 700; }
	.row { margin-top: 0.7rem; }
	.row > span { display: block; color: #64748b; font-size: 0.78rem; margin-bottom: 0.35rem; }
	.row.col { display: flex; flex-direction: column; }
	.chips { display: flex; flex-wrap: wrap; gap: 0.35rem; }
	.chip { background: #f1f5f9; border-radius: 0.5rem; padding: 0.2rem 0.55rem; font-size: 0.8rem; color: #0f172a; }
	.muted { color: #94a3b8; font-size: 0.8rem; }
	.top { list-style: none; margin: 0; padding: 0; }
	.top li { display: flex; justify-content: space-between; padding: 0.3rem 0; border-bottom: 1px dashed #e2e8f0; font-size: 0.85rem; }
	.top li:last-child { border-bottom: none; }
	.top .count { font-weight: 700; color: var(--accent); }
	.raw { background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 0.75rem; padding: 0.9rem 1rem; margin-bottom: 1.25rem; }
	.raw h3 { font-size: 0.95rem; font-weight: 700; margin: 0 0 0.6rem; }
	.raw .hint { color: #94a3b8; font-size: 0.78rem; margin: 0.6rem 0 0; }
	.topviewed { background: #fff; border: 1px solid #e2e8f0; border-radius: 0.75rem; padding: 0.9rem 1rem; margin-bottom: 1.25rem; }
	.topviewed h3 { font-size: 0.95rem; font-weight: 700; margin: 0 0 0.6rem; }
	.tv-list { list-style: none; margin: 0; padding: 0; counter-reset: tv; }
	.tv-list li { display: flex; align-items: center; gap: 0.6rem; padding: 0.4rem 0; border-bottom: 1px dashed #e2e8f0; font-size: 0.85rem; }
	.tv-list li:last-child { border-bottom: none; }
	.tv-rank { width: 1.6rem; height: 1.6rem; flex: none; display: grid; place-items: center; background: #f1f5f9; border-radius: 50%; font-weight: 700; font-size: 0.78rem; color: #334155; }
	.tv-title { flex: 1; font-weight: 600; color: #0f172a; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
	.tv-type { color: #64748b; font-size: 0.78rem; white-space: nowrap; }
	.tv-metric { color: #475569; font-variant-numeric: tabular-nums; white-space: nowrap; }
</style>
