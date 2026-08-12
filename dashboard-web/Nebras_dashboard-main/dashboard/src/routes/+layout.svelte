<!--
  Root Layout — حارس المصادقة.

  عند الإقلاع:
   1) نُهيّئ Firebase (Analytics/DB/Storage/Auth).
   2) نُشغّل مُستمع onAuthStateChanged الموحّد (في api/auth.js).
   3) أثناء التحميل نعرض LoadingScreen.
   4) بعد الانتهاء:
       • إذا كان المستخدم غير موقّع → ندفعه إلى /login (إلّا إذا كان هناك).
       • إذا كان موقّعاً لكن غير مصرّح (needsOwnerCode) → /login للرمز.
       • إذا كان مصرّحاً ومسار الجذر → ندخله للوحة التحكّم مباشرةً.
-->

<script>
	import { onMount, onDestroy } from 'svelte';
	import { getAuthState, setLoading } from '$lib/stores/auth.svelte.js';
	import { startAuthListener, completeGoogleRedirectSignIn } from '$lib/api/auth.js';
	import { goto } from '$app/navigation';
	import { page } from '$app/state';
	import LoadingScreen from '$lib/components/LoadingScreen.svelte';
	import { setLanguage, getLanguage, getDir } from '$lib/i18n/store.svelte.js';
	import { initFirebase } from '$lib/firebase/client.js';
	import '../app.css';

	let { children } = $props();

	const authState = getAuthState();
	let currentDir = $derived(getDir());
	let unsubscribe = null;
	let bootstrapTimeoutId = null;

	function isPublicPath(path) {
		return path === '/login' || path.startsWith('/login/');
	}

	$effect(() => {
		if (authState.isLoading) return;

		const currentPath = page.url?.pathname || '/';

		// محظور (تم تعليق وصوله) → دائماً /login?blocked=1.
		if (authState.isBlocked) {
			if (currentPath !== '/login') goto('/login?blocked=1');
			return;
		}

		// مستخدم غير موقّع → /login (إن لم يكن هناك أصلاً).
		if (!authState.user) {
			if (!isPublicPath(currentPath)) goto('/login');
			return;
		}

		// موقّع لكن جديد (يحتاج رمز المالك) → /login مرحلة الرمز.
		if (!authState.authorized) {
			if (!isPublicPath(currentPath)) goto('/login');
			return;
		}

		// مصرّح له — إذا كان على /login أو /، انقله للوحة التحكّم.
		if (currentPath === '/' || isPublicPath(currentPath)) {
			goto('/moderator/content/files');
		}
	});

	onMount(async () => {
		// Safety net: لو علقت أيّ خطوة (شبكة بطيئة، Firebase config مفقود،
		// /api/auth/check لا يستجيب) لا نترك المستخدم خلف LoadingScreen
		// إلى ما لا نهاية. 8 ثوان كافية لـ Firebase init + completeRedirect
		// + checkAuth حتى على شبكات بطيئة.
		bootstrapTimeoutId = setTimeout(() => {
			if (authState.isLoading) {
				console.warn('[auth] bootstrap timeout — forcing loading=false');
				setLoading(false);
			}
		}, 8000);

		try {
			await initFirebase();
			setLanguage(getLanguage());
			// يجب استدعاء getRedirectResult قبل onAuthStateChanged حتى لا تبقى
			// نتيجة التحويل عالقة؛ وإلا قد يبقى isLoading=true ولا تُعرض صفحة
			// /login أبداً فيتخطّى المستخدم استهلاك redirect بالكامل.
			// (يُستعمل فقط حين فشل popup ولجأنا إلى redirect.)
			await completeGoogleRedirectSignIn();
		} catch (err) {
			console.error('[auth] bootstrap step failed:', err);
		} finally {
			unsubscribe = startAuthListener();
		}
	});

	onDestroy(() => {
		if (typeof unsubscribe === 'function') unsubscribe();
		if (bootstrapTimeoutId) {
			clearTimeout(bootstrapTimeoutId);
			bootstrapTimeoutId = null;
		}
	});
</script>

<svelte:head>
	<title>Nebras Dashboard</title>
</svelte:head>

{#if authState.isLoading}
	<LoadingScreen message="Authenticating" />
{:else}
	<div dir={currentDir} style="display: contents;">
		{@render children()}
	</div>
{/if}
