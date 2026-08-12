<!--
  Admin Chat — Message moderation (list + delete).
  REST only, no WebSocket.
-->
<script>
	import { onMount } from 'svelte';
	import { listAdminMessages, deleteAdminMessage } from '$lib/api/chat.js';
	import { t } from '$lib/i18n/store.svelte.js';

	let messages = $state([]);
	let totalCount = $state(0);
	let currentPage = $state(1);
	let isLoading = $state(true);
	let error = $state('');

	// Delete
	let showDeleteModal = $state(false);
	let deletingItem = $state(null);
	let deleteLoading = $state(false);

	const PAGE_SIZE = 20;
	let totalPages = $derived(Math.ceil(totalCount / PAGE_SIZE));

	onMount(() => { fetchMessages(); });

	async function fetchMessages() {
		isLoading = true; error = '';
		try {
			const data = await listAdminMessages({ page: currentPage });
			messages = data.results; totalCount = data.count;
		} catch (err) { error = err.message; }
		finally { isLoading = false; }
	}

	function goToPage(p) { if (p < 1 || p > totalPages) return; currentPage = p; fetchMessages(); }

	function openDeleteModal(msg) { deletingItem = msg; showDeleteModal = true; }
	async function handleDelete() {
		deleteLoading = true;
		try { await deleteAdminMessage(deletingItem.id); showDeleteModal = false; deletingItem = null; fetchMessages(); }
		catch (err) { error = err.message; showDeleteModal = false; }
		finally { deleteLoading = false; }
	}

	function formatDate(d) {
		if (!d) return '—';
		return new Date(d).toLocaleDateString('en-US', { year: 'numeric', month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });
	}

	function isImage(file) {
		const ext = (file.url || file.file || '').toLowerCase();
		return ext.match(/\.(jpg|jpeg|png|gif|webp|svg)/) || (file.type || '').startsWith('image/');
	}

	function fileName(url) {
		if (!url) return 'File';
		return decodeURIComponent(url.split('/').pop().split('?')[0]);
	}
</script>

<svelte:head><title>{t('chat.moderation')} — Nebras</title></svelte:head>

<div class="page">
	<div class="page-header">
		<div><h1 class="page-title">{t('chat.moderation')}</h1><p class="page-desc">{t('chat.moderation_desc')}</p></div>
		<div class="count-badge">{totalCount} {t('chat.messages_count')}</div>
	</div>

	{#if error}<div class="alert alert-error">{error}</div>{/if}

	<div class="content-container">
		{#if isLoading}
			<div class="state-box"><div class="spinner"></div><span>{t('common.loading')}</span></div>
		{:else if messages.length === 0}
			<div class="state-box empty-state"><p>{t('chat.no_messages')}</p></div>
		{:else}
			<div class="msg-list">
				{#each messages as msg (msg.id)}
					<div class="msg-row">
						<div class="msg-avatar">{msg.username?.charAt(0).toUpperCase()}</div>
						<div class="msg-content">
							<div class="msg-meta">
								<span class="msg-user">{msg.username}</span>
								<span class="msg-date">{formatDate(msg.timestamp)}</span>
							</div>
							{#if msg.message}<p class="msg-text">{msg.message}</p>{/if}
							{#if msg.files?.length > 0}
								<div class="msg-files">
									{#each msg.files as file}
										{#if isImage(file)}
											<a href={file.url || file.file} target="_blank" rel="noopener"><img src={file.url || file.file} alt="" class="msg-file-img" loading="lazy" /></a>
										{:else}
											<a href={file.url || file.file} target="_blank" rel="noopener" class="msg-file-link">
												📎 {fileName(file.url || file.file)}
											</a>
										{/if}
									{/each}
								</div>
							{/if}
						</div>
						<button class="action-btn delete" title="Delete message" onclick={() => openDeleteModal(msg)}>
							<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" /></svg>
						</button>
					</div>
				{/each}
			</div>
		{/if}
	</div>

	{#if totalPages > 1}
		<div class="pagination">
			<button class="page-btn" disabled={currentPage === 1} onclick={() => goToPage(currentPage - 1)}>← {t('common.previous')}</button>
			<div class="page-numbers">
				{#each Array.from({ length: totalPages }, (_, i) => i + 1) as p}
					{#if p === 1 || p === totalPages || (p >= currentPage - 1 && p <= currentPage + 1)}
						<button class="page-num" class:active={p === currentPage} onclick={() => goToPage(p)}>{p}</button>
					{:else if p === currentPage - 2 || p === currentPage + 2}
						<span class="page-ellipsis">...</span>
					{/if}
				{/each}
			</div>
			<button class="page-btn" disabled={currentPage === totalPages} onclick={() => goToPage(currentPage + 1)}>{t('common.next')} →</button>
		</div>
	{/if}
</div>

<!-- Delete Modal -->
{#if showDeleteModal && deletingItem}
	<!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
	<!-- svelte-ignore a11y_click_events_have_key_events -->
	<div class="modal-overlay" role="dialog" tabindex="-1" onclick={(e) => { if (e.target === e.currentTarget) showDeleteModal = false; }}>
		<div class="modal modal-sm animate-fade-in">
			<div class="modal-header"><h2 class="modal-title">{t('chat.delete_msg')}</h2><button class="modal-close" aria-label="Close" onclick={() => (showDeleteModal = false)}><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M6 18L18 6M6 6l12 12" stroke-linecap="round" stroke-linejoin="round" /></svg></button></div>
			<div class="delete-body">
				<p class="delete-message">{t('chat.delete_confirm')} <strong>{deletingItem.username}</strong>?</p>
				{#if deletingItem.message}<div class="delete-preview">"{deletingItem.message}"</div>{/if}
			</div>
			<div class="modal-actions pad-actions">
				<button class="btn btn-secondary" onclick={() => (showDeleteModal = false)}>{t('common.cancel')}</button>
				<button class="btn btn-danger" onclick={handleDelete} disabled={deleteLoading}>{#if deleteLoading}<span class="spinner-sm"></span>{/if}{t('common.delete')}</button>
			</div>
		</div>
	</div>
{/if}

<style>
	.page { display: flex; flex-direction: column; gap: 1.25rem; }
	.page-header { display: flex; align-items: flex-start; justify-content: space-between; gap: 1rem; }
	.page-title { font-size: 1.5rem; font-weight: 700; color: var(--color-surface-100); letter-spacing: -0.02em; }
	.page-desc { font-size: 0.8125rem; color: var(--color-surface-400); margin-top: 0.25rem; }
	.count-badge { padding: 0.375rem 0.75rem; background: var(--color-surface-800); border: 1px solid var(--color-surface-700); border-radius: 100px; font-size: 0.75rem; color: var(--color-surface-400); font-weight: 500; }
	.alert { padding: 0.75rem 1rem; border-radius: 10px; font-size: 0.8125rem; }
	.alert-error { background: rgba(244,63,94,0.1); border: 1px solid rgba(244,63,94,0.2); color: var(--color-danger-400); }
	.content-container { min-height: 200px; }
	.state-box { display: flex; flex-direction: column; align-items: center; justify-content: center; padding: 3rem; gap: 0.75rem; color: var(--color-surface-500); font-size: 0.875rem; }
	.empty-state { padding: 4rem 2rem; }
	.spinner { width: 24px; height: 24px; border: 3px solid var(--color-surface-700); border-top-color: var(--color-primary-500); border-radius: 50%; animation: spin 0.6s linear infinite; }

	/* Message list */
	.msg-list { display: flex; flex-direction: column; gap: 0.5rem; }
	.msg-row { display: flex; align-items: flex-start; gap: 0.75rem; padding: 0.875rem 1rem; background: var(--color-surface-800); border: 1px solid var(--color-surface-700); border-radius: 12px; }
	.msg-avatar { width: 36px; height: 36px; border-radius: 50%; background: var(--color-surface-700); display: flex; align-items: center; justify-content: center; font-size: 0.8125rem; font-weight: 700; color: var(--color-surface-300); flex-shrink: 0; }
	.msg-content { flex: 1; min-width: 0; }
	.msg-meta { display: flex; align-items: baseline; gap: 0.5rem; margin-bottom: 0.25rem; }
	.msg-user { font-size: 0.8125rem; font-weight: 600; color: var(--color-primary-400); }
	.msg-date { font-size: 0.6875rem; color: var(--color-surface-500); }
	.msg-text { font-size: 0.8125rem; color: var(--color-surface-200); line-height: 1.5; white-space: pre-wrap; word-break: break-word; margin: 0; }
	.msg-files { display: flex; flex-wrap: wrap; gap: 0.5rem; margin-top: 0.5rem; }
	.msg-file-img { max-width: 120px; max-height: 80px; border-radius: 6px; }
	.msg-file-link { font-size: 0.75rem; color: var(--color-primary-400); text-decoration: none; }
	.msg-file-link:hover { text-decoration: underline; }
	.action-btn { width: 30px; height: 30px; display: flex; align-items: center; justify-content: center; border-radius: 8px; border: 1px solid var(--color-surface-600); background: transparent; color: var(--color-surface-400); cursor: pointer; transition: all 0.15s; flex-shrink: 0; margin-top: 0.25rem; }
	.action-btn svg { width: 14px; height: 14px; }
	.action-btn.delete:hover { background: rgba(244,63,94,0.1); border-color: var(--color-danger-600); color: var(--color-danger-400); }

	/* Pagination */
	.pagination { display: flex; align-items: center; justify-content: center; gap: 0.5rem; }
	.page-btn { padding: 0.5rem 1rem; background: var(--color-surface-800); border: 1px solid var(--color-surface-700); border-radius: 8px; color: var(--color-surface-300); font-size: 0.8125rem; font-family: inherit; cursor: pointer; }
	.page-btn:hover:not(:disabled) { background: var(--color-surface-700); }
	.page-btn:disabled { opacity: 0.4; cursor: not-allowed; }
	.page-numbers { display: flex; align-items: center; gap: 0.25rem; }
	.page-num { width: 34px; height: 34px; display: flex; align-items: center; justify-content: center; border-radius: 8px; border: none; background: transparent; color: var(--color-surface-400); font-size: 0.8125rem; font-family: inherit; cursor: pointer; }
	.page-num:hover { background: var(--color-surface-700); }
	.page-num.active { background: var(--color-primary-700); color: white; font-weight: 600; }
	.page-ellipsis { color: var(--color-surface-500); }

	/* Buttons & Modal */
	.btn { display: inline-flex; align-items: center; gap: 0.5rem; padding: 0.625rem 1.125rem; border-radius: 10px; font-size: 0.8125rem; font-weight: 600; font-family: inherit; cursor: pointer; border: none; transition: all 0.15s; }
	.btn-secondary { background: var(--color-surface-700); color: var(--color-surface-300); border: 1px solid var(--color-surface-600); }
	.btn-secondary:hover { background: var(--color-surface-600); }
	.btn-danger { background: linear-gradient(135deg, var(--color-danger-600), var(--color-danger-500)); color: white; }
	.btn-danger:disabled { opacity: 0.6; cursor: not-allowed; }
	.modal-overlay { position: fixed; inset: 0; background: rgba(0,0,0,0.6); backdrop-filter: blur(4px); display: flex; align-items: center; justify-content: center; z-index: 100; padding: 1rem; }
	.modal { width: 100%; max-width: 520px; background: var(--color-surface-800); border: 1px solid var(--color-surface-700); border-radius: 16px; box-shadow: var(--shadow-elevated); max-height: 90vh; overflow-y: auto; }
	.modal-sm { max-width: 400px; }
	.modal-header { display: flex; align-items: center; justify-content: space-between; padding: 1.25rem 1.5rem; border-bottom: 1px solid var(--color-surface-700); }
	.modal-title { font-size: 1.125rem; font-weight: 700; color: var(--color-surface-100); }
	.modal-close { width: 32px; height: 32px; display: flex; align-items: center; justify-content: center; border-radius: 8px; border: none; background: transparent; color: var(--color-surface-500); cursor: pointer; }
	.modal-close:hover { background: var(--color-surface-700); color: var(--color-surface-300); }
	.modal-close svg { width: 18px; height: 18px; }
	.modal-actions { display: flex; justify-content: flex-end; gap: 0.5rem; padding-top: 0.5rem; }
	.pad-actions { padding: 0 1.5rem 1.25rem; }
	.delete-body { padding: 1.25rem 1.5rem; }
	.delete-message { font-size: 0.875rem; color: var(--color-surface-300); line-height: 1.5; }
	.delete-message strong { color: var(--color-surface-100); }
	.delete-preview { margin-top: 0.75rem; padding: 0.625rem 0.875rem; background: var(--color-surface-900); border: 1px solid var(--color-surface-600); border-radius: 8px; font-size: 0.8125rem; color: var(--color-surface-400); font-style: italic; white-space: pre-wrap; word-break: break-word; max-height: 120px; overflow-y: auto; }
	.spinner-sm { width: 14px; height: 14px; border: 2px solid rgba(255,255,255,0.3); border-top-color: white; border-radius: 50%; animation: spin 0.6s linear infinite; }
	@keyframes spin { to { transform: rotate(360deg); } }
	:global(.animate-fade-in) { animation: fadeIn 0.15s ease-out; }
	@keyframes fadeIn { from { opacity: 0; transform: translateY(8px); } to { opacity: 1; transform: translateY(0); } }

	@media (max-width: 640px) {
		.msg-row { flex-wrap: wrap; }
		.msg-content { min-width: 100%; order: -1; }
		.msg-avatar { display: none; }
		.msg-meta { flex-wrap: wrap; }
		.action-btn.delete { margin-left: auto; justify-content: flex-end; }
	}
</style>
