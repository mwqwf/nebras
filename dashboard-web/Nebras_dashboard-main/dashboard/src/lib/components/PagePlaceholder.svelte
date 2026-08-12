<!--
  PagePlaceholder.svelte — Reusable placeholder for unbuilt pages
  Shows a styled card with title, description, and a status badge.
-->

<script>
	let { title = 'Page', description = 'Coming soon', icon = 'page' } = $props();

	const iconPaths = {
		dashboard:
			'M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6',
		stats: 'M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z',
		users:
			'M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z',
		sections:
			'M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10',
		content:
			'M7 21h10a2 2 0 002-2V9.414a1 1 0 00-.293-.707l-5.414-5.414A1 1 0 0012.586 3H7a2 2 0 00-2 2v14a2 2 0 002 2z',
		chat: 'M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z',
		ban: 'M18.364 18.364A9 9 0 005.636 5.636m12.728 12.728A9 9 0 015.636 5.636m12.728 12.728L5.636 5.636',
		page: 'M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z'
	};
</script>

<div class="placeholder-page">
	<div class="placeholder-card">
		<!-- Icon -->
		<div class="placeholder-icon">
			<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
				<path d={iconPaths[icon] || iconPaths.page} />
			</svg>
		</div>

		<!-- Title -->
		<h1 class="placeholder-title">{title}</h1>

		<!-- Description -->
		<p class="placeholder-desc">{description}</p>

		<!-- Status badge -->
		<div class="status-badge">
			<span class="status-dot"></span>
			Planned
		</div>
	</div>
</div>

<style>
	.placeholder-page {
		display: flex;
		align-items: center;
		justify-content: center;
		min-height: calc(100vh - 4rem);
	}

	.placeholder-card {
		display: flex;
		flex-direction: column;
		align-items: center;
		text-align: center;
		padding: 3rem;
		max-width: 480px;
		background: var(--color-surface-800);
		border: 1px solid var(--color-surface-700);
		border-radius: 16px;
		box-shadow: var(--shadow-card);
	}

	.placeholder-icon {
		width: 64px;
		height: 64px;
		background: linear-gradient(135deg, var(--color-primary-900), var(--color-primary-800));
		border: 1px solid var(--color-primary-700);
		border-radius: 16px;
		display: flex;
		align-items: center;
		justify-content: center;
		color: var(--color-primary-400);
		margin-bottom: 1.5rem;
	}

	.placeholder-icon svg {
		width: 28px;
		height: 28px;
	}

	.placeholder-title {
		font-size: 1.5rem;
		font-weight: 700;
		color: var(--color-surface-100);
		margin-bottom: 0.75rem;
		letter-spacing: -0.02em;
	}

	.placeholder-desc {
		font-size: 0.875rem;
		color: var(--color-surface-400);
		line-height: 1.6;
		margin-bottom: 1.5rem;
	}

	.status-badge {
		display: flex;
		align-items: center;
		gap: 0.5rem;
		padding: 0.375rem 0.875rem;
		background: var(--color-surface-900);
		border: 1px solid var(--color-surface-700);
		border-radius: 100px;
		font-size: 0.75rem;
		font-weight: 500;
		color: var(--color-surface-400);
		text-transform: uppercase;
		letter-spacing: 0.05em;
	}

	.status-dot {
		width: 6px;
		height: 6px;
		border-radius: 50%;
		background: var(--color-warning-400);
		animation: pulse-glow 2s ease-in-out infinite;
	}

	@keyframes pulse-glow {
		0%, 100% { opacity: 0.4; }
		50% { opacity: 1; }
	}
</style>
