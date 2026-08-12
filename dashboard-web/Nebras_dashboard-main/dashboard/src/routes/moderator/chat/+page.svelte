<script>
	import { onMount, onDestroy, tick } from 'svelte';
	import { getAuthState } from '$lib/stores/auth.svelte.js';
	import { createChatSocket, uploadChatFile } from '$lib/api/chat.js';
	import { t } from '$lib/i18n/store.svelte.js';

	const authState = getAuthState();

	let messages = $state([]);
	let messageText = $state('');
	let isConnected = $state(false);
	let error = $state('');

	// File attachment
	let pendingFiles = $state([]);  // { file: File, uploading: bool, id: number|null, error: string }
	let fileInputEl;

	let chatSocket = null;
	let messagesEndEl;
	let messagesContainerEl;

	onMount(() => {
		chatSocket = createChatSocket({
			onHistory: (msgs) => {
				messages = msgs;
				scrollToBottom();
			},
			onMessage: (msg) => {
				messages = [...messages, msg];
				scrollToBottom();
			},
			onOpen: () => { isConnected = true; error = ''; },
			onClose: () => { isConnected = false; },
			onError: () => { error = 'Connection error. Reconnecting...'; }
		});
	});

	onDestroy(() => {
		chatSocket?.close();
	});

	async function scrollToBottom() {
		await tick();
		messagesEndEl?.scrollIntoView({ behavior: 'smooth' });
	}

	function handleFileSelect(e) {
		const files = Array.from(e.target.files || []);
		for (const f of files) {
			const entry = $state({ file: f, uploading: true, id: null, error: '' });
			pendingFiles = [...pendingFiles, entry];
			uploadFile(entry);
		}
		if (fileInputEl) fileInputEl.value = '';
	}

	async function uploadFile(entry) {
		try {
			const result = await uploadChatFile(entry.file);
			entry.id = result.id;
			entry.uploading = false;
			pendingFiles = [...pendingFiles]; // trigger reactivity
		} catch (err) {
			entry.error = err.message;
			entry.uploading = false;
			pendingFiles = [...pendingFiles];
		}
	}

	function removePendingFile(idx) {
		pendingFiles = pendingFiles.filter((_, i) => i !== idx);
	}

	async function sendMessage() {
		const text = messageText.trim();
		const fileIds = pendingFiles.filter(f => f.id).map(f => f.id);

		if (!text && fileIds.length === 0) return;

		const payload = {};
		if (text) payload.message = text;
		if (fileIds.length > 0) payload.file_ids = fileIds;

		chatSocket?.send(payload);
		messageText = '';
		pendingFiles = [];
	}

	function handleKeydown(e) {
		if (e.key === 'Enter' && !e.shiftKey) {
			e.preventDefault();
			sendMessage();
		}
	}

	function isImage(file) {
		const ext = (file.url || file.file || '').toLowerCase();
		return ext.match(/\.(jpg|jpeg|png|gif|webp|svg)/) || (file.type || '').startsWith('image/');
	}

	function fileName(url) {
		if (!url) return 'File';
		return decodeURIComponent(url.split('/').pop().split('?')[0]);
	}

	function formatTime(ts) {
		if (!ts) return '';
		const d = new Date(ts);
		return d.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' });
	}

	function formatDate(ts) {
		if (!ts) return '';
		return new Date(ts).toLocaleDateString('en-US', { weekday: 'long', month: 'short', day: 'numeric' });
	}

	function shouldShowDate(idx) {
		if (idx === 0) return true;
		const curr = new Date(messages[idx].timestamp).toDateString();
		const prev = new Date(messages[idx - 1].timestamp).toDateString();
		return curr !== prev;
	}

	let currentUser = $derived(authState.user?.username || '');

	let allFilesReady = $derived(pendingFiles.length === 0 || pendingFiles.every(f => f.id || f.error));
</script>

<svelte:head><title>{t('chat.title')} — Nebras</title></svelte:head>

<div class="chat-page">
	<div class="chat-header">
		<div class="chat-header-left">
			<h1 class="chat-title">{t('chat.title')}</h1>
			<span class="chat-status" class:online={isConnected}>
				<span class="status-dot"></span>
				{isConnected ? t('chat.connected') : t('chat.connecting')}
			</span>
		</div>
		<span class="chat-members">{new Set(messages.map(m => m.username)).size} {t('chat.participants')}</span>
	</div>

	{#if error}<div class="chat-error">{error}</div>{/if}

	<div class="messages-container" bind:this={messagesContainerEl}>
		{#if messages.length === 0}
			<div class="empty-chat">
				<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" class="empty-icon"><path d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z" stroke-linecap="round" stroke-linejoin="round" /></svg>
				<p>{t('chat.no_messages_yet')}</p>
			</div>
		{:else}
			{#each messages as msg, idx (msg.id || msg.message_id || idx)}
				{#if shouldShowDate(idx)}
					<div class="date-divider"><span>{formatDate(msg.timestamp)}</span></div>
				{/if}
				{@const isMe = msg.username === currentUser}
				<div class="msg" class:msg-me={isMe} class:msg-other={!isMe}>
					{#if !isMe}
						<div class="msg-avatar">{msg.username?.charAt(0).toUpperCase()}</div>
					{/if}
					<div class="msg-bubble">
						{#if !isMe}<span class="msg-sender">{msg.username}</span>{/if}
						{#if msg.message}<p class="msg-text">{msg.message}</p>{/if}
						{#if msg.files?.length > 0}
							<div class="msg-files">
								{#each msg.files as file}
									{#if isImage(file)}
										<a href={file.url || file.file} target="_blank" rel="noopener" class="msg-image-link">
											<img src={file.url || file.file} alt="Attachment" class="msg-image" loading="lazy" />
										</a>
									{:else}
										<a href={file.url || file.file} target="_blank" rel="noopener" class="msg-file-chip">
											<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="file-chip-icon"><path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z" stroke-linecap="round" stroke-linejoin="round" /><path d="M14 2v6h6M16 13H8M16 17H8M10 9H8" stroke-linecap="round" stroke-linejoin="round" /></svg>
											<span>{fileName(file.url || file.file)}</span>
										</a>
									{/if}
								{/each}
							</div>
						{/if}
						<span class="msg-time">{formatTime(msg.timestamp)}</span>
					</div>
				</div>
			{/each}
		{/if}
		<div bind:this={messagesEndEl}></div>
	</div>

	<!-- Pending files preview -->
	{#if pendingFiles.length > 0}
		<div class="pending-bar">
			{#each pendingFiles as pf, i}
				<div class="pending-chip" class:pending-error={pf.error}>
					{#if pf.uploading}<span class="spinner-xs"></span>{/if}
					<span class="pending-name">{pf.file.name}</span>
					{#if pf.error}<span class="pending-err">Failed</span>{/if}
					{#if pf.id}<span class="pending-ok">✓</span>{/if}
					<button class="pending-remove" onclick={() => removePendingFile(i)}>×</button>
				</div>
			{/each}
		</div>
	{/if}

	<!-- Input area -->
	<div class="input-area">
		<button class="attach-btn" onclick={() => fileInputEl?.click()} title="Attach file">
			<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21.44 11.05l-9.19 9.19a6 6 0 01-8.49-8.49l9.19-9.19a4 4 0 015.66 5.66l-9.2 9.19a2 2 0 01-2.83-2.83l8.49-8.48" /></svg>
		</button>
		<input type="file" class="file-input-hidden" multiple bind:this={fileInputEl} onchange={handleFileSelect} />
		<textarea
			class="msg-input"
			placeholder={t('chat.type_message')}
			bind:value={messageText}
			onkeydown={handleKeydown}
			rows="1"
		></textarea>
		<button class="send-btn" aria-label="Send" onclick={sendMessage} disabled={(!messageText.trim() && pendingFiles.filter(f => f.id).length === 0) || !isConnected}>
			<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="22" y1="2" x2="11" y2="13" /><polygon points="22 2 15 22 11 13 2 9 22 2" /></svg>
		</button>
	</div>
</div>

<style>
	:global(body) { overscroll-behavior-y: none; }
	.chat-page { display: flex; flex-direction: column; height: calc(100svh - 130px); overflow: hidden; }
	.chat-header { display: flex; align-items: center; justify-content: space-between; padding: 1rem 1.5rem; border-bottom: 1px solid var(--color-surface-700); flex-shrink: 0; }
	.chat-header-left { display: flex; align-items: center; gap: 1rem; }
	.chat-title { font-size: 1.25rem; font-weight: 700; color: var(--color-surface-100); }
	.chat-status { display: flex; align-items: center; gap: 0.375rem; font-size: 0.6875rem; color: var(--color-surface-500); }
	.chat-status.online { color: var(--color-primary-400); }
	.status-dot { width: 6px; height: 6px; border-radius: 50%; background: var(--color-surface-500); }
	.chat-status.online .status-dot { background: var(--color-primary-400); box-shadow: 0 0 6px rgba(5,150,105,0.5); }
	.chat-members { font-size: 0.75rem; color: var(--color-surface-500); }
	.chat-error { padding: 0.5rem 1.5rem; background: rgba(244,63,94,0.1); color: var(--color-danger-400); font-size: 0.8125rem; flex-shrink: 0; }

	/* Messages */
	.messages-container { flex: 1; overflow-y: auto; padding: 1.5rem; display: flex; flex-direction: column; gap: 0.5rem; }
	.empty-chat { display: flex; flex-direction: column; align-items: center; justify-content: center; flex: 1; gap: 0.75rem; color: var(--color-surface-500); font-size: 0.875rem; }
	.empty-icon { width: 48px; height: 48px; }

	.date-divider { display: flex; align-items: center; justify-content: center; margin: 1rem 0 0.5rem; }
	.date-divider span { background: var(--color-surface-800); padding: 0.25rem 0.75rem; border-radius: 100px; font-size: 0.6875rem; color: var(--color-surface-400); font-weight: 500; border: 1px solid var(--color-surface-700); }

	.msg { display: flex; gap: 0.5rem; max-width: 70%; }
	.msg-me { align-self: flex-end; flex-direction: row-reverse; }
	.msg-other { align-self: flex-start; }

	.msg-avatar { width: 32px; height: 32px; border-radius: 50%; background: var(--color-surface-700); display: flex; align-items: center; justify-content: center; font-size: 0.75rem; font-weight: 700; color: var(--color-surface-300); flex-shrink: 0; margin-top: 0.25rem; }

	.msg-bubble { padding: 0.625rem 0.875rem; border-radius: 14px; max-width: 100%; min-width: 60px; }
	.msg-me .msg-bubble { background: var(--color-primary-700); border-bottom-right-radius: 4px; }
	.msg-other .msg-bubble { background: var(--color-surface-800); border: 1px solid var(--color-surface-700); border-bottom-left-radius: 4px; }

	.msg-sender { font-size: 0.6875rem; font-weight: 600; color: var(--color-primary-400); display: block; margin-bottom: 0.2rem; }
	.msg-text { font-size: 0.8125rem; color: var(--color-surface-100); line-height: 1.5; white-space: pre-wrap; word-break: break-word; margin: 0; }
	.msg-time { font-size: 0.5625rem; color: var(--color-surface-500); display: block; margin-top: 0.25rem; text-align: right; }
	.msg-me .msg-time { color: rgba(255,255,255,0.5); }

	/* Files in messages */
	.msg-files { display: flex; flex-direction: column; gap: 0.375rem; margin-top: 0.375rem; }
	.msg-image-link { display: block; border-radius: 8px; overflow: hidden; }
	.msg-image { max-width: 240px; max-height: 180px; border-radius: 8px; display: block; }
	.msg-file-chip { display: flex; align-items: center; gap: 0.375rem; padding: 0.375rem 0.625rem; background: rgba(255,255,255,0.08); border-radius: 8px; text-decoration: none; color: var(--color-primary-400); font-size: 0.75rem; transition: background 0.15s; }
	.msg-file-chip:hover { background: rgba(255,255,255,0.12); }
	.file-chip-icon { width: 14px; height: 14px; flex-shrink: 0; }

	/* Pending files bar */
	.pending-bar { display: flex; flex-wrap: wrap; gap: 0.375rem; padding: 0.625rem 1.5rem; border-top: 1px solid var(--color-surface-700); background: var(--color-surface-800); flex-shrink: 0; }
	.pending-chip { display: flex; align-items: center; gap: 0.375rem; padding: 0.3rem 0.625rem; background: var(--color-surface-900); border: 1px solid var(--color-surface-600); border-radius: 8px; font-size: 0.6875rem; color: var(--color-surface-300); }
	.pending-error { border-color: var(--color-danger-600); }
	.pending-name { max-width: 120px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
	.pending-err { color: var(--color-danger-400); font-weight: 600; }
	.pending-ok { color: var(--color-primary-400); font-weight: 600; }
	.pending-remove { background: none; border: none; color: var(--color-surface-500); cursor: pointer; font-size: 1rem; padding: 0 0.125rem; }
	.pending-remove:hover { color: var(--color-danger-400); }
	.spinner-xs { width: 10px; height: 10px; border: 2px solid var(--color-surface-600); border-top-color: var(--color-primary-400); border-radius: 50%; animation: spin 0.6s linear infinite; }

	/* Input area */
	.input-area { display: flex; align-items: flex-end; gap: 0.5rem; padding: 0.75rem 1.5rem; border-top: 1px solid var(--color-surface-700); background: var(--color-surface-800); flex-shrink: 0; }
	.attach-btn { width: 38px; height: 38px; display: flex; align-items: center; justify-content: center; border-radius: 10px; border: 1px solid var(--color-surface-600); background: transparent; color: var(--color-surface-400); cursor: pointer; flex-shrink: 0; transition: all 0.15s; }
	.attach-btn:hover { background: var(--color-surface-700); color: var(--color-surface-200); }
	.attach-btn svg { width: 18px; height: 18px; }
	.msg-input { flex: 1; padding: 0.5rem 0.75rem; background: var(--color-surface-900); border: 1px solid var(--color-surface-600); border-radius: 10px; color: var(--color-surface-100); font-size: 0.8125rem; font-family: inherit; outline: none; resize: none; min-height: 38px; max-height: 120px; transition: border-color 0.15s; }
	.msg-input:focus { border-color: var(--color-primary-600); }
	.msg-input::placeholder { color: var(--color-surface-500); }
	.send-btn { width: 38px; height: 38px; display: flex; align-items: center; justify-content: center; border-radius: 10px; border: none; background: linear-gradient(135deg, var(--color-primary-700), var(--color-primary-500)); color: white; cursor: pointer; flex-shrink: 0; transition: all 0.15s; }
	.send-btn:hover:not(:disabled) { box-shadow: 0 4px 12px rgba(5,150,105,0.3); }
	.send-btn:disabled { opacity: 0.4; cursor: not-allowed; }
	.send-btn svg { width: 18px; height: 18px; }
	.file-input-hidden { position: absolute; width: 0; height: 0; opacity: 0; pointer-events: none; }
	@keyframes spin { to { transform: rotate(360deg); } }

	@media (max-width: 640px) {
		.chat-page { height: calc(100svh - 100px - env(safe-area-inset-bottom, 0px)); }
		.msg { max-width: 90%; }
		.chat-header { flex-direction: column; align-items: flex-start; gap: 0.5rem; }
		.msg-image { max-width: 100%; height: auto; }
	}
</style>
