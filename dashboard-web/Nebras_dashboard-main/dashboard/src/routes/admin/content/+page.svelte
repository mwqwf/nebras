<script>
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	onMount(() => { goto('/moderator/content/files', { replaceState: true }); });
</script>
<svelte:head><title>Content Management â€” Nebras</title></svelte:head>
<div style="display:flex;align-items:center;justify-content:center;height:200px;color:var(--color-surface-500);">
	<div class="spinner"></div><span style="margin-left:0.75rem;">Loading...</span>
</div>
<style>.spinner{width:24px;height:24px;border:3px solid var(--color-surface-700);border-top-color:var(--color-primary-500);border-radius:50%;animation:spin .6s linear infinite}@keyframes spin{to{transform:rotate(360deg)}}</style>

