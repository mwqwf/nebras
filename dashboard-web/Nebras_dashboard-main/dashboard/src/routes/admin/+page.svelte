<script>
	import { onMount, onDestroy } from 'svelte';
	import { t } from '$lib/i18n/store.svelte.js';
	import { getDashboardOverview } from '$lib/api/admin.js';

	// Chart.js imports
	import {
		Chart,
		Title,
		Tooltip,
		Legend,
		ArcElement,
		CategoryScale,
		LinearScale,
		PointElement,
		LineElement,
		BarElement,
		BarController,
		DoughnutController,
		LineController
	} from 'chart.js';

	// Register Chart.js components
	Chart.register(
		Title,
		Tooltip,
		Legend,
		ArcElement,
		CategoryScale,
		LinearScale,
		PointElement,
		LineElement,
		BarElement,
		BarController,
		DoughnutController,
		LineController
	);

	// State — كل البيانات من Firestore عبر /api/admin/aggregates/overview
	let loading = $state(true);
	let error = $state(null);
	let overview = $state(null);

	let distChart = $state();
	let distCanvas = $state();

	async function load() {
		loading = true;
		error = null;
		try {
			overview = await getDashboardOverview();
		} catch (err) {
			console.error('Dashboard error:', err);
			error = err.message || 'تعذّر تحميل الإحصائيات';
		} finally {
			loading = false;
		}
	}

	onMount(load);

	onDestroy(() => {
		if (distChart) distChart.destroy();
	});

	// ارسم المخطّط الدائري حين يصبح الـ canvas جاهزاً وبياناته متوفّرة
	$effect(() => {
		if (distCanvas && overview && !distChart) renderDistributionChart();
	});

	function renderDistributionChart() {
		if (!distCanvas || !overview) return;
		const bt = overview.byType || {};
		const ctx = distCanvas.getContext('2d');
		distChart = new Chart(ctx, {
			type: 'doughnut',
			data: {
				labels: [t('content.document'), t('content.audio'), t('content.video')],
				datasets: [{
					data: [bt.document || 0, bt.audio || 0, bt.video || 0],
					backgroundColor: ['#f59e0b', '#3b82f6', '#10b981'],
					borderWidth: 0,
					hoverOffset: 4
				}]
			},
			options: {
				responsive: true,
				maintainAspectRatio: false,
				plugins: { legend: { position: 'bottom', labels: { color: '#d4d4d8' } } },
				cutout: '70%'
			}
		});
	}
</script>

<svelte:head>
	<title>{t('common.dashboard')} — Nebras</title>
</svelte:head>

<div class="page-container">
	<div class="page-header">
		<div>
			<h1 class="page-title">{t('common.dashboard')}</h1>
			<p class="page-desc">{t('statistics.desc')}</p>
		</div>
	</div>

	{#if loading}
		<div class="loading-state">
			<span class="spinner-lg"></span>
			<p>{t('common.loading')}</p>
		</div>
	{:else if error}
		<div class="alert alert-error">{error}</div>
	{:else if overview}
		<!-- Numbers Overview Grid — أقسام رئيسي/فرعي/ثانوي + المحتوى -->
		<div class="stats-grid animate-fade-in">
			<div class="stat-card">
				<div class="stat-icon section"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2V6zM14 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2V6zM4 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2v-2zM14 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2v-2z" stroke-linecap="round" stroke-linejoin="round" /></svg></div>
				<div class="stat-content">
					<p class="stat-label">أقسام رئيسيّة</p>
					<h3 class="stat-value">{overview.sections?.main ?? 0}</h3>
				</div>
			</div>

			<div class="stat-card">
				<div class="stat-icon mod"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2V6zM14 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2h-2a2 2 0 01-2-2V6zM4 16a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2v-2z" stroke-linecap="round" stroke-linejoin="round" /></svg></div>
				<div class="stat-content">
					<p class="stat-label">أقسام فرعيّة</p>
					<h3 class="stat-value">{overview.sections?.sub ?? 0}</h3>
				</div>
			</div>

			<div class="stat-card">
				<div class="stat-icon chat"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 6a2 2 0 012-2h2a2 2 0 012 2v2a2 2 0 01-2 2H6a2 2 0 01-2-2V6z" stroke-linecap="round" stroke-linejoin="round" /></svg></div>
				<div class="stat-content">
					<p class="stat-label">أقسام ثانويّة</p>
					<h3 class="stat-value">{overview.sections?.secondary ?? 0}</h3>
				</div>
			</div>

			<div class="stat-card">
				<div class="stat-icon content"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10" stroke-linecap="round" stroke-linejoin="round" /></svg></div>
				<div class="stat-content">
					<p class="stat-label">إجمالي المحتوى</p>
					<h3 class="stat-value">{overview.content?.total ?? 0}</h3>
				</div>
			</div>
		</div>

		<!-- نوع المحتوى بالأرقام -->
		<div class="stats-grid animate-fade-in" style="animation-delay: 0.05s;">
			<div class="stat-card"><div class="stat-content"><p class="stat-label">{t('content.document')}</p><h3 class="stat-value">{overview.byType?.document ?? 0}</h3></div></div>
			<div class="stat-card"><div class="stat-content"><p class="stat-label">{t('content.audio')}</p><h3 class="stat-value">{overview.byType?.audio ?? 0}</h3></div></div>
			<div class="stat-card"><div class="stat-content"><p class="stat-label">{t('content.video')}</p><h3 class="stat-value">{overview.byType?.video ?? 0}</h3></div></div>
		</div>

		<!-- Charts Layer 1 -->
		<div class="charts-row animate-fade-in" style="animation-delay: 0.1s;">
			<!-- Distribution Doughnut -->
			<div class="chart-card">
				<h3 class="chart-title">{t('common.content_distribution')}</h3>
				<div class="chart-container pie-container">
					<canvas bind:this={distCanvas}></canvas>
				</div>
				<p class="ts-sub" style="text-align:center;margin-top:0.5rem;">
					من الأرشيف: {overview.content?.fromInternetArchive ?? 0} عنصر
				</p>
			</div>

			<!-- Top Sections List -->
			<div class="chart-card">
				<h3 class="chart-title">{t('common.top_sections')}</h3>
				<div class="top-sections-list">
					{#if !overview.topSections || overview.topSections.length === 0}
						<div class="empty-state">
							<p>{t('content.no_files')}</p>
						</div>
					{:else}
						{#each overview.topSections as section, i}
							<div class="top-section-item">
								<div class="ts-rank">#{i + 1}</div>
								<div class="ts-info">
									<p class="ts-name">{section.name}</p>
									<p class="ts-sub">{section.content_count} عنصر</p>
								</div>
								<div class="ts-bar">
									<div class="ts-bar-fill" style="width: {(section.content_count / overview.topSections[0].content_count) * 100}%"></div>
								</div>
							</div>
						{/each}
					{/if}
				</div>
			</div>
		</div>
	{/if}
</div>

<style>
	/* ─── Page Layout ───────────────────────────────── */
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
	}

	.stats-grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
		gap: 1.5rem;
		margin-bottom: 2rem;
	}

	.stat-card {
		background: var(--color-surface-800);
		border: 1px solid var(--color-surface-700);
		border-radius: 12px;
		padding: 1.5rem;
		display: flex;
		align-items: center;
		gap: 1.5rem;
		transition: transform 0.2s, box-shadow 0.2s;
	}

	.stat-card:hover {
		transform: translateY(-2px);
		box-shadow: 0 10px 15px -3px rgba(0, 0, 0, 0.5);
	}

	.stat-icon {
		width: 48px;
		height: 48px;
		border-radius: 12px;
		display: flex;
		align-items: center;
		justify-content: center;
	}

	.stat-icon svg {
		width: 24px;
		height: 24px;
	}

	.stat-icon.mod { background: rgba(16, 185, 129, 0.1); color: var(--color-primary-400); }
	.stat-icon.content { background: rgba(59, 130, 246, 0.1); color: #60a5fa; }
	.stat-icon.section { background: rgba(245, 158, 11, 0.1); color: #fbbf24; }
	.stat-icon.chat { background: rgba(239, 68, 68, 0.1); color: #f87171; }

	.stat-content {
		display: flex;
		flex-direction: column;
		gap: 0.25rem;
	}

	.stat-label {
		font-size: 0.875rem;
		color: var(--color-surface-400);
		font-weight: 500;
	}

	.stat-value {
		font-size: 1.5rem;
		font-weight: 700;
		color: var(--color-surface-50);
	}

	/* Charts */
	.charts-row {
		display: grid;
		grid-template-columns: 1fr;
		gap: 1.5rem;
		margin-bottom: 1.5rem;
	}

	@media (min-width: 1024px) {
		.charts-row {
			grid-template-columns: 1fr 1fr;
		}
		.chart-card.full-width {
			grid-column: span 2;
		}
	}

	.chart-card {
		background: var(--color-surface-800);
		border: 1px solid var(--color-surface-700);
		border-radius: 12px;
		padding: 1.5rem;
	}

	.chart-title {
		font-size: 1.125rem;
		font-weight: 600;
		color: var(--color-surface-50);
		margin-bottom: 1.5rem;
	}

	.chart-container {
		position: relative;
		width: 100%;
	}

	.pie-container {
		height: 280px;
	}

	.line-container {
		height: 320px;
	}

	/* Top Sections */
	.top-sections-list {
		display: flex;
		flex-direction: column;
		gap: 1rem;
		max-height: 280px;
		overflow-y: auto;
	}

	.top-section-item {
		display: flex;
		align-items: center;
		gap: 1rem;
		padding: 0.75rem;
		background: var(--color-surface-900);
		border-radius: 8px;
	}

	.ts-rank {
		font-weight: 700;
		color: var(--color-primary-400);
		font-size: 1.125rem;
		min-width: 2rem;
	}

	.ts-info {
		flex: 1;
		min-width: 0;
	}

	.ts-name {
		font-weight: 500;
		color: var(--color-surface-100);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	.ts-sub {
		font-size: 0.75rem;
		color: var(--color-surface-400);
		margin-top: 0.125rem;
	}

	.ts-bar {
		width: 100px;
		height: 6px;
		background: var(--color-surface-700);
		border-radius: 3px;
		overflow: hidden;
	}

	.ts-bar-fill {
		height: 100%;
		background: var(--color-primary-500);
		border-radius: 3px;
	}

</style>
