<!--
  Multi Upload Page
  =================
  نموذج رفع متعدد مستقلّ تماماً عن نموذج الرفع الفردي (./files/+page.svelte).
  تعتمد الصفحة على متجر `$lib/stores/multiUpload.svelte.js` الذي يحفظ حالة
  الطابور على مستوى التطبيق، مما يجعل الرفع يستمر في الخلفية أثناء التنقل
  بين صفحات لوحة التحكم. كما تسمح الصفحة بحذف أي بند في أي وقت — حتى لو
  كان قيد الرفع فعلياً — دون التأثير على بقية البنود.
-->

<script>
	import { onMount } from 'svelte';
	import {
		formatFileSize,
		mimeToContentType,
		validateMultiUploadFile
	} from '$lib/utils/fileUpload.js';
	import { generatePdfThumbnail } from '$lib/utils/pdfThumbnail.js';
	import {
		getCachedMainSections,
		getCachedSubSections,
		getCachedSecondarySections
	} from '$lib/utils/sectionOptionsCache.js';
	import {
		getMultiUploadState,
		addItem,
		replaceItemFields,
		removeItem,
		moveItem,
		reorderItem,
		getItemProgress,
		clearCompleted,
		resetQueue,
		startAll,
		stopAll,
		pauseAll,
		resumeAll,
		setLastSections,
		setConcurrency,
		requestUploadNotificationPermission,
		restoreQueueFromStorage,
		DEFAULT_CONCURRENCY
	} from '$lib/stores/multiUpload.svelte.js';
	import { t } from '$lib/i18n/store.svelte.js';

	const multi = getMultiUploadState();

	let isDragging = $state(false);
	let fileSizeWarning = $state('');
	let dragReorderFrom = $state(null);

	let mainSectionsList = $state([]);

	let showItemModal = $state(false);
	let editingItemId = $state(null);
	let itemForm = $state(freshItemForm());
	/** @type {File[]} */
	let itemFiles = $state([]);
	let itemThumbnail = $state(null);
	let itemThumbnailPreview = $state('');
	let itemFormError = $state('');
	let itemSubOptions = $state([]);
	let itemSecondaryOptions = $state([]);
	let sectionsPrefilled = $state(false);

	let completedCount = $derived(
		multi.queue.filter((it) => it.status === 'completed').length
	);
	let totalCount = $derived(multi.queue.length);
	let hasQueue = $derived(multi.queue.length > 0);
	let canStart = $derived(
		!multi.isUploading &&
			multi.queue.some((it) => it.status === 'queued' || it.status === 'failed')
	);
	let hasActiveUpload = $derived(multi.isUploading);
	let allDone = $derived(
		multi.allDoneAt > 0 &&
			multi.queue.length > 0 &&
			multi.queue.every((it) => it.status === 'completed')
	);
	let isMultiFileMode = $derived(!editingItemId && itemFiles.length > 1);

	$effect(() => {
		if (itemForm.main_section) {
			fetchSubOpts(itemForm.main_section);
		}
	});
	$effect(() => {
		if (itemForm.subsection) {
			fetchSecOpts(itemForm.subsection);
		}
	});

	onMount(() => {
		fetchMainOptions();
		restoreQueueFromStorage();
		requestUploadNotificationPermission();
	});

	function freshItemForm() {
		return {
			title: '',
			description: '',
			author: '',
			main_section: '',
			subsection: '',
			secondary_subsection: '',
			is_listed: true
		};
	}

	async function fetchMainOptions() {
		mainSectionsList = await getCachedMainSections();
	}

	async function fetchSubOpts(mainId) {
		itemSubOptions = await getCachedSubSections(mainId);
	}

	async function fetchSecOpts(subId) {
		itemSecondaryOptions = await getCachedSecondarySections(subId);
	}

	function openAddModal() {
		editingItemId = null;
		itemForm = freshItemForm();
		itemFiles = [];
		itemThumbnail = null;
		itemThumbnailPreview = '';
		itemFormError = '';
		itemSubOptions = [];
		itemSecondaryOptions = [];
		sectionsPrefilled = false;
		showItemModal = true;
		if (mainSectionsList.length === 0) fetchMainOptions();

		// تذكّر آخر اختيار أقسام داخل نفس دفعة "الرفع المتعدد": لو وُجد
		// اختيار محفوظ من الملف السابق، نملأ الحقول تلقائياً لنُريح المستخدم
		// من إعادة اختيارها يدوياً. يبقى بإمكانه تغييرها كما يشاء.
		const last = multi.lastSections;
		if (last && last.main_section) {
			itemForm.main_section = last.main_section;
			itemForm.subsection = last.subsection || '';
			itemForm.secondary_subsection = last.secondary_subsection || '';
			sectionsPrefilled = true;
			fetchSubOpts(last.main_section).then(() => {
				if (last.subsection) fetchSecOpts(last.subsection);
			});
		}
	}

	function openEditModal(item) {
		if (item.status === 'uploading' || item.status === 'completed') return;
		editingItemId = item.id;
		itemForm = {
			title: item.form.title,
			description: item.form.description,
			author: item.form.author,
			main_section: item.form.main_section,
			subsection: item.form.subsection,
			secondary_subsection: item.form.secondary_subsection,
			is_listed: item.form.is_listed
		};
		itemFiles = item.file ? [item.file] : [];
		itemThumbnail = item.thumbnail;
		itemThumbnailPreview = item.thumbnailPreview || '';
		itemFormError = '';
		itemSubOptions = [];
		itemSecondaryOptions = [];
		showItemModal = true;
		if (itemForm.main_section) fetchSubOpts(itemForm.main_section);
		if (itemForm.subsection) fetchSecOpts(itemForm.subsection);
	}

	function applyFilesList(list) {
		fileSizeWarning = '';
		itemFormError = '';
		const accepted = [];
		for (const f of list) {
			const check = validateMultiUploadFile(f);
			if (!check.ok) {
				itemFormError = `${f.name}: ${check.error || t('content.file_too_large')}`;
				return;
			}
			if (check.warn && !fileSizeWarning) fileSizeWarning = check.warn;
			accepted.push(f);
		}
		if (!accepted.length) return;
		if (editingItemId) {
			itemFiles = [accepted[0]];
			if (!itemForm.title) itemForm.title = accepted[0].name.replace(/\.[^/.]+$/, '');
		} else {
			itemFiles = [...itemFiles, ...accepted];
			if (itemFiles.length === 1 && !itemForm.title) {
				itemForm.title = itemFiles[0].name.replace(/\.[^/.]+$/, '');
			}
		}
	}

	function handleFilesSelect(e) {
		const list = Array.from(e.target.files || []);
		if (!list.length) return;
		applyFilesList(list);
		try {
			e.target.value = '';
		} catch {
			/* ignore */
		}
	}

	function handleDragOver(e) {
		e.preventDefault();
		isDragging = true;
	}

	function handleDragLeave() {
		isDragging = false;
	}

	function handleDrop(e) {
		e.preventDefault();
		isDragging = false;
		const list = Array.from(e.dataTransfer?.files || []);
		if (list.length) applyFilesList(list);
	}

	function handleThumbSelect(e) {
		const f = e.target.files?.[0];
		if (!f) return;
		itemThumbnail = f;
		const reader = new FileReader();
		reader.onload = (ev) => {
			itemThumbnailPreview = ev.target.result;
		};
		reader.readAsDataURL(f);
	}

	function removeFileAt(idx) {
		itemFiles = itemFiles.filter((_, i) => i !== idx);
	}

	function clearAllFiles() {
		itemFiles = [];
	}

	function clearThumb() {
		itemThumbnail = null;
		itemThumbnailPreview = '';
	}

	async function handleMainChange() {
		itemForm.subsection = '';
		itemForm.secondary_subsection = '';
		itemSecondaryOptions = [];
		sectionsPrefilled = false;
		if (itemForm.main_section) await fetchSubOpts(itemForm.main_section);
		else itemSubOptions = [];
	}

	async function handleSubChange() {
		itemForm.secondary_subsection = '';
		sectionsPrefilled = false;
		if (itemForm.subsection) await fetchSecOpts(itemForm.subsection);
		else itemSecondaryOptions = [];
	}

	function handleSecondaryChange() {
		sectionsPrefilled = false;
	}

	async function saveItemToQueue() {
		itemFormError = '';
		if (itemFiles.length === 0) {
			itemFormError = t('content.click_select');
			return;
		}
		// في الوضع متعدد الملفات نسمح بترك العنوان فارغاً (سيُؤخذ من اسم الملف).
		if (!isMultiFileMode && !itemForm.title?.trim()) {
			itemFormError = t('common.title');
			return;
		}
		if (!itemForm.main_section) {
			itemFormError = t('sections.main_section');
			return;
		}
		if (!itemForm.subsection) {
			itemFormError = t('sections.sub_section');
			return;
		}

		const mainName =
			mainSectionsList.find((m) => String(m.id) === String(itemForm.main_section))?.name || '';
		const subName =
			itemSubOptions.find((s) => String(s.id) === String(itemForm.subsection))?.name || '';
		const secName = itemForm.secondary_subsection
			? itemSecondaryOptions.find(
					(s) => String(s.id) === String(itemForm.secondary_subsection)
				)?.name || ''
			: '';
		const labels = { main: mainName, sub: subName, secondary: secName };

		if (editingItemId) {
			// التعديل دائماً على ملف واحد. لا تغيير في ترتيب الطابور.
			replaceItemFields(editingItemId, {
				file: itemFiles[0],
				thumbnail: itemThumbnail,
				thumbnailPreview: itemThumbnailPreview,
				form: { ...itemForm },
				labels
			});
		} else {
			// نُضيف بترتيب الاختيار: index 0 أوّلاً، ١، ٢، …، وهو ما يضمن
			// أنّ أوّل ملف اختاره المستخدم هو أوّل من يُبدأ رفعه عند الانطلاق.
			for (let i = 0; i < itemFiles.length; i++) {
				const f = itemFiles[i];
				const titleForFile =
					isMultiFileMode
						? f.name.replace(/\.[^/.]+$/, '')
						: (itemForm.title?.trim() || f.name.replace(/\.[^/.]+$/, ''));
				let thumb = itemThumbnail;
				let thumbPreview = itemThumbnailPreview;
				if (!thumb && f.type === 'application/pdf') {
					const generated = await generatePdfThumbnail(f);
					if (generated) {
						thumb = generated.file;
						thumbPreview = generated.preview;
					}
				}
				const addedId = addItem({
					file: f,
					thumbnail: thumb,
					thumbnailPreview: thumbPreview,
					form: { ...itemForm, title: titleForFile },
					labels
				});
				if (!addedId) {
					itemFormError = multi.lastError || t('content.file_too_large');
					return;
				}
			}
			// لا نحفظ آخر أقسام إلا عند إضافة بند جديد — التعديل لا يغيّر السياق.
			setLastSections({
				main_section: itemForm.main_section,
				subsection: itemForm.subsection,
				secondary_subsection: itemForm.secondary_subsection
			});
		}

		showItemModal = false;
	}

	function handleMoveItem(id, direction) {
		moveItem(id, direction);
	}

	function handleQueueDragStart(idx) {
		if (multi.isUploading) return;
		dragReorderFrom = idx;
	}

	function handleQueueDragOver(e, idx) {
		if (dragReorderFrom === null || multi.isUploading) return;
		e.preventDefault();
	}

	function handleQueueDrop(e, toIdx) {
		e.preventDefault();
		if (dragReorderFrom === null || multi.isUploading) return;
		reorderItem(dragReorderFrom, toIdx);
		dragReorderFrom = null;
	}

	function handleQueueDragEnd() {
		dragReorderFrom = null;
	}

	function handleRemoveItem(item) {
		if (item.status === 'uploading') {
			const ok = confirm(t('content.confirm_remove_active'));
			if (!ok) return;
		}
		removeItem(item.id);
	}

	function handleClearCompleted() {
		clearCompleted();
	}

	function handleReset() {
		if (multi.isUploading) {
			const ok = confirm(t('content.confirm_remove_active'));
			if (!ok) return;
		}
		resetQueue();
	}

	function handleStart() {
		startAll();
	}

	function handleStop() {
		stopAll();
	}

	function handlePause() {
		pauseAll();
	}

	function handleResume() {
		resumeAll();
	}

	function handleConcurrencyChange(e) {
		setConcurrency(Number(e.target.value));
	}

	function statusLabel(status) {
		if (status === 'uploading') return t('content.item_active');
		if (status === 'committing') return t('content.item_committing');
		if (status === 'completed') return t('content.item_done');
		if (status === 'failed') return t('content.item_error');
		return t('content.item_queued');
	}

	function iconFor(mime) {
		const ct = mimeToContentType(mime);
		if (ct === 'video') return '🎬';
		if (ct === 'audio') return '🎵';
		return '📄';
	}
</script>

<svelte:head><title>{t('content.multi_upload_title')} — Nebras</title></svelte:head>

<div class="page">
	<div class="page-header">
		<div>
			<h1 class="page-title">{t('content.multi_upload_title')}</h1>
			<p class="page-desc">{t('content.multi_upload_desc')}</p>
		</div>
		<div class="header-actions">
			<label class="concurrency-picker" title={t('content.concurrency_label')}>
				<span class="concurrency-label">{t('content.parallel_hint')}</span>
				<select
					class="concurrency-select"
					value={multi.concurrency || DEFAULT_CONCURRENCY}
					onchange={handleConcurrencyChange}
					disabled={multi.isUploading}
				>
					<option value={1}>1</option>
					<option value={2}>2</option>
					<option value={3}>3</option>
					<option value={4}>4</option>
					<option value={5}>5</option>
				</select>
			</label>
			<button class="btn btn-secondary" disabled={!hasQueue} onclick={handleReset}>
				{t('content.reset_queue')}
			</button>
			<button class="btn btn-primary" onclick={openAddModal}>
				<svg
					viewBox="0 0 24 24"
					fill="none"
					stroke="currentColor"
					stroke-width="2"
					stroke-linecap="round"
					stroke-linejoin="round"
					class="btn-icon"><path d="M12 5v14m-7-7h14" /></svg
				>
				{t('content.add_to_queue_multi')}
			</button>
		</div>
	</div>

	<div class="tabs">
		<a href="/moderator/content/files" class="tab">{t('content.file_uploads')}</a>
		<a href="/moderator/content/multi" class="tab active">{t('content.multi_upload')}</a>
	</div>

	<div class="summary-strip">
		<div class="summary-left">
			<span class="summary-count">{totalCount}</span>
			<span class="summary-label">{t('content.files_in_queue')}</span>
		</div>
		<div class="summary-progress">
			<div class="summary-bar-track">
				<div
					class="summary-bar-fill"
					style="width: {totalCount > 0 ? (completedCount / totalCount) * 100 : 0}%"
				></div>
			</div>
			<span class="summary-numbers"
				>{completedCount} {t('content.summary_of')} {totalCount} {t('content.summary_done')}</span
			>
		</div>
		<div class="summary-actions">
			{#if hasActiveUpload}
				{#if multi.isPaused}
					<button class="btn btn-secondary" onclick={handleResume}>{t('content.resume_all')}</button>
				{:else}
					<button class="btn btn-secondary" onclick={handlePause}>{t('content.pause_all')}</button>
				{/if}
				<button class="btn btn-secondary" onclick={handleStop}>{t('content.stop_all')}</button>
			{:else}
				<button
					class="btn btn-secondary"
					disabled={!completedCount}
					onclick={handleClearCompleted}
				>
					{t('content.clear_completed')}
				</button>
				<button class="btn btn-primary" disabled={!canStart} onclick={handleStart}>
					<svg
						viewBox="0 0 24 24"
						fill="none"
						stroke="currentColor"
						stroke-width="2"
						stroke-linecap="round"
						stroke-linejoin="round"
						class="btn-icon"><path d="M5 3l14 9-14 9V3z" /></svg
					>
					{t('content.start_all')}
				</button>
			{/if}
		</div>
	</div>

	{#if multi.lastError}<div class="alert alert-error">{multi.lastError}</div>{/if}
	{#if allDone}<div class="alert alert-success">{t('content.uploads_finished')}</div>{/if}

	<div class="hints">
		<p class="hint-note">{t('content.upload_order_note')}</p>
		<p class="hint-note hint-info">• {t('content.upload_commit_order_note')}</p>
		<p class="hint-note hint-info">• {t('content.remove_during_upload_hint')}</p>
		<p class="hint-note hint-info">• {t('content.background_hint')}</p>
		<p class="hint-note hint-info">• {t('content.drag_reorder_hint')}</p>
	</div>

	<div class="queue-container">
		{#if !hasQueue}
			<div class="empty-state">
				<svg
					viewBox="0 0 24 24"
					fill="none"
					stroke="currentColor"
					stroke-width="1.5"
					class="empty-icon"
					><path
						d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12"
						stroke-linecap="round"
						stroke-linejoin="round"
					/></svg
				>
				<p>{t('content.queue_empty')}</p>
				<button class="btn btn-primary btn-sm" onclick={openAddModal}
					>{t('content.add_to_queue_multi')}</button
				>
			</div>
		{:else}
			<ul class="queue-list">
				{#each multi.queue as item, idx (item.id)}
					{@const pct = getItemProgress(item.id)}
					<li
						class="queue-item"
						class:is-active={item.status === 'uploading' || item.status === 'committing'}
						class:is-completed={item.status === 'completed'}
						class:is-failed={item.status === 'failed'}
						class:is-dragging={dragReorderFrom === idx}
						draggable={!multi.isUploading &&
							item.status !== 'uploading' &&
							item.status !== 'committing'}
						ondragstart={() => handleQueueDragStart(idx)}
						ondragover={(e) => handleQueueDragOver(e, idx)}
						ondrop={(e) => handleQueueDrop(e, idx)}
						ondragend={handleQueueDragEnd}
					>
						<div class="queue-order">{idx + 1}</div>

						{#if item.thumbnailPreview}
							<img class="queue-thumb" src={item.thumbnailPreview} alt="" />
						{:else}
							<div class="queue-thumb queue-thumb-fallback">{iconFor(item.file.type)}</div>
						{/if}

						<div class="queue-main">
							<div class="queue-title-row">
								<span class="queue-title">{item.form.title}</span>
								<span class="queue-chip queue-chip-{item.status}"
									>{statusLabel(item.status)}</span
								>
							</div>
							<div class="queue-meta-row">
								<span class="queue-filename">{item.file.name}</span>
								<span class="queue-dot">•</span>
								<span class="queue-size">{formatFileSize(item.file.size)}</span>
								<span class="queue-dot">•</span>
								<span class="queue-section-chain">
									{item.labels.main}
									{#if item.labels.sub} › {item.labels.sub}{/if}
									{#if item.labels.secondary} › {item.labels.secondary}{/if}
								</span>
							</div>

							{#if item.status === 'uploading' || item.status === 'committing' || (item.status === 'completed' && pct > 0)}
								<div class="queue-progress">
									<div class="queue-progress-track">
										<div class="queue-progress-fill" style="width: {pct}%"></div>
									</div>
									<span class="queue-progress-pct">{pct}%</span>
								</div>
							{/if}

							{#if item.error}
								<div class="queue-error">{item.error}</div>
							{/if}
						</div>

						<div class="queue-actions">
							<button
								class="icon-btn"
								title={t('content.move_up')}
								disabled={item.status === 'uploading' || item.status === 'committing' || idx === 0}
								onclick={() => handleMoveItem(item.id, -1)}
							>
								<svg
									viewBox="0 0 24 24"
									fill="none"
									stroke="currentColor"
									stroke-width="2"
									stroke-linecap="round"
									stroke-linejoin="round"><path d="M18 15l-6-6-6 6" /></svg
								>
							</button>
							<button
								class="icon-btn"
								title={t('content.move_down')}
								disabled={item.status === 'uploading' || item.status === 'committing' || idx === multi.queue.length - 1}
								onclick={() => handleMoveItem(item.id, 1)}
							>
								<svg
									viewBox="0 0 24 24"
									fill="none"
									stroke="currentColor"
									stroke-width="2"
									stroke-linecap="round"
									stroke-linejoin="round"><path d="M6 9l6 6 6-6" /></svg
								>
							</button>
							<button
								class="icon-btn edit"
								title={t('content.edit_item')}
								disabled={item.status === 'uploading' || item.status === 'completed'}
								onclick={() => openEditModal(item)}
							>
								<svg
									viewBox="0 0 24 24"
									fill="none"
									stroke="currentColor"
									stroke-width="2"
									stroke-linecap="round"
									stroke-linejoin="round"
									><path
										d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z"
									/></svg
								>
							</button>
							<button
								class="icon-btn delete"
								title={t('content.remove_from_queue')}
								onclick={() => handleRemoveItem(item)}
							>
								<svg
									viewBox="0 0 24 24"
									fill="none"
									stroke="currentColor"
									stroke-width="2"
									stroke-linecap="round"
									stroke-linejoin="round"
									><path
										d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
									/></svg
								>
							</button>
						</div>
					</li>
				{/each}
			</ul>
		{/if}
	</div>
</div>

<!-- ═══════════════ Configure Item Modal ═══════════════ -->
{#if showItemModal}
	<!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
	<div
		class="modal-overlay"
		role="dialog"
		tabindex="-1"
		onkeydown={(e) => e.key === 'Escape' && (showItemModal = false)}
		onclick={(e) => {
			if (e.target === e.currentTarget) showItemModal = false;
		}}
	>
		<div class="modal animate-fade-in">
			<div class="modal-header">
				<h2 class="modal-title">
					{editingItemId ? t('content.update_item') : t('content.configure_item')}
				</h2>
				<button class="modal-close" aria-label="Close" onclick={() => (showItemModal = false)}>
					<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
						><path d="M6 18L18 6M6 6l12 12" stroke-linecap="round" stroke-linejoin="round" /></svg
					>
				</button>
			</div>

			{#if itemFormError}<div class="alert alert-error modal-alert">{itemFormError}</div>{/if}
			{#if !editingItemId && sectionsPrefilled}
				<div class="alert alert-info modal-alert">
					<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="alert-icon" aria-hidden="true">
						<circle cx="12" cy="12" r="10" />
						<path d="M12 16v-4M12 8h.01" stroke-linecap="round" stroke-linejoin="round" />
					</svg>
					<span>{t('content.sections_prefilled_hint')}</span>
				</div>
			{/if}

			<div class="modal-form">
				<div class="form-group">
					<span class="form-label">{t('content.file')} *</span>
					{#if itemFiles.length > 0}
						<div class="selected-files">
							{#if itemFiles.length > 1}
								<div class="selected-files-head">
									<span class="selected-files-count">
										{itemFiles.length} {t('content.selected_files_count')}
									</span>
									<button type="button" class="selected-files-clear" onclick={clearAllFiles}>
										{t('content.clear_all_files')}
									</button>
								</div>
							{/if}
							<ul class="selected-files-list">
								{#each itemFiles as f, i (i + ':' + f.name + ':' + f.size)}
									<li class="selected-file">
										<span class="selected-file-name" title={f.name}>{f.name}</span>
										<span class="selected-file-size">{formatFileSize(f.size)}</span>
										<button
											type="button"
											class="selected-file-remove"
											onclick={() => removeFileAt(i)}
											aria-label="Remove">×</button
										>
									</li>
								{/each}
							</ul>
							{#if !editingItemId}
								<label class="upload-zone small-zone upload-zone-add" for="multi-file">
									<span>＋ {t('content.click_select_multi')}</span>
								</label>
								<input
									type="file"
									id="multi-file"
									class="file-input-hidden"
									multiple
									onchange={handleFilesSelect}
								/>
							{/if}
						</div>
					{:else}
						<!-- svelte-ignore a11y_no_static_element_interactions -->
						<label
							class="upload-zone"
							class:is-dragging={isDragging}
							for="multi-file"
							ondragover={handleDragOver}
							ondragleave={handleDragLeave}
							ondrop={handleDrop}
						>
							<svg
								viewBox="0 0 24 24"
								fill="none"
								stroke="currentColor"
								stroke-width="1.5"
								class="upload-icon"
								><path
									d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12"
									stroke-linecap="round"
									stroke-linejoin="round"
								/></svg
							>
							<span>{t('content.click_select_multi')}</span>
							<span class="upload-hint">{t('content.drop_files_hint')}</span>
						</label>
						{#if fileSizeWarning}
							<p class="form-hint hint-warn">{fileSizeWarning}</p>
						{/if}
						<input
							type="file"
							id="multi-file"
							class="file-input-hidden"
							multiple={!editingItemId}
							onchange={handleFilesSelect}
						/>
					{/if}
				</div>

				<div class="form-group">
					<label for="multi-title" class="form-label">
						{t('common.title')} {isMultiFileMode ? '' : '*'}
					</label>
					<input
						id="multi-title"
						type="text"
						class="form-input"
						bind:value={itemForm.title}
						placeholder={isMultiFileMode ? t('content.multi_titles_from_filenames') : t('common.title')}
						disabled={isMultiFileMode}
					/>
					{#if isMultiFileMode}
						<span class="form-hint">{t('content.multi_titles_from_filenames')}</span>
					{/if}
				</div>

				<div class="form-group">
					<label for="multi-desc" class="form-label">{t('content.description')}</label>
					<textarea
						id="multi-desc"
						class="form-input form-textarea"
						rows="2"
						bind:value={itemForm.description}
						placeholder={t('common.optional')}
					></textarea>
				</div>

				<div class="form-group">
					<label for="multi-author" class="form-label">{t('content.author')}</label>
					<input
						id="multi-author"
						type="text"
						class="form-input"
						bind:value={itemForm.author}
						placeholder="e.g. John Doe..."
					/>
				</div>

				<div class="form-group">
					<label for="multi-main" class="form-label">{t('sections.main_section')} *</label>
					<select
						id="multi-main"
						class="form-input"
						bind:value={itemForm.main_section}
						onchange={handleMainChange}
					>
						<option value="">{t('common.select')}</option>
						{#each mainSectionsList as ms}<option value={ms.id}>{ms.name}</option>{/each}
					</select>
				</div>

				{#if itemForm.main_section}
					<div class="form-group">
						<label for="multi-sub" class="form-label">{t('sections.sub_section')} *</label>
						<select
							id="multi-sub"
							class="form-input"
							bind:value={itemForm.subsection}
							onchange={handleSubChange}
						>
							<option value="">{t('common.select')}</option>
							{#each itemSubOptions as ss}<option value={ss.id}>{ss.name}</option>{/each}
						</select>
					</div>
				{/if}

				{#if itemForm.subsection && itemSecondaryOptions.length > 0}
					<div class="form-group">
						<label for="multi-sec" class="form-label">{t('sections.secondary')}</label>
						<select
							id="multi-sec"
							class="form-input"
							bind:value={itemForm.secondary_subsection}
							onchange={handleSecondaryChange}
						>
							<option value="">{t('common.none')}</option>
							{#each itemSecondaryOptions as sec}<option value={sec.id}>{sec.name}</option>{/each}
						</select>
					</div>
				{/if}

				<div class="form-group" style="margin-top: 0.75rem;">
					<label class="toggle-switch">
						<input
							type="checkbox"
							class="toggle-input"
							bind:checked={itemForm.is_listed}
						/>
						<span class="toggle-slider"></span>
						<span class="toggle-label">{t('common.is_listed')}</span>
					</label>
				</div>

				<div class="form-group">
					<span class="form-label">{t('content.thumbnail')}</span>
					{#if itemThumbnailPreview}
						<div class="upload-preview">
							<img src={itemThumbnailPreview} alt="Preview" class="preview-img" />
							<button
								type="button"
								class="preview-remove"
								aria-label="Remove Thumbnail"
								onclick={clearThumb}
							>
								<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
									><path
										d="M6 18L18 6M6 6l12 12"
										stroke-linecap="round"
										stroke-linejoin="round"
									/></svg
								>
							</button>
						</div>
					{:else}
						<label class="upload-zone small-zone" for="multi-thumb"
							><span>{t('content.add_thumb')}</span></label
						>
						<input
							type="file"
							id="multi-thumb"
							accept="image/*"
							class="file-input-hidden"
							onchange={handleThumbSelect}
						/>
					{/if}
				</div>

				<div class="modal-actions">
					<button class="btn btn-secondary" onclick={() => (showItemModal = false)}
						>{t('common.cancel')}</button
					>
					<button class="btn btn-primary" onclick={saveItemToQueue}
						>{editingItemId ? t('content.update_item') : t('content.save_item')}</button
					>
				</div>
			</div>
		</div>
	</div>
{/if}

<style>
	.page { display: flex; flex-direction: column; gap: 1.25rem; }
	.page-header { display: flex; align-items: flex-start; justify-content: space-between; gap: 1rem; flex-wrap: wrap; }
	.page-title { font-size: 1.5rem; font-weight: 700; color: var(--color-surface-100); letter-spacing: -0.02em; }
	.page-desc { font-size: 0.8125rem; color: var(--color-surface-400); margin-top: 0.25rem; max-width: 680px; line-height: 1.5; }
	.header-actions { display: flex; gap: 0.5rem; flex-wrap: wrap; }

	.upload-zone.is-dragging {
		border-color: var(--color-primary-500);
		background: rgba(5, 150, 105, 0.08);
	}
	.hint-warn { color: #fbbf24; }

	.tabs { display: flex; gap: 0.25rem; border-bottom: 1px solid var(--color-surface-700); }
	.tab { padding: 0.625rem 1rem; font-size: 0.8125rem; font-weight: 500; color: var(--color-surface-400); text-decoration: none; border-bottom: 2px solid transparent; transition: all 0.15s; }
	.tab:hover { color: var(--color-surface-200); }
	.tab.active { color: var(--color-primary-400); border-bottom-color: var(--color-primary-500); }

	.summary-strip { display: flex; align-items: center; gap: 1.5rem; padding: 1rem 1.25rem; background: linear-gradient(135deg, var(--color-surface-800), var(--color-surface-900)); border: 1px solid var(--color-surface-700); border-radius: 14px; flex-wrap: wrap; }
	.summary-left { display: flex; align-items: baseline; gap: 0.5rem; }
	.summary-count { font-size: 1.75rem; font-weight: 800; color: var(--color-surface-100); letter-spacing: -0.02em; }
	.summary-label { font-size: 0.75rem; color: var(--color-surface-400); text-transform: uppercase; letter-spacing: 0.05em; }
	.summary-progress { flex: 1; min-width: 200px; display: flex; flex-direction: column; gap: 0.375rem; }
	.summary-bar-track { width: 100%; height: 6px; background: var(--color-surface-700); border-radius: 100px; overflow: hidden; }
	.summary-bar-fill { height: 100%; background: linear-gradient(90deg, var(--color-primary-600), var(--color-primary-400)); border-radius: 100px; transition: width 0.3s ease; }
	.summary-numbers { font-size: 0.75rem; color: var(--color-surface-400); }
	.summary-actions { display: flex; gap: 0.5rem; flex-wrap: wrap; }

	.alert { padding: 0.75rem 1rem; border-radius: 10px; font-size: 0.8125rem; display: flex; align-items: center; gap: 0.5rem; }
	.alert-error { background: rgba(244,63,94,0.1); border: 1px solid rgba(244,63,94,0.2); color: var(--color-danger-400); }
	.alert-success { background: rgba(5,150,105,0.1); border: 1px solid rgba(5,150,105,0.2); color: var(--color-primary-400); }
	.alert-info { background: rgba(59,130,246,0.08); border: 1px solid rgba(59,130,246,0.2); color: #93c5fd; }
	.alert-icon { width: 16px; height: 16px; flex-shrink: 0; }

	.hints { display: flex; flex-direction: column; gap: 0.2rem; }
	.hint-note { font-size: 0.75rem; color: var(--color-surface-500); padding: 0.1rem 0.125rem; line-height: 1.5; }
	.hint-info { color: var(--color-primary-400); }

	.queue-container { min-height: 200px; }
	.empty-state { display: flex; flex-direction: column; align-items: center; justify-content: center; padding: 4rem 2rem; gap: 0.75rem; color: var(--color-surface-500); font-size: 0.875rem; background: var(--color-surface-800); border: 1px dashed var(--color-surface-700); border-radius: 14px; }
	.empty-icon { width: 48px; height: 48px; color: var(--color-surface-600); }

	.queue-list { list-style: none; padding: 0; margin: 0; display: flex; flex-direction: column; gap: 0.625rem; }
	.queue-item { display: flex; align-items: center; gap: 1rem; padding: 0.875rem 1rem; background: var(--color-surface-800); border: 1px solid var(--color-surface-700); border-radius: 12px; transition: all 0.15s ease; }
	.queue-item.is-active { border-color: var(--color-primary-500); box-shadow: 0 0 0 2px rgba(5,150,105,0.15); }
	.queue-item.is-completed { opacity: 0.82; }
	.queue-item.is-completed .queue-title { color: var(--color-surface-300); }
	.queue-item.is-failed { border-color: rgba(244,63,94,0.5); }
	.queue-item.is-dragging { opacity: 0.55; border-style: dashed; }
	.queue-item[draggable='true'] { cursor: grab; }
	.queue-item[draggable='true']:active { cursor: grabbing; }

	.queue-order { width: 28px; height: 28px; display: flex; align-items: center; justify-content: center; font-size: 0.75rem; font-weight: 700; color: var(--color-surface-300); background: var(--color-surface-900); border: 1px solid var(--color-surface-700); border-radius: 50%; flex-shrink: 0; }
	.queue-thumb { width: 48px; height: 48px; border-radius: 10px; object-fit: cover; flex-shrink: 0; background: var(--color-surface-900); border: 1px solid var(--color-surface-700); }
	.queue-thumb-fallback { display: flex; align-items: center; justify-content: center; font-size: 1.375rem; color: var(--color-surface-400); }

	.queue-main { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 0.3rem; }
	.queue-title-row { display: flex; align-items: center; gap: 0.5rem; flex-wrap: wrap; }
	.queue-title { font-size: 0.9rem; font-weight: 600; color: var(--color-surface-100); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
	.queue-chip { font-size: 0.6875rem; font-weight: 600; padding: 0.2rem 0.55rem; border-radius: 100px; text-transform: capitalize; }
	.queue-chip-queued { background: rgba(120, 120, 135, 0.18); color: var(--color-surface-300); }
	.queue-chip-uploading { background: rgba(59,130,246,0.15); color: #60a5fa; }
	.queue-chip-committing { background: rgba(168,85,247,0.15); color: #c084fc; }
	.queue-chip-completed { background: rgba(5,150,105,0.18); color: var(--color-primary-400); }
	.queue-chip-failed { background: rgba(244,63,94,0.15); color: var(--color-danger-400); }

	.queue-meta-row { display: flex; align-items: center; gap: 0.4rem; font-size: 0.6875rem; color: var(--color-surface-500); flex-wrap: wrap; }
	.queue-filename { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; max-width: 260px; }
	.queue-dot { color: var(--color-surface-600); }
	.queue-section-chain { color: var(--color-surface-400); }

	.queue-progress { display: flex; align-items: center; gap: 0.5rem; margin-top: 0.2rem; }
	.queue-progress-track { flex: 1; height: 5px; background: var(--color-surface-700); border-radius: 100px; overflow: hidden; }
	.queue-progress-fill { height: 100%; background: linear-gradient(90deg, var(--color-primary-600), var(--color-primary-400)); border-radius: 100px; transition: width 0.3s ease; }
	.queue-progress-pct { font-size: 0.6875rem; font-weight: 600; color: var(--color-primary-400); min-width: 32px; text-align: end; }

	.queue-error { font-size: 0.6875rem; color: var(--color-danger-400); margin-top: 0.25rem; }

	.queue-actions { display: flex; gap: 0.25rem; flex-shrink: 0; }
	.icon-btn { width: 30px; height: 30px; display: flex; align-items: center; justify-content: center; border-radius: 8px; border: 1px solid var(--color-surface-600); background: transparent; color: var(--color-surface-400); cursor: pointer; transition: all 0.15s; }
	.icon-btn svg { width: 14px; height: 14px; }
	.icon-btn:hover:not(:disabled) { background: var(--color-surface-700); color: var(--color-surface-200); }
	.icon-btn:disabled { opacity: 0.35; cursor: not-allowed; }
	.icon-btn.edit:hover:not(:disabled) { background: rgba(5,150,105,0.1); border-color: var(--color-primary-700); color: var(--color-primary-400); }
	.icon-btn.delete:hover:not(:disabled) { background: rgba(244,63,94,0.1); border-color: var(--color-danger-600); color: var(--color-danger-400); }

	/* Buttons */
	.btn { display: inline-flex; align-items: center; gap: 0.5rem; padding: 0.625rem 1.125rem; border-radius: 10px; font-size: 0.8125rem; font-weight: 600; font-family: inherit; cursor: pointer; border: none; transition: all 0.15s; }
	.btn-sm { padding: 0.5rem 0.875rem; font-size: 0.75rem; }
	.btn-icon { width: 16px; height: 16px; }
	.btn-primary { background: linear-gradient(135deg, var(--color-primary-700), var(--color-primary-600)); color: white; }
	.btn-primary:hover:not(:disabled) { box-shadow: 0 4px 12px rgba(5,150,105,0.25); }
	.btn-primary:disabled { opacity: 0.5; cursor: not-allowed; }
	.btn-secondary { background: var(--color-surface-700); color: var(--color-surface-300); border: 1px solid var(--color-surface-600); }
	.btn-secondary:hover:not(:disabled) { background: var(--color-surface-600); }
	.btn-secondary:disabled { opacity: 0.45; cursor: not-allowed; }

	/* Modal */
	.modal-overlay { position: fixed; inset: 0; background: rgba(0,0,0,0.6); backdrop-filter: blur(4px); display: flex; align-items: center; justify-content: center; z-index: 100; padding: 1rem; }
	.modal { width: 100%; max-width: 540px; background: var(--color-surface-800); border: 1px solid var(--color-surface-700); border-radius: 16px; box-shadow: var(--shadow-elevated); max-height: 92vh; overflow-y: auto; }
	.modal-header { display: flex; align-items: center; justify-content: space-between; padding: 1.25rem 1.5rem; border-bottom: 1px solid var(--color-surface-700); }
	.modal-title { font-size: 1.125rem; font-weight: 700; color: var(--color-surface-100); }
	.modal-close { width: 32px; height: 32px; display: flex; align-items: center; justify-content: center; border-radius: 8px; border: none; background: transparent; color: var(--color-surface-500); cursor: pointer; }
	.modal-close:hover { background: var(--color-surface-700); color: var(--color-surface-300); }
	.modal-close svg { width: 18px; height: 18px; }
	.modal-alert { margin: 1rem 1.5rem 0; }
	.modal-form { padding: 1.25rem 1.5rem; display: flex; flex-direction: column; gap: 1rem; }
	.modal-actions { display: flex; justify-content: flex-end; gap: 0.5rem; padding-top: 0.5rem; }

	.form-group { display: flex; flex-direction: column; gap: 0.375rem; }
	.form-label { font-size: 0.8125rem; font-weight: 500; color: var(--color-surface-300); }
	.form-input { padding: 0.625rem 0.75rem; background: var(--color-surface-900); border: 1px solid var(--color-surface-600); border-radius: 8px; color: var(--color-surface-100); font-size: 0.8125rem; font-family: inherit; outline: none; }
	.form-input:focus { border-color: var(--color-primary-600); }
	.form-textarea { resize: vertical; min-height: 50px; }

	.upload-zone { display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 0.5rem; padding: 1.5rem; border: 2px dashed var(--color-surface-600); border-radius: 12px; background: var(--color-surface-900); cursor: pointer; transition: all 0.2s ease; color: var(--color-surface-400); font-size: 0.8125rem; }
	.upload-zone:hover { border-color: var(--color-primary-600); background: rgba(5,150,105,0.05); color: var(--color-primary-400); }
	.small-zone { padding: 0.75rem; }
	.upload-icon { width: 28px; height: 28px; }
	.upload-hint { font-size: 0.6875rem; color: var(--color-surface-500); }
	.file-input-hidden { position: absolute; width: 0; height: 0; opacity: 0; pointer-events: none; }
	.upload-preview { position: relative; border-radius: 10px; overflow: hidden; border: 1px solid var(--color-surface-600); }
	.preview-img { width: 100%; max-height: 120px; object-fit: cover; display: block; }
	.preview-remove { position: absolute; top: 0.5rem; right: 0.5rem; width: 28px; height: 28px; display: flex; align-items: center; justify-content: center; border-radius: 50%; background: rgba(0,0,0,0.6); border: none; color: white; cursor: pointer; }
	.preview-remove:hover { background: rgba(244,63,94,0.8); }
	.preview-remove svg { width: 14px; height: 14px; }

	.selected-files { display: flex; flex-direction: column; gap: 0.5rem; }
	.selected-files-head { display: flex; align-items: center; justify-content: space-between; padding: 0 0.125rem; }
	.selected-files-count { font-size: 0.75rem; color: var(--color-surface-300); font-weight: 600; }
	.selected-files-clear { background: none; border: none; color: var(--color-danger-400); font-size: 0.75rem; cursor: pointer; padding: 0.25rem 0.5rem; border-radius: 6px; }
	.selected-files-clear:hover { background: rgba(244,63,94,0.08); }
	.selected-files-list { list-style: none; padding: 0; margin: 0; display: flex; flex-direction: column; gap: 0.375rem; max-height: 240px; overflow-y: auto; }
	.selected-file { display: flex; align-items: center; gap: 0.5rem; padding: 0.625rem 0.875rem; background: var(--color-surface-900); border: 1px solid var(--color-primary-700); border-radius: 10px; }
	.selected-file-name { flex: 1; font-size: 0.8125rem; color: var(--color-surface-100); font-weight: 500; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; min-width: 0; }
	.selected-file-size { font-size: 0.6875rem; color: var(--color-surface-400); flex-shrink: 0; }
	.selected-file-remove { background: none; border: none; color: var(--color-surface-400); cursor: pointer; font-size: 1.25rem; padding: 0 0.25rem; line-height: 1; }
	.selected-file-remove:hover { color: var(--color-danger-400); }
	.upload-zone-add { font-size: 0.75rem; padding: 0.5rem 0.75rem; }
	.form-hint { font-size: 0.6875rem; color: var(--color-surface-500); line-height: 1.4; }

	.concurrency-picker { display: inline-flex; align-items: center; gap: 0.4rem; padding: 0.4rem 0.625rem; background: var(--color-surface-800); border: 1px solid var(--color-surface-700); border-radius: 10px; }
	.concurrency-label { font-size: 0.6875rem; font-weight: 600; color: var(--color-surface-400); text-transform: uppercase; letter-spacing: 0.04em; }
	.concurrency-select { background: var(--color-surface-900); color: var(--color-surface-100); border: 1px solid var(--color-surface-600); border-radius: 6px; font-size: 0.8125rem; padding: 0.2rem 0.4rem; font-family: inherit; cursor: pointer; }
	.concurrency-select:disabled { opacity: 0.6; cursor: not-allowed; }

	:global(.animate-fade-in) { animation: fadeIn 0.15s ease-out; }
	@keyframes fadeIn { from { opacity: 0; transform: translateY(8px); } to { opacity: 1; transform: translateY(0); } }

	@media (max-width: 820px) {
		.queue-item { flex-wrap: wrap; }
		.queue-main { min-width: 100%; order: 3; }
		.queue-actions { margin-inline-start: auto; }
		.queue-filename { max-width: 180px; }
	}

	@media (max-width: 540px) {
		.summary-strip { flex-direction: column; align-items: stretch; }
		.summary-actions { justify-content: flex-end; }
	}
</style>
