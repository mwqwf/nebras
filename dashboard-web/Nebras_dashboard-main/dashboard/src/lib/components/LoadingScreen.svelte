<!--
  LoadingScreen.svelte — Full-page loading overlay
  Dark theme with green pulsing orb.
-->

<script>
	let { message = 'Loading...' } = $props();
</script>

<div class="loading-screen" id="loading-screen">
	<div class="loading-orb">
		<div class="orb-ring"></div>
		<div class="orb-core"></div>
	</div>
	<p class="loading-text">{message}</p>
	<div class="loading-dots">
		<span class="dot" style="animation-delay: 0s;"></span>
		<span class="dot" style="animation-delay: 0.2s;"></span>
		<span class="dot" style="animation-delay: 0.4s;"></span>
	</div>
</div>

<style>
	.loading-screen {
		position: fixed;
		inset: 0;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		background: var(--color-surface-950);
		z-index: 9999;
		gap: 1.5rem;
	}

	.loading-orb {
		position: relative;
		width: 64px;
		height: 64px;
	}

	.orb-ring {
		position: absolute;
		inset: 0;
		border: 3px solid transparent;
		border-top-color: var(--color-primary-500);
		border-right-color: var(--color-primary-400);
		border-radius: 50%;
		animation: spinner 1s linear infinite;
	}

	.orb-core {
		position: absolute;
		inset: 12px;
		background: radial-gradient(circle, var(--color-primary-500), var(--color-primary-700));
		border-radius: 50%;
		animation: pulse-glow 2s ease-in-out infinite;
	}

	.loading-text {
		font-size: 0.875rem;
		font-weight: 500;
		color: var(--color-surface-400);
		letter-spacing: 0.05em;
		text-transform: uppercase;
	}

	.loading-dots {
		display: flex;
		gap: 6px;
	}

	.dot {
		width: 6px;
		height: 6px;
		background: var(--color-primary-500);
		border-radius: 50%;
		animation: pulse-glow 1.2s ease-in-out infinite;
	}

	@keyframes spinner {
		to { transform: rotate(360deg); }
	}

	@keyframes pulse-glow {
		0%, 100% { opacity: 0.3; transform: scale(0.8); }
		50% { opacity: 1; transform: scale(1); }
	}
</style>
