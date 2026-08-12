<script>
	import { onMount, onDestroy } from 'svelte';
	import { t } from '$lib/i18n/store.svelte.js';
	import { getModeratorTotals, getModeratorContentDistribution, getModeratorContentAddedChart } from '$lib/api/moderator.js';

	// Chart.js imports
	import {
		Chart,
		Title,
		Tooltip,
		Legend,
		ArcElement,
		CategoryScale,
		LinearScale,
		BarElement,
		BarController,
		DoughnutController,
	} from 'chart.js';

	// Register Chart.js components
	Chart.register(
		Title,
		Tooltip,
		Legend,
		ArcElement,
		CategoryScale,
		LinearScale,
		BarElement,
		BarController,
		DoughnutController,
	);

	// State
	let loading = $state(true);
	let error = $state(null);

	let totals = $state({});
	let distributionData = $state({});
	let contentChartData = $state([]);

	// Chart instances
	let distChart = $state();
	let contentChart = $state();

	// Canvas references
	let distCanvas = $state();
	let contentCanvas = $state();

	onMount(async () => {
		try {
			// Fetch all dashboard data concurrently
			const [tData, dData, ccData] = await Promise.all([
				getModeratorTotals(),
				getModeratorContentDistribution(),
				getModeratorContentAddedChart()
			]);

			totals = tData;
			distributionData = dData;
			contentChartData = ccData.data || [];

		} catch (err) {
			console.error("Dashboard error:", err);
			error = err.message || "Failed to load dashboard statistics";
		} finally {
			loading = false;
		}
	});

	onDestroy(() => {
		if (distChart) distChart.destroy();
		if (contentChart) contentChart.destroy();
	});

	// Re-run safely whenever the canvas nodes are mounted by Svelte after `loading` becomes false
	$effect(() => {
		if (distCanvas && !distChart) renderDistributionChart();
		if (contentCanvas && !contentChart) renderContentChart();
	});

	function renderDistributionChart() {
		if (!distCanvas) return;
		const ctx = distCanvas.getContext('2d');
		
		distChart = new Chart(ctx, {
			type: 'doughnut',
			data: {
				labels: [t('content.video'), t('content.audio'), t('content.document')],
				datasets: [{
					data: [
						distributionData.video || 0,
						distributionData.audio || 0,
						distributionData.document || 0
					],
					backgroundColor: [
						'#10b981', // Primary green
						'#3b82f6', // Blue
						'#f59e0b'  // Gold
					],
					borderWidth: 0,
					hoverOffset: 4
				}]
			},
			options: {
				responsive: true,
				maintainAspectRatio: false,
				plugins: {
					legend: {
						position: 'bottom',
						labels: { color: '#d4d4d8' }
					}
				},
				cutout: '70%'
			}
		});
	}

	function renderContentChart() {
		if (!contentCanvas) return;
		const ctx = contentCanvas.getContext('2d');

		// Group by date and type for the bar chart
		const dates = [...new Set(contentChartData.map(d => d.date))].sort();
		const labels = dates.map(d => formatDateShort(d));

		const types = ['video', 'audio', 'document'];
		const bgColors = {
			video: '#10b981',
			audio: '#3b82f6',
			document: '#f59e0b'
		};
		const translatedLabels = {
			video: t('content.video'),
			audio: t('content.audio'),
			document: t('content.document')
		};

		const datasets = types.map(type => {
			const data = dates.map(date => {
				const entry = contentChartData.find(d => d.date === date && d.content_type === type);
				return entry ? entry.count : 0;
			});
			return {
				label: translatedLabels[type],
				data: data,
				backgroundColor: bgColors[type],
				borderRadius: 4
			};
		});

		contentChart = new Chart(ctx, {
			type: 'bar',
			data: {
				labels: labels,
				datasets: datasets
			},
			options: {
				responsive: true,
				maintainAspectRatio: false,
				plugins: {
					legend: { position: 'bottom', labels: { color: '#d4d4d8' } },
					tooltip: {
						mode: 'index',
						intersect: false,
					}
				},
				scales: {
					x: { stacked: true, grid: { display: false }, ticks: { color: '#a1a1aa' } },
					y: { stacked: true, beginAtZero: true, grid: { color: '#3f3f46' }, ticks: { color: '#a1a1aa', stepSize: 1 } }
				}
			}
		});
	}

	function formatDateShort(dateString) {
		const d = new Date(dateString);
		return d.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
	}

</script>

<svelte:head>
	<title>{t('common.dashboard')} — Nebras</title>
</svelte:head>

<div class="page-container">
	<div class="page-header">
		<div>
			<h1 class="page-title">{t('common.dashboard')}</h1>
			<p class="page-desc">{t('moderator.dashboard_desc')}</p>
		</div>
	</div>

	{#if loading}
		<div class="loading-state">
			<span class="spinner-lg"></span>
			<p>{t('common.loading')}</p>
		</div>
	{:else if error}
		<div class="alert alert-error">{error}</div>
	{:else}
		<!-- Numbers Overview Grid -->
		<div class="stats-grid animate-fade-in">
			<div class="stat-card">
				<div class="stat-icon content"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10" stroke-linecap="round" stroke-linejoin="round" /></svg></div>
				<div class="stat-content">
					<p class="stat-label">{t('common.total_content')}</p>
					<h3 class="stat-value">{totals.total_content_items || 0}</h3>
				</div>
			</div>

			<div class="stat-card">
				<div class="stat-icon chat"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z" stroke-linecap="round" stroke-linejoin="round" /></svg></div>
				<div class="stat-content">
					<p class="stat-label">{t('common.total_sections')}</p>
					<h3 class="stat-value">{totals.total_sections || 0}</h3>
				</div>
			</div>
		</div>

		<!-- Charts Layer -->
		<div class="charts-row animate-fade-in" style="animation-delay: 0.1s;">
			<!-- Distribution Doughnut -->
			<div class="chart-card">
				<h3 class="chart-title">{t('common.content_distribution')}</h3>
				<div class="chart-container pie-container">
					<canvas bind:this={distCanvas}></canvas>
				</div>
			</div>

			<!-- Content Timeline -->
			<div class="chart-card full-width">
				<h3 class="chart-title">{t('common.upload_activity')} (30 Days)</h3>
				<div class="chart-container line-container">
					<canvas bind:this={contentCanvas}></canvas>
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

	.stat-icon.content { background: rgba(59, 130, 246, 0.1); color: #60a5fa; }
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
			grid-template-columns: 1fr 2fr;
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
</style>
