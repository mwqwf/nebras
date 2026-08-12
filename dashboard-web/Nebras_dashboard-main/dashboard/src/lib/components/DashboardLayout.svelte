<!--
  DashboardLayout.svelte — Shell layout
  Left sidebar (240px) + top header bar + scrollable main content.
  Matches the Futirify-style layout reference.
-->

<script>
	import Sidebar from './Sidebar.svelte';
	import MultiUploadIndicator from './MultiUploadIndicator.svelte';
	import { getAuthState } from '$lib/stores/auth.svelte.js';
	import { toggleLanguage, getLanguage, t } from '$lib/i18n/store.svelte.js';
	import { goto } from '$app/navigation';

	let { children } = $props();

	const authState = getAuthState();
	let searchQuery = $state('');
	let isSidebarOpen = $state(false);

	function submitGlobalSearch(e) {
		e?.preventDefault?.();
		const q = String(searchQuery || '').trim();
		if (!q) return;
		goto(`/search?q=${encodeURIComponent(q)}`);
	}

	function handleSearchKey(e) {
		if (e.key === 'Enter') submitGlobalSearch(e);
		else if (e.key === 'Escape') searchQuery = '';
	}
</script>

<div class="dashboard-layout" id="dashboard-layout">
	<Sidebar bind:isOpen={isSidebarOpen} />

	<!-- Mobile Sidebar Overlay -->
	{#if isSidebarOpen}
		<!-- svelte-ignore a11y_click_events_have_key_events -->
		<!-- svelte-ignore a11y_no_static_element_interactions -->
		<div class="sidebar-overlay" onclick={() => isSidebarOpen = false}></div>
	{/if}

	<div class="main-wrapper">
		<!-- Top Header Bar -->
		<header class="top-header" id="top-header">
			<div class="header-left">
				<button class="header-icon-btn hamburger-btn" onclick={() => isSidebarOpen = true} title="Open Sidebar">
					<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
						<line x1="3" y1="12" x2="21" y2="12"></line>
						<line x1="3" y1="6" x2="21" y2="6"></line>
						<line x1="3" y1="18" x2="21" y2="18"></line>
					</svg>
				</button>
				<form class="search-box" onsubmit={submitGlobalSearch} role="search">
					<button type="submit" class="search-icon-btn" aria-label={t('common.search_btn')} title={t('common.search_btn')}>
						<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
							stroke-linecap="round" stroke-linejoin="round" class="search-icon">
							<path d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
						</svg>
					</button>
					<input
						type="text"
						placeholder={t('common.search_global_placeholder')}
						bind:value={searchQuery}
						onkeydown={handleSearchKey}
						class="search-input"
						id="search-input"
					/>
					{#if searchQuery}
						<button type="button" class="search-clear-btn" aria-label={t('common.search_clear')} onclick={() => { searchQuery = ''; }}>
							<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 18L18 6M6 6l12 12" /></svg>
						</button>
					{/if}
				</form>
			</div>

			<div class="header-right">
				<button class="header-icon-btn lang-btn" onclick={toggleLanguage} title="Change Language">
					{getLanguage() === 'ar' ? 'EN' : 'عربي'}
				</button>

				<!-- Notification bell -->
				<button class="header-icon-btn" id="notifications-btn" title="Notifications">
					<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
						stroke-linecap="round" stroke-linejoin="round">
						<path d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9" />
					</svg>
				</button>

				<!-- User avatar in header -->
				<div class="header-user">
					<div class="header-avatar">
						{#if authState.user?.photoURL}
							<img src={authState.user.photoURL} alt="Avatar" referrerpolicy="no-referrer" />
						{:else}
							<span>{((authState.user?.displayName || authState.user?.email || 'U')).charAt(0).toUpperCase()}</span>
						{/if}
					</div>
				</div>
			</div>
		</header>

		<!-- Main Content Area -->
		<main class="main-content" id="main-content">
			<div class="content-inner animate-fade-in">
				{@render children()}
			</div>
		</main>
	</div>

	<!-- Floating multi-upload progress indicator (visible across dashboard pages) -->
	<MultiUploadIndicator />
</div>

<style>
	.dashboard-layout {
		display: flex;
		min-height: 100vh;
	}

	.main-wrapper {
		flex: 1;
		margin-inline-start: 240px;
		display: flex;
		flex-direction: column;
		min-height: 100vh;
		background: var(--color-surface-900);
		transition: margin-inline-start 0.3s ease;
		min-width: 0;
	}

	.sidebar-overlay {
		display: none;
		position: fixed;
		inset: 0;
		background: rgba(0, 0, 0, 0.5);
		z-index: 45;
		backdrop-filter: blur(2px);
	}

	/* ─── Top Header ─────────────────────────────────── */
	.top-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: 0.75rem 2rem;
		background: var(--color-surface-900);
		border-bottom: 1px solid var(--color-surface-700);
		position: sticky;
		top: 0;
		z-index: 40;
		gap: 1rem;
	}

	.header-left {
		flex: 1;
		max-width: 480px;
		display: flex;
		align-items: center;
		gap: 0.75rem;
	}

	.hamburger-btn {
		display: none;
	}

	.search-box {
		display: flex;
		align-items: center;
		gap: 0.5rem;
		padding: 0.5rem 0.875rem;
		background: var(--color-surface-800);
		border: 1px solid var(--color-surface-700);
		border-radius: 10px;
		transition: all 0.2s ease;
	}

	.search-box:focus-within {
		border-color: var(--color-primary-600);
		box-shadow: 0 0 0 3px rgba(5, 150, 105, 0.1);
	}

	.search-icon {
		width: 18px;
		height: 18px;
		color: var(--color-surface-500);
		flex-shrink: 0;
	}

	.search-icon-btn, .search-clear-btn {
		background: none;
		border: none;
		padding: 0;
		color: var(--color-surface-400);
		cursor: pointer;
		display: inline-flex;
		align-items: center;
		justify-content: center;
	}
	.search-icon-btn:hover, .search-clear-btn:hover {
		color: var(--color-surface-100);
	}
	.search-clear-btn svg {
		width: 14px;
		height: 14px;
	}

	.search-input {
		flex: 1;
		background: none;
		border: none;
		outline: none;
		color: var(--color-surface-100);
		font-size: 0.8125rem;
		font-family: inherit;
	}

	.search-input::placeholder {
		color: var(--color-surface-500);
	}

	.header-right {
		display: flex;
		align-items: center;
		gap: 0.5rem;
	}

	.header-icon-btn {
		width: 38px;
		height: 38px;
		display: flex;
		align-items: center;
		justify-content: center;
		border-radius: 10px;
		border: 1px solid var(--color-surface-700);
		background: var(--color-surface-800);
		color: var(--color-surface-400);
		cursor: pointer;
		transition: all 0.15s ease;
	}

	.header-icon-btn:hover {
		background: var(--color-surface-700);
		color: var(--color-surface-200);
	}

	.header-icon-btn svg {
		width: 18px;
		height: 18px;
	}

	.lang-btn {
		font-size: 0.75rem;
		font-weight: 700;
	}

	.header-user {
		margin-inline-start: 0.25rem;
	}

	.header-avatar {
		width: 34px;
		height: 34px;
		border-radius: 50%;
		background: linear-gradient(135deg, var(--color-primary-700), var(--color-primary-500));
		display: flex;
		align-items: center;
		justify-content: center;
		overflow: hidden;
		border: 2px solid var(--color-surface-700);
	}

	.header-avatar img {
		width: 100%;
		height: 100%;
		object-fit: cover;
	}

	.header-avatar span {
		font-size: 0.8125rem;
		font-weight: 700;
		color: white;
	}

	/* ─── Main Content ───────────────────────────────── */
	.main-content {
		flex: 1;
		min-width: 0;
	}

	.content-inner {
		padding: 1.5rem 2rem;
		max-width: 1400px;
		min-width: 0;
	}

	/* ─── Media Queries (Responsive) ─────────────────── */
	@media (max-width: 1024px) {
		.main-wrapper {
			margin-inline-start: 0;
		}

		.hamburger-btn {
			display: flex;
		}

		.sidebar-overlay {
			display: block;
		}
	}

	@media (max-width: 640px) {
		.top-header {
			padding: 0.75rem 1rem;
		}

		.content-inner {
			padding: 1rem;
		}

		.search-box {
			display: none; /* Optionally hide search box on very small screens, or adjust width */
		}
	}
</style>
