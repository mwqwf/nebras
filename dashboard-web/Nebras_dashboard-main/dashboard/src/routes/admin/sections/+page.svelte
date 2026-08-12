<script>
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';

	onMount(() => {
		goto('/moderator/sections', { replaceState: true });
	});
</script>

<svelte:head>
	<title>Redirecting — Nebras</title>
</svelte:head>
