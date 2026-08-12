<!--
  Global Search Page — /search
  ──────────────────────────────────────────────────────────
  بحث موحَّد عبر الأقسام + الملفّات في Nebras.
  يعتمد حصرًا على طبقة الـ API الحاليّة (لا
  يُنشئ قنوات بيانات جديدة) ويطبّق Arabic-aware AND search + ranking.
-->
<script>
	import DashboardLayout from '$lib/components/DashboardLayout.svelte';
	import { page } from '$app/stores';
	import { goto } from '$app/navigation';
	import {
		searchDashboardUnified
	} from '$lib/api/moderator.js';
	import { t } from '$lib/i18n/store.svelte.js';
	import { tokenize, highlightMatches } from '$lib/utils/search.js';

	import { untrack } from 'svelte';

	let query = $state('');
	let activeTab = $state('all'); // all | sections | files
	let isLoading = $state(false);
	let error = $state('');
	let partialFailures = $state([]);
	let searchTokens = $state([]);

	let sectionsResults = $state([]);
	let filesResults = $state([]);

	let counts = $derived({
		sections: sectionsResults.length,
		files: filesResults.length,
		all: sectionsResults.length + filesResults.length
	});

	// يقرأ الاستعلام من URL عند فتح الصفحة ويُشغّل البحث فورًا.
	$effect(() => {
		const q = String($page.url.searchParams.get('q') || '').trim();
		untrack(() => {
			if (q !== query) {
				query = q;
				if (q) runSearch();
				else resetAll();
			}
		});
	});

	function resetAll() {
		sectionsResults = [];
		filesResults = [];
		searchTokens = [];
		partialFailures = [];
		error = '';
	}

	async function runSearch() {
		const q = String(query || '').trim();
		if (!q) { resetAll(); return; }
		isLoading = true;
		error = '';
		searchTokens = tokenize(q);
		try {
			const results = await searchDashboardUnified({ query: q, requireSearch: true });
			sectionsResults = [
				...(results.groups.mainSections || []).map((x) => ({ ...x, _level: 'main' })),
				...(results.groups.subSections || []).map((x) => ({ ...x, _level: 'sub' })),
				...(results.groups.secondarySections || []).map((x) => ({ ...x, _level: 'secondary' }))
			];
			filesResults = (results.groups.content || []).filter((x) => x.kind === 'file');
			partialFailures = results.partialFailures || [];
		} catch (err) {
			error = err?.message || String(err);
		} finally {
			isLoading = false;
		}
	}

	function buildActionHref(action) {
		if (!action?.route) return '#';
		const url = new URL(action.route, $page.url.origin);
		for (const [key, value] of Object.entries(action.query || {})) {
			if (value !== undefined && value !== null && value !== '') {
				url.searchParams.set(key, String(value));
			}
		}
		return url.pathname + url.search;
	}

	function submit(e) {
		e?.preventDefault?.();
		const q = String(query || '').trim();
		if (!q) return;
		const url = new URL($page.url);
		url.searchParams.set('q', q);
		goto(url.pathname + url.search, { replaceState: true, noScroll: true });
		runSearch();
	}

	function handleKey(e) {
		if (e.key === 'Enter') submit(e);
		else if (e.key === 'Escape') { query = ''; resetAll(); }
	}

	function levelLabel(l) {
		if (l === 'main') return t('sections.main_section');
		if (l === 'sub') return t('sections.sub_section');
		return t('sections.secondary');
	}
</script>

<svelte:head><title>{t('common.search_global_title')} — Nebras</title></svelte:head>

<DashboardLayout>
	<div class="page">
		<div class="page-header">
			<div>
				<h1 class="page-title">{t('common.search_global_title')}</h1>
				<p class="page-desc">{t('common.search_global_desc')}</p>
			</div>
		</div>

		<form class="search-form" onsubmit={submit}>
			<div class="search-box">
				<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="search-icon"><path d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" /></svg>
				<!-- svelte-ignore a11y_autofocus -->
				<input type="text" placeholder={t('common.search_global_placeholder')} bind:value={query} onkeydown={handleKey} class="search-input" autofocus />
				{#if query}
					<button type="button" class="search-clear" aria-label={t('common.search_clear')} onclick={() => { query = ''; resetAll(); }}>
						<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 18L18 6M6 6l12 12" /></svg>
					</button>
				{/if}
			</div>
			<button class="btn btn-primary" type="submit" disabled={!String(query || '').trim()}>
				{t('common.search_btn')}
			</button>
		</form>

		{#if error}<div class="alert alert-error">{error}</div>{/if}
		{#if partialFailures.length > 0}
			<div class="alert alert-warning">
				{t('common.search_partial_warning')}
				{#each partialFailures as f}<span style="display:inline-block;margin:0 0.35rem">· {f.source}</span>{/each}
			</div>
		{/if}

		<div class="tabs">
			<button class="tab" class:active={activeTab === 'all'} onclick={() => activeTab = 'all'}>{t('common.all')} ({counts.all})</button>
			<button class="tab" class:active={activeTab === 'sections'} onclick={() => activeTab = 'sections'}>{t('common.sections')} ({counts.sections})</button>
			<button class="tab" class:active={activeTab === 'files'} onclick={() => activeTab = 'files'}>{t('content.file_uploads')} ({counts.files})</button>
		</div>

		{#if isLoading}
			<div class="state-box"><div class="spinner"></div><span>{t('common.loading')}</span></div>
		{:else if !String(query || '').trim()}
			<div class="state-box empty-state">
				<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" class="empty-icon"><path d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" stroke-linecap="round" stroke-linejoin="round" /></svg>
				<p class="empty-title">{t('common.search_empty_title')}</p>
				<p class="empty-hint">{t('common.search_empty_hint')}</p>
			</div>
		{:else if counts.all === 0}
			<div class="state-box empty-state">
				<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" class="empty-icon"><path d="M19 11H5" stroke-linecap="round" stroke-linejoin="round" /></svg>
				<p>{t('common.search_no_results')}</p>
			</div>
		{:else}
			<!-- Sections group -->
			{#if (activeTab === 'all' || activeTab === 'sections') && sectionsResults.length > 0}
				<h2 class="group-title">{t('common.sections')} <span class="count-badge">{sectionsResults.length}</span></h2>
				<div class="grid">
					{#each sectionsResults as item (item._level + ':' + String(item.id))}
						<div class="result-card">
							{#if item.thumbnail}<img class="thumb" src={item.thumbnail} alt={item.name} />{/if}
							<div class="body">
								<span class="chip">{levelLabel(item._level)}</span>
								<h3 class="title">{@html highlightMatches(item.title || item.name, searchTokens)}</h3>
								<div class="meta">#{item.id}</div>
								<div class="result-actions">
									<a class="mini-btn" href={buildActionHref(item.actions?.edit)}>{t('common.edit')}</a>
									<a class="mini-btn danger" href={buildActionHref(item.actions?.delete)}>{t('common.delete')}</a>
								</div>
							</div>
						</div>
					{/each}
				</div>
			{/if}

			<!-- Files group -->
			{#if (activeTab === 'all' || activeTab === 'files') && filesResults.length > 0}
				<h2 class="group-title">{t('content.file_uploads')} <span class="count-badge">{filesResults.length}</span></h2>
				<div class="grid">
					{#each filesResults as item (item.id)}
						<div class="result-card">
							{#if item.thumbnail}<img class="thumb" src={item.thumbnail} alt={item.title} />{/if}
							<div class="body">
								<span class="chip">{item.content_type || 'file'}</span>
								<h3 class="title">{@html highlightMatches(item.title || 'Untitled', searchTokens)}</h3>
								{#if item.description}<p class="desc">{@html highlightMatches(String(item.description).slice(0, 120), searchTokens)}</p>{/if}
								<div class="result-actions">
									<a class="mini-btn" href={buildActionHref(item.actions?.edit)}>{t('common.edit')}</a>
									<a class="mini-btn danger" href={buildActionHref(item.actions?.delete)}>{t('common.delete')}</a>
								</div>
							</div>
						</div>
					{/each}
				</div>
			{/if}

		{/if}
	</div>
</DashboardLayout>

<style>
	:global(.hl) { background: rgba(234, 179, 8, 0.32); color: inherit; padding: 0 0.125rem; border-radius: 3px; }
	.page { padding: 0; }
	.page-header { display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 1rem; }
	.page-title { font-size: 1.5rem; font-weight: 700; margin: 0 0 0.25rem 0; }
	.page-desc { color: var(--color-surface-400); margin: 0; font-size: 0.9rem; }
	.search-form { display: flex; gap: 0.5rem; align-items: center; margin-bottom: 1rem; }
	.search-box { display: flex; align-items: center; gap: 0.5rem; padding: 0.65rem 0.9rem; background: var(--color-surface-800); border: 1px solid var(--color-surface-700); border-radius: 10px; flex: 1; max-width: 560px; }
	.search-box:focus-within { border-color: var(--color-primary-600); }
	.search-icon { width: 16px; height: 16px; color: var(--color-surface-500); }
	.search-input { flex: 1; background: none; border: none; outline: none; color: var(--color-surface-100); font-size: 0.95rem; font-family: inherit; }
	.search-clear { background: none; border: none; color: var(--color-surface-400); cursor: pointer; padding: 0; display: inline-flex; }
	.search-clear:hover { color: var(--color-surface-100); }
	.search-clear svg { width: 14px; height: 14px; }
	.btn { padding: 0.55rem 1rem; border-radius: 10px; border: none; cursor: pointer; font-weight: 600; font-size: 0.9rem; }
	.btn-primary { background: var(--color-primary-600); color: white; }
	.btn-primary:disabled { opacity: 0.5; cursor: not-allowed; }
	.tabs { display: flex; gap: 0.5rem; border-bottom: 1px solid var(--color-surface-700); margin: 0.75rem 0 1.25rem 0; overflow-x: auto; }
	.tab { padding: 0.5rem 0.9rem; border: none; background: none; color: var(--color-surface-300); cursor: pointer; font-size: 0.875rem; border-bottom: 2px solid transparent; white-space: nowrap; }
	.tab.active { color: var(--color-primary-400); border-bottom-color: var(--color-primary-500); font-weight: 600; }
	.group-title { font-size: 0.95rem; color: var(--color-surface-300); margin: 1rem 0 0.5rem 0; display: flex; align-items: center; gap: 0.5rem; }
	.count-badge { font-size: 0.75rem; background: var(--color-surface-700); color: var(--color-surface-200); padding: 0.15rem 0.5rem; border-radius: 999px; }
	.grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(240px, 1fr)); gap: 0.75rem; margin-bottom: 0.75rem; }
	.result-card { background: var(--color-surface-800); border: 1px solid var(--color-surface-700); border-radius: 10px; padding: 0.75rem; text-decoration: none; color: inherit; display: flex; flex-direction: column; gap: 0.5rem; transition: border-color 0.15s, transform 0.15s; }
	.result-card:hover { border-color: var(--color-primary-600); transform: translateY(-2px); }
	.thumb { width: 100%; height: 120px; object-fit: cover; border-radius: 8px; }
	.result-actions { display: flex; gap: 0.5rem; margin-top: 0.6rem; }
	.mini-btn { display: inline-flex; align-items: center; justify-content: center; padding: 0.35rem 0.7rem; border-radius: 8px; background: var(--color-surface-700); color: var(--color-surface-100); text-decoration: none; font-size: 0.78rem; font-weight: 600; }
	.mini-btn:hover { background: var(--color-primary-700); }
	.mini-btn.danger:hover { background: rgba(220, 38, 38, 0.9); }
	.chip { display: inline-block; font-size: 0.7rem; padding: 0.1rem 0.45rem; border-radius: 4px; background: var(--color-surface-700); color: var(--color-surface-200); }
	.title { font-size: 0.95rem; font-weight: 600; margin: 0.1rem 0 0 0; color: var(--color-surface-100); }
	.desc { font-size: 0.8rem; color: var(--color-surface-400); margin: 0.2rem 0 0 0; }
	.meta { font-size: 0.75rem; color: var(--color-surface-500); }
	.state-box { display: flex; flex-direction: column; align-items: center; justify-content: center; min-height: 220px; gap: 0.75rem; color: var(--color-surface-400); }
	.empty-icon { width: 48px; height: 48px; color: var(--color-surface-600); }
	.empty-title { font-size: 1rem; color: var(--color-surface-200); margin: 0; }
	.empty-hint { font-size: 0.85rem; color: var(--color-surface-500); margin: 0; text-align: center; max-width: 420px; }
	.spinner { width: 28px; height: 28px; border: 3px solid var(--color-surface-700); border-top-color: var(--color-primary-500); border-radius: 50%; animation: spin 0.8s linear infinite; }
	@keyframes spin { to { transform: rotate(360deg); } }
	.alert { padding: 0.6rem 0.85rem; border-radius: 8px; font-size: 0.85rem; margin-bottom: 0.75rem; }
	.alert-error { background: rgba(239, 68, 68, 0.12); border: 1px solid rgba(239, 68, 68, 0.35); color: #fca5a5; }
	.alert-warning { background: rgba(234, 179, 8, 0.12); border: 1px solid rgba(234, 179, 8, 0.35); color: #fde68a; }
</style>
