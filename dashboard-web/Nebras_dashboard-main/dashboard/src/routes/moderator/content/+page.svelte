<script>
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import { t } from '$lib/i18n/store.svelte.js';
	
	onMount(() => { goto('/moderator/content/files', { replaceState: true }); });
</script>
<svelte:head><title>{t('content.title')} — Nebras</title></svelte:head>
<div style="display:flex;align-items:center;justify-content:center;height:200px;color:var(--color-surface-500);">
	<div class="spinner"></div><span style="margin-inline-start:0.75rem;">{t('common.loading')}</span>
</div>
<style>.spinner{width:24px;height:24px;border:3px solid var(--color-surface-700);border-top-color:var(--color-primary-500);border-radius:50%;animation:spin .6s linear infinite}@keyframes spin{to{transform:rotate(360deg)}}</style>
