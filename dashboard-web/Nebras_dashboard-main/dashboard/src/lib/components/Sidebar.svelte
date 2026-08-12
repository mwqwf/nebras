<!--
  Sidebar.svelte — Dashboard navigation sidebar
  Layout: Logo top → Nav middle (scrollable) → User + Logout bottom
  Matches the Futirify-style reference layout.
-->

<script>
	import { getAuthState } from '$lib/stores/auth.svelte.js';
	import { logout } from '$lib/api/auth.js';
	import { goto } from '$app/navigation';
	import { page } from '$app/state';
	import { t } from '$lib/i18n/store.svelte.js';

	let { isOpen = $bindable(false) } = $props();

	const authState = getAuthState();

	let currentPath = $derived(page.url?.pathname || '');

	let displayName = $derived(
		authState.user?.displayName?.trim() ||
			(authState.user?.email ? authState.user.email.split('@')[0] : 'User')
	);
	let userEmail = $derived(authState.user?.email || '');
	let userPhoto = $derived(authState.user?.photoURL || '');

	async function handleLogout() {
		await logout();
		goto('/login');
	}

	// ─── Menu Items ────────────────────────────────────────
	// getAuthState() داخل $derived.by لضمان إعادة بناء القائمة عند تحديث role/authorized.
	let menuItems = $derived.by(() => {
		const { role } = getAuthState();
		return [
			{ label: t('common.dashboard'), href: '/moderator', icon: 'dashboard' },
			{ label: t('common.sections'), href: '/moderator/sections', icon: 'sections' },
			{ label: t('common.content'), href: '/moderator/content/files', icon: 'content' },
			{ label: t('content.multi_upload'), href: '/moderator/content/multi', icon: 'multiUpload' },
			{ label: 'جلب من مكتبة نور', href: '/moderator/content/import-noor', icon: 'noorImport' },
			{ label: t('common.chat'), href: '/moderator/chat', icon: 'chat' },
			...(role === 'owner'
				? [
						{
							label: 'إدارة المشرفين',
							href: '/admin/users/supervisors',
							icon: 'supervisors'
						},
						{
							label: 'Crawl4AI',
							href: '/admin/crawl4ai',
							icon: 'crawl'
						},
						{
							label: 'Internet Archive',
							href: '/admin/internet-archive',
							icon: 'archive'
						},
						{
							label: 'مكتبة نور',
							href: '/admin/noor-library',
							icon: 'noorImport'
						},
						{
							label: 'مؤسسة هنداوي',
							href: '/admin/hindawi-library',
							icon: 'content'
						},
						{
							label: 'الإحصاءات',
							href: '/admin/statistics',
							icon: 'stats'
						},
						{
							label: 'بلاغات المحتوى',
							href: '/admin/reports',
							icon: 'reports'
						},
						{
							label: 'تدقيق المحتوى',
							href: '/admin/content-audit',
							icon: 'audit'
						}
					]
				: [])
		];
	});

	function isActive(href) {
		if (!href) return false;
		if (href === '/moderator') {
			return currentPath === href;
		}
		return currentPath.startsWith(href);
	}

	function hasActiveChild(item) {
		if (!item.children) return false;
		return item.children.some((child) => isActive(child.href));
	}

	function handleNavClick() {
		if (window.innerWidth <= 1024) {
			isOpen = false;
		}
	}

	const icons = {
		dashboard: 'M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6',
		stats: 'M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z',
		sections: 'M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10',
		content: 'M7 21h10a2 2 0 002-2V9.414a1 1 0 00-.293-.707l-5.414-5.414A1 1 0 0012.586 3H7a2 2 0 00-2 2v14a2 2 0 002 2z',
		multiUpload: 'M4 16v2a2 2 0 002 2h12a2 2 0 002-2v-2M8 10l4-4 4 4M12 6v10',
		noorImport: 'M4 19.5A2.5 2.5 0 016.5 17H20M4 4.5A2.5 2.5 0 016.5 2H20v20H6.5A2.5 2.5 0 014 19.5zM9 7l3 3 3-3',
		chat: 'M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z',
		supervisors: 'M17 20h5v-2a4 4 0 00-3-3.87M9 20H4v-2a4 4 0 013-3.87m6 5.87v-2a4 4 0 00-4-4H8a4 4 0 00-4 4v2m12-10a4 4 0 11-8 0 4 4 0 018 0z',
		crawl: 'M8 9l3 3-3 3m5 0h3M5 20h14a2 2 0 002-2V6a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z',
		archive:
			'M4 7v10c0 2.21 3.582 4 8 4s8-1.79 8-4V7M4 7c0 2.21 3.582 4 8 4s8-1.79 8-4M4 7c0-2.21 3.582-4 8-4s8 1.79 8 4m0 5c0 2.21-3.582 4-8 4s-8-1.79-8-4',
		reports:
			'M3 21v-4m0 0V5a2 2 0 012-2h6.5l1 2H20l-3 6 3 6h-7.5l-1-2H5a2 2 0 00-2 2z',
		audit:
			'M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z'
	};
</script>

<aside class="sidebar {isOpen ? 'open' : ''}" id="sidebar">
	<!-- ─── Top: Logo ────────────────────────────── -->
	<div class="sidebar-top">
		<a href="/moderator" class="app-brand">
			<div class="brand-icon">
				<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
					<path d="M12 3L2 12h3v8h6v-6h2v6h6v-8h3L12 3z" />
				</svg>
			</div>
			<span class="brand-name">Nebras</span>
		</a>
	</div>

	<!-- ─── Middle: Navigation (scrollable) ──────── -->
	<nav class="sidebar-nav" id="sidebar-nav">
		{#each menuItems as item}
			{#if item.children}
				<!-- Parent with children -->
				<div class="nav-group" class:active={hasActiveChild(item)}>
					<div class="nav-group-label">
						<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
							stroke-linecap="round" stroke-linejoin="round" class="nav-icon">
							<path d={icons[item.icon]} />
						</svg>
						<span>{item.label}</span>
					</div>
					<div class="nav-children">
						{#each item.children as child}
							<a
								href={child.href}
								class="nav-child-link"
								class:active={isActive(child.href)}
								onclick={handleNavClick}
							>
								<span class="child-dot"></span>
								<span>{child.label}</span>
							</a>
						{/each}
					</div>
				</div>
			{:else}
				<!-- Single link -->
				<a
					href={item.href}
					class="nav-link"
					class:active={isActive(item.href)}
					onclick={handleNavClick}
				>
					<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
						stroke-linecap="round" stroke-linejoin="round" class="nav-icon">
						<path d={icons[item.icon]} />
					</svg>
					<span>{item.label}</span>
				</a>
			{/if}
		{/each}
	</nav>

	<!-- ─── Bottom: User + Logout ───── -->
	<div class="sidebar-bottom">
		<div class="user-info">
			<div class="avatar">
				{#if userPhoto}
					<img src={userPhoto} alt="Avatar" referrerpolicy="no-referrer" />
				{:else}
					<span class="avatar-letter">{displayName.charAt(0).toUpperCase()}</span>
				{/if}
			</div>
			<div class="user-details">
				<span class="user-name">{displayName}</span>
				<span class="user-email">{userEmail}</span>
			</div>
		</div>

		<button type="button" class="logout-btn" onclick={handleLogout}>
			<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
				stroke-linecap="round" stroke-linejoin="round">
				<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4" />
				<polyline points="16 17 21 12 16 7" />
				<line x1="21" y1="12" x2="9" y2="12" />
			</svg>
			<span>{t('auth.logout')}</span>
		</button>
	</div>
</aside>

<style>
	/* ─── Sidebar Shell ──────────────────────────── */
	.sidebar {
		position: fixed;
		top: 0;
		inset-inline-start: 0;
		bottom: 0;
		width: 240px;
		background: var(--color-sidebar-bg);
		border-inline-end: 1px solid var(--color-sidebar-border);
		display: flex;
		flex-direction: column;
		z-index: 50;
		transition: transform 0.3s ease;
	}

	/* Mobile styles */
	@media (max-width: 1024px) {
		.sidebar {
			transform: translateX(-100%);
		}

		/* The default is LTR, so -100% hides it. 
		   If the layout is RTL (Arabic), maybe it needs different translation, 
		   but let's use standard -100% or we can rely on logical properties but transform doesn't have logical variants yet without using `html[dir="rtl"]`. 
		   Let's check if the current project supports RTL. */
		:global(html[dir='rtl']) .sidebar {
			transform: translateX(100%);
		}

		.sidebar.open {
			transform: translateX(0) !important;
		}
	}

	/* ─── Top: Brand ─────────────────────────────── */
	.sidebar-top {
		padding: 1.25rem 1rem;
		border-bottom: 1px solid var(--color-sidebar-border);
	}

	.app-brand {
		display: flex;
		align-items: center;
		gap: 0.75rem;
		text-decoration: none;
	}

	.brand-icon {
		width: 36px;
		height: 36px;
		background: linear-gradient(135deg, var(--color-primary-700), var(--color-primary-500));
		border-radius: 10px;
		display: flex;
		align-items: center;
		justify-content: center;
		color: white;
		flex-shrink: 0;
	}

	.brand-icon svg {
		width: 18px;
		height: 18px;
	}

	.brand-name {
		font-size: 1.25rem;
		font-weight: 800;
		background: linear-gradient(135deg, var(--color-primary-300), var(--color-primary-100));
		-webkit-background-clip: text;
		-webkit-text-fill-color: transparent;
		background-clip: text;
		letter-spacing: -0.02em;
	}

	/* ─── Middle: Navigation ──────────────────────── */
	.sidebar-nav {
		flex: 1;
		overflow-y: auto;
		padding: 0.75rem 0.625rem;
		display: flex;
		flex-direction: column;
		gap: 2px;
	}

	/* Single nav link */
	.nav-link {
		display: flex;
		align-items: center;
		gap: 0.75rem;
		padding: 0.625rem 0.75rem;
		border-radius: 8px;
		text-decoration: none;
		color: var(--color-surface-400);
		font-size: 0.8125rem;
		font-weight: 500;
		transition: all 0.15s ease;
	}

	.nav-link:hover {
		background: var(--color-sidebar-hover);
		color: var(--color-surface-200);
	}

	.nav-link.active {
		background: var(--color-sidebar-active);
		color: var(--color-primary-400);
		font-weight: 600;
	}

	.nav-icon {
		width: 20px;
		height: 20px;
		flex-shrink: 0;
		stroke-width: 1.75;
	}

	/* Nav group (parent + children) */
	.nav-group-label {
		display: flex;
		align-items: center;
		gap: 0.75rem;
		padding: 0.625rem 0.75rem;
		color: var(--color-surface-400);
		font-size: 0.8125rem;
		font-weight: 500;
	}

	.nav-group.active .nav-group-label {
		color: var(--color-surface-200);
	}

	.nav-children {
		padding-inline-start: 1rem;
		display: flex;
		flex-direction: column;
		gap: 1px;
	}

	.nav-child-link {
		display: flex;
		align-items: center;
		gap: 0.625rem;
		padding: 0.5rem 0.75rem;
		border-radius: 8px;
		text-decoration: none;
		color: var(--color-surface-500);
		font-size: 0.8125rem;
		transition: all 0.15s ease;
	}

	.nav-child-link:hover {
		background: var(--color-sidebar-hover);
		color: var(--color-surface-300);
	}

	.nav-child-link.active {
		color: var(--color-primary-400);
		font-weight: 600;
	}

	.child-dot {
		width: 5px;
		height: 5px;
		border-radius: 50%;
		background: var(--color-surface-600);
		flex-shrink: 0;
	}

	.nav-child-link.active .child-dot {
		background: var(--color-primary-500);
	}

	/* ─── Bottom: User ──────────── */
	.sidebar-bottom {
		padding: 0.75rem;
		border-top: 1px solid var(--color-sidebar-border);
		display: flex;
		flex-direction: column;
		gap: 0.5rem;
	}

	/* User info */
	.user-info {
		display: flex;
		align-items: center;
		gap: 0.75rem;
		padding: 0.5rem;
		text-decoration: none;
		border-radius: 10px;
		cursor: pointer;
		transition: background 0.15s;
	}
	.user-info:hover {
		background: var(--color-surface-700);
	}

	.avatar {
		width: 36px;
		height: 36px;
		border-radius: 50%;
		overflow: hidden;
		background: linear-gradient(135deg, var(--color-primary-700), var(--color-primary-500));
		display: flex;
		align-items: center;
		justify-content: center;
		flex-shrink: 0;
	}

	.avatar img {
		width: 100%;
		height: 100%;
		object-fit: cover;
	}

	.avatar-letter {
		font-size: 0.875rem;
		font-weight: 700;
		color: white;
	}

	.user-details {
		display: flex;
		flex-direction: column;
		min-width: 0;
	}

	.user-name {
		font-size: 0.8125rem;
		font-weight: 600;
		color: var(--color-surface-200);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.user-email {
		font-size: 0.6875rem;
		color: var(--color-surface-500);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.logout-btn {
		display: flex;
		align-items: center;
		gap: 0.625rem;
		width: 100%;
		padding: 0.55rem 0.75rem;
		border-radius: 10px;
		border: 1px solid var(--color-surface-700);
		background: transparent;
		color: var(--color-surface-300);
		font-size: 0.8125rem;
		font-weight: 600;
		cursor: pointer;
		transition: background 0.15s ease, color 0.15s ease, border-color 0.15s ease;
	}
	.logout-btn:hover {
		background: rgba(220, 38, 38, 0.12);
		border-color: rgba(220, 38, 38, 0.4);
		color: #fecaca;
	}
	.logout-btn svg {
		width: 16px;
		height: 16px;
		flex-shrink: 0;
	}

</style>
