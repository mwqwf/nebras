<!--
  Floating multi-upload indicator.
  يظهر دائماً (على مستوى اللوحة) أثناء الرفع المتعدد، ويختفي تلقائياً لو
  كان الطابور فارغاً. يسمح للمستخدم بمتابعة التقدم والوصول السريع إلى
  صفحة الطابور بينما يتصفح بقية اللوحة. يستمر العرض حتى بعد انتهاء
  الرفع لعدة ثوانٍ لإبلاغ المستخدم، ثم يمكن إخفاؤه يدوياً.
-->
<script>
	import { page } from '$app/stores';
	import { getMultiUploadState } from '$lib/stores/multiUpload.svelte.js';
	import { t } from '$lib/i18n/store.svelte.js';

	const multi = getMultiUploadState();

	let manuallyHidden = $state(false);

	let total = $derived(multi.queue.length);
	let completed = $derived(multi.queue.filter((it) => it.status === 'completed').length);
	let active = $derived(multi.queue.find((it) => it.status === 'uploading'));
	let queuedLeft = $derived(multi.queue.filter((it) => it.status === 'queued').length);
	let onMultiPage = $derived($page.url?.pathname === '/moderator/content/multi');
	let shouldShow = $derived(
		!manuallyHidden &&
			!onMultiPage &&
			total > 0 &&
			(multi.isUploading ||
				(multi.allDoneAt > 0 && Date.now() - multi.allDoneAt < 10000))
	);

	// إعادة الإظهار تلقائياً عند بدء دفعة جديدة
	$effect(() => {
		if (multi.isUploading) manuallyHidden = false;
	});
</script>

{#if shouldShow}
	<div class="mu-indicator" role="status" aria-live="polite">
		<div class="mu-head">
			<div class="mu-title">
				<span class="mu-dot" class:is-active={multi.isUploading}></span>
				<span class="mu-title-text">{t('content.floating_title')}</span>
			</div>
			<button
				class="mu-hide"
				type="button"
				title={t('content.floating_hide')}
				aria-label={t('content.floating_hide')}
				onclick={() => (manuallyHidden = true)}
			>
				<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
					<path d="M6 18L18 6M6 6l12 12" stroke-linecap="round" stroke-linejoin="round" />
				</svg>
			</button>
		</div>

		{#if active}
			<div class="mu-line">
				<span class="mu-sub">{t('content.floating_uploading')}</span>
				<span class="mu-file" title={active.form.title}>{active.form.title}</span>
			</div>
			<div class="mu-bar">
				<div class="mu-bar-fill" style="width: {active.progress}%"></div>
			</div>
			<div class="mu-meta">
				<span>{active.progress}%</span>
				<span>•</span>
				<span>{completed}/{total} {t('content.floating_done_suffix')}</span>
				{#if queuedLeft > 0}
					<span>•</span>
					<span>{queuedLeft} {t('content.floating_queued')}</span>
				{/if}
			</div>
		{:else if multi.allDoneAt > 0}
			<div class="mu-line mu-line-success">
				<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.25" class="mu-ok-icon">
					<path d="M5 13l4 4L19 7" stroke-linecap="round" stroke-linejoin="round" />
				</svg>
				<span>{t('content.floating_all_done')}</span>
			</div>
			<div class="mu-meta">
				<span>{completed}/{total} {t('content.floating_done_suffix')}</span>
			</div>
		{/if}

		<a class="mu-cta" href="/moderator/content/multi">
			{t('content.floating_open')}
			<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
				<path d="M9 5l7 7-7 7" stroke-linecap="round" stroke-linejoin="round" />
			</svg>
		</a>
	</div>
{/if}

<style>
	.mu-indicator {
		position: fixed;
		bottom: 1.25rem;
		inset-inline-end: 1.25rem;
		width: 320px;
		max-width: calc(100vw - 2rem);
		padding: 0.875rem 1rem;
		background: var(--color-surface-800);
		border: 1px solid var(--color-surface-700);
		border-radius: 14px;
		box-shadow: 0 10px 30px rgba(0, 0, 0, 0.35), 0 2px 6px rgba(0, 0, 0, 0.2);
		z-index: 200;
		display: flex;
		flex-direction: column;
		gap: 0.5rem;
		animation: muSlideIn 0.25s ease-out;
	}

	@keyframes muSlideIn {
		from {
			opacity: 0;
			transform: translateY(12px);
		}
		to {
			opacity: 1;
			transform: translateY(0);
		}
	}

	.mu-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 0.5rem;
	}

	.mu-title {
		display: inline-flex;
		align-items: center;
		gap: 0.5rem;
	}

	.mu-title-text {
		font-size: 0.8125rem;
		font-weight: 700;
		color: var(--color-surface-100);
	}

	.mu-dot {
		width: 10px;
		height: 10px;
		border-radius: 50%;
		background: var(--color-surface-500);
	}

	.mu-dot.is-active {
		background: var(--color-primary-400);
		box-shadow: 0 0 0 0 rgba(5, 150, 105, 0.6);
		animation: muPulse 1.4s ease-out infinite;
	}

	@keyframes muPulse {
		0% {
			box-shadow: 0 0 0 0 rgba(5, 150, 105, 0.55);
		}
		70% {
			box-shadow: 0 0 0 8px rgba(5, 150, 105, 0);
		}
		100% {
			box-shadow: 0 0 0 0 rgba(5, 150, 105, 0);
		}
	}

	.mu-hide {
		width: 24px;
		height: 24px;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		border-radius: 6px;
		background: transparent;
		border: none;
		color: var(--color-surface-500);
		cursor: pointer;
	}

	.mu-hide:hover {
		background: var(--color-surface-700);
		color: var(--color-surface-200);
	}

	.mu-hide svg {
		width: 14px;
		height: 14px;
	}

	.mu-line {
		display: flex;
		align-items: center;
		gap: 0.4rem;
		font-size: 0.75rem;
		color: var(--color-surface-300);
	}

	.mu-sub {
		color: var(--color-surface-500);
		flex-shrink: 0;
	}

	.mu-file {
		color: var(--color-surface-100);
		font-weight: 600;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
		min-width: 0;
	}

	.mu-line-success {
		color: var(--color-primary-400);
		font-weight: 600;
	}

	.mu-ok-icon {
		width: 16px;
		height: 16px;
		color: var(--color-primary-400);
		flex-shrink: 0;
	}

	.mu-bar {
		width: 100%;
		height: 5px;
		background: var(--color-surface-700);
		border-radius: 100px;
		overflow: hidden;
	}

	.mu-bar-fill {
		height: 100%;
		background: linear-gradient(90deg, var(--color-primary-600), var(--color-primary-400));
		border-radius: 100px;
		transition: width 0.3s ease;
	}

	.mu-meta {
		display: flex;
		align-items: center;
		gap: 0.35rem;
		font-size: 0.6875rem;
		color: var(--color-surface-500);
		flex-wrap: wrap;
	}

	.mu-cta {
		margin-top: 0.125rem;
		display: inline-flex;
		align-items: center;
		gap: 0.35rem;
		align-self: flex-start;
		padding: 0.4rem 0.75rem;
		background: linear-gradient(135deg, var(--color-primary-700), var(--color-primary-600));
		color: white;
		font-size: 0.75rem;
		font-weight: 600;
		text-decoration: none;
		border-radius: 8px;
		transition: box-shadow 0.15s;
	}

	.mu-cta:hover {
		box-shadow: 0 4px 12px rgba(5, 150, 105, 0.25);
	}

	.mu-cta svg {
		width: 12px;
		height: 12px;
	}

	:global([dir='rtl']) .mu-cta svg {
		transform: scaleX(-1);
	}
</style>
