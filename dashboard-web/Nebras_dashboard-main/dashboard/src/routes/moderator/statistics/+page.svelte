<script>
	import PagePlaceholder from '$lib/components/PagePlaceholder.svelte';
	import { t } from '$lib/i18n/store.svelte.js';
</script>

<svelte:head>
	<title>{t('statistics.my_title')} — Nebras</title>
</svelte:head>

<PagePlaceholder
	title={t('statistics.my_title')}
	description={t('statistics.my_desc')}
	icon="stats"
/>
