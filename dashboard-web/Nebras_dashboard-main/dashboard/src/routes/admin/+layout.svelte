<!--
  Admin Layout — Dashboard shell only (no role split).
-->

<script>
	import { onMount } from 'svelte';
	import DashboardLayout from '$lib/components/DashboardLayout.svelte';
	import LoadingScreen from '$lib/components/LoadingScreen.svelte';

	let { children } = $props();
	let ready = $state(false);

	onMount(() => {
		ready = true;
	});
</script>

{#if ready}
	<DashboardLayout>
		{@render children()}
	</DashboardLayout>
{:else}
	<LoadingScreen message="Loading" />
{/if}
