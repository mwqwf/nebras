<script>
	import { t } from '$lib/i18n/store.svelte.js';

	/** @type {{ view_count?: number; play_count?: number; complete_count?: number }} */
	let { stats = {} } = $props();

	const views = $derived(Number(stats?.view_count) || 0);
	const plays = $derived(Number(stats?.play_count) || 0);
	const completes = $derived(Number(stats?.complete_count) || 0);
	const visible = $derived(views > 0 || plays > 0 || completes > 0);
</script>

{#if visible}
	<span class="engagement-badge" title={t('content.engagement_tooltip')}>
		<span class="eng-stat" aria-label={t('content.engagement_views')}>👁 {views}</span>
		<span class="eng-sep">·</span>
		<span class="eng-stat" aria-label={t('content.engagement_plays')}>▶ {plays}</span>
		<span class="eng-sep">·</span>
		<span class="eng-stat" aria-label={t('content.engagement_completes')}>✓ {completes}</span>
	</span>
{/if}

<style>
	.engagement-badge {
		display: inline-flex;
		align-items: center;
		gap: 0.2rem;
		font-size: 0.72rem;
		color: var(--color-text-muted, #6b7280);
		white-space: nowrap;
	}
	.eng-sep {
		opacity: 0.55;
	}
</style>
