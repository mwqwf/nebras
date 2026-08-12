<!--
  Root index — صفحة فارغة عمداً.
  حارس +layout.svelte يتكفّل بإعادة التوجيه:
    • غير مسجّل → /login
    • مصرّح له → /moderator/content/files
-->
<script>
	import LoadingScreen from '$lib/components/LoadingScreen.svelte';
</script>

<svelte:head>
	<title>Nebras Dashboard</title>
</svelte:head>

<LoadingScreen message="Loading" />
