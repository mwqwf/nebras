<script>
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { page } from '$app/state';
	import { listMyFiles, removeFile, updateFile, listMyMainSections, listMySubSections, listMySecondarySections, getLastPartialFailures } from '$lib/api/moderator.js';
	import { createFileUploader, createResumeUploader, formatFileSize, mimeToContentType, validateMultiUploadFile, compressImageFile } from '$lib/utils/fileUpload.js';
	import { notifyContentAdded } from '$lib/utils/notifyEvents.js';
	import { t } from '$lib/i18n/store.svelte.js';
	import { tokenize, highlightMatches } from '$lib/utils/search.js';
	import EngagementBadge from '$lib/components/EngagementBadge.svelte';

	// سياسة الجلب: لا تحميل تلقائيّ — الشاشة تبقى فارغة حتّى يبحث المستخدم.

	// List state
	let items = $state([]);
	let totalCount = $state(0);
	let currentPage = $state(1);
	let searchQuery = $state('');
	let filterMainSection = $state('');
	let filterContentType = $state('');
	let filterIsListed = $state('');
	let isLoading = $state(false);
	let hasSearched = $state(false);
	let error = $state('');

	let mainSectionsList = $state([]);
	let subSectionsList = $state([]);
	let secondarySectionsList = $state([]);
	let searchTokens = $state([]);
	let partialFailures = $state([]);

	// Upload modal
	let showUploadModal = $state(false);
	let uploadFile = $state(null);
	let uploadForm = $state({ title: '', description: '', author: '', main_section: '', subsection: '', secondary_subsection: '', is_listed: true, source_name: '', license_name: '', license_url: '', license_status: '' });
	let uploadThumbnail = $state(null);
	let uploadThumbnailPreview = $state('');
	let uploadFormError = $state('');
	let uploadSubOptions = $state([]);
	let uploadSecondaryOptions = $state([]);

	// Upload progress
	let uploadStatus = $state(''); // '' | 'initiating' | 'uploading' | 'completing' | 'completed' | 'failed'
	let uploadProgress = $state(0);
	let currentUploader = $state(null);
	let isUploading = $state(false); // حارس منع الإرسال المزدوج

	// Edit modal
	let showEditModal = $state(false);
	let editingItem = $state(null);
	let editForm = $state({ title: '', description: '', author: '', main_section: '', subsection: '', secondary_subsection: '', is_listed: true });
	let editFile = $state(null);
	let editThumbnail = $state(null);
	let editThumbnailPreview = $state('');
	let editSubOptions = $state([]);
	let editSecondaryOptions = $state([]);
	let editHierarchySnapshot = $state({ main_section: '', subsection: '', secondary_subsection: '' });
	let editFormError = $state('');
	let editFormLoading = $state(false);

	// Bulk selection / delete
	let selectedIds = $state(new Set());
	let showBulkDeleteModal = $state(false);
	let bulkDeleting = $state(false);

	// Delete modal
	let showDeleteModal = $state(false);
	let deletingItem = $state(null);
	let deleteLoading = $state(false);

	// Detail modal
	let showDetailModal = $state(false);
	let detailItem = $state(null);

	// Resume modal
	let showResumeModal = $state(false);
	let resumeItem = $state(null);
	let resumeFile = $state(null);
	let resumeStatus = $state('');
	let resumeProgress = $state(0);
	let resumeError = $state('');
	let currentResumeUploader = $state(null);

	function consumeModalIntent() {
		const params = page.url?.searchParams;
		const modal = params?.get('modal');
		const id = params?.get('id');
		if (!modal || !id) return false;
		const item = items.find((entry) => String(entry.id) === String(id));
		if (!item) return false;
		if (modal === 'edit') openEditModal(item);
		if (modal === 'delete') openDeleteModal(item);
		goto(page.url.pathname, { replaceState: true, noScroll: true, keepFocus: true });
		return true;
	}

	const PAGE_SIZE = 10;
	let totalPages = $derived(Math.ceil(totalCount / PAGE_SIZE));

	async function fetchItems() {
		const q = String(searchQuery || '').trim();
		const hasActiveFilter = !!filterMainSection || !!filterContentType || filterIsListed !== '';
		if (!q && !hasActiveFilter) {
			items = []; totalCount = 0; hasSearched = false; isLoading = false; searchTokens = []; return;
		}
		isLoading = true; error = ''; hasSearched = true; searchTokens = tokenize(q);
		try {
			const data = await listMyFiles({
				search: q,
				main_section: filterMainSection || undefined,
				content_type: filterContentType || undefined,
				metadata__is_listed: filterIsListed === '' ? undefined : filterIsListed === 'true',
				page: currentPage,
				requireSearch: true
			});
			items = data.results; totalCount = data.count;
			partialFailures = getLastPartialFailures();
		} catch (err) { error = friendlyError(err, 'تعذّر تحميل القائمة.'); }
		finally { isLoading = false; }
	}

	async function fetchMainOptions() {
		try { const d = await listMyMainSections({ all: true }); mainSectionsList = d.results; } catch {}
	}

	async function fetchSubOpts(mainId) {
		try { const d = await listMySubSections({ main_section: mainId || undefined, all: true }); uploadSubOptions = d.results; }
		catch { uploadSubOptions = []; }
	}

	async function fetchSecOpts(subId) {
		try { const d = await listMySecondarySections({ sub_section: subId || undefined, all: true }); uploadSecondaryOptions = d.results; }
		catch { uploadSecondaryOptions = []; }
	}

	function handleSearchKey(e) {
		if (e.key === 'Enter') { e.preventDefault(); submitSearch(); }
		else if (e.key === 'Escape') { e.preventDefault(); clearSearch(); }
	}
	function submitSearch() { currentPage = 1; fetchItems(); }
	function clearSearch() {
		searchQuery = '';
		searchTokens = [];
		const hasActiveFilter = !!filterMainSection || !!filterContentType || filterIsListed !== '';
		if (hasActiveFilter) { currentPage = 1; fetchItems(); }
		else { items = []; totalCount = 0; hasSearched = false; error = ''; }
	}
	function handleFilterChange() { currentPage = 1; fetchItems(); }
	function goToPage(p) { if (p < 1 || p > totalPages) return; currentPage = p; if (hasSearched) fetchItems(); }

	// ─── Upload Modal ───────────────────────────────────
	function openUploadModal() {
		uploadFile = null; uploadForm = { title: '', description: '', author: '', main_section: '', subsection: '', secondary_subsection: '', is_listed: true, source_name: '', license_name: '', license_url: '', license_status: '' };
		uploadThumbnail = null; uploadThumbnailPreview = ''; uploadFormError = '';
		uploadSubOptions = []; uploadSecondaryOptions = [];
		uploadStatus = ''; uploadProgress = 0; currentUploader = null;
		showUploadModal = true;
		if (mainSectionsList.length === 0) fetchMainOptions();
	}

	// رسائل عربية واضحة لنتيجة فحص الملف (بدل الإنجليزية الخام من المكتبة).
	function localizeUploadCheck(check) {
		const msg = check?.error || check?.warn || '';
		if (/exceeds/i.test(msg)) return 'حجم الملف يتجاوز الحدّ المسموح (500 ميجابايت).';
		if (/Unsupported/i.test(msg)) return 'نوع الملف غير مدعوم. المسموح: PDF، وثائق، صوت، فيديو، صور.';
		if (/Large file/i.test(msg)) return 'ملف كبير الحجم — قد يستغرق الرفع وقتاً أطول.';
		return msg;
	}

	function handleFileSelect(e) {
		const f = e.target.files?.[0];
		if (!f) return;
		// تحقّق مبكر من النوع/الحجم قبل أيّ رفع (يمنع رفعات فاشلة واستهلاك الباندويث).
		const check = validateMultiUploadFile(f);
		if (!check.ok) {
			uploadFormError = localizeUploadCheck(check);
			uploadFile = null;
			e.target.value = ''; // اسمح بإعادة اختيار نفس الملف لاحقاً
			return;
		}
		uploadFormError = check.warn ? localizeUploadCheck(check) : '';
		uploadFile = f;
		if (!uploadForm.title) uploadForm.title = f.name.replace(/\.[^/.]+$/, '');
	}

	function handleUploadMainChange() {
		uploadForm.subsection = ''; uploadForm.secondary_subsection = '';
		uploadSecondaryOptions = [];
		if (uploadForm.main_section) fetchSubOpts(uploadForm.main_section);
		else uploadSubOptions = [];
	}

	function handleUploadSubChange() {
		uploadForm.secondary_subsection = '';
		if (uploadForm.subsection) fetchSecOpts(uploadForm.subsection);
		else uploadSecondaryOptions = [];
	}

	function handleUploadThumbChange(e) {
		const f = e.target.files?.[0];
		if (f) { uploadThumbnail = f; const r = new FileReader(); r.onload = (ev) => { uploadThumbnailPreview = ev.target.result; }; r.readAsDataURL(f); }
	}

	async function startUpload() {
		if (isUploading) return; // 🛡️ منع الإرسال المزدوج (نقرتان سريعتان)
		uploadFormError = '';
		if (!uploadFile) { uploadFormError = 'اختر ملفاً أولاً.'; return; }
		const fileCheck = validateMultiUploadFile(uploadFile);
		if (!fileCheck.ok) { uploadFormError = localizeUploadCheck(fileCheck); return; }
		if (!uploadForm.subsection) { uploadFormError = 'اختر قسماً فرعياً.'; return; }
		if (!uploadForm.title) { uploadFormError = 'أدخل عنواناً.'; return; }

		const contentType = mimeToContentType(uploadFile.type);
		const metadata = {
			title: uploadForm.title,
			description: uploadForm.description || undefined,
			author: uploadForm.author || undefined,
			subsection: String(uploadForm.subsection),
			content_type: contentType,
			is_listed: uploadForm.is_listed
		};
		if (uploadForm.secondary_subsection) metadata.secondary_subsection = String(uploadForm.secondary_subsection);
		// ⚖️ المصدر والرخصة (اختياريّة) — للإسناد والامتثال. تُمرَّر فقط حين تُملأ.
		if (uploadForm.source_name) metadata.source_name = uploadForm.source_name.trim();
		if (uploadForm.license_name) metadata.license_name = uploadForm.license_name.trim();
		if (uploadForm.license_url) metadata.license_url = uploadForm.license_url.trim();
		if (uploadForm.license_status) metadata.license_status = uploadForm.license_status.trim();

		isUploading = true;
		try {
			// ضغط الصورة المصغّرة قبل الرفع (يقلّل حجم Storage وزمن تحميل التطبيق).
			let thumb = uploadThumbnail;
			if (thumb) { try { thumb = await compressImageFile(thumb); } catch { thumb = uploadThumbnail; } }

			const uploader = createFileUploader(uploadFile, metadata, thumb, {
				onProgress: (p) => { uploadProgress = p; },
				onStatus: (s) => { uploadStatus = s; },
				onError: (msg) => { uploadFormError = msg; }
			});
			currentUploader = uploader;

			const result = await uploader.start();
			// إشعار FCM غير مُعطِّل: لا نَوقف التدفّق إن فشل.
			const mainName = mainSectionsList.find((m) => String(m.id) === String(uploadForm.main_section))?.name || '';
			const subName = uploadSubOptions.find((s) => String(s.id) === String(uploadForm.subsection))?.name || '';
			const secName = uploadSecondaryOptions.find((s) => String(s.id) === String(uploadForm.secondary_subsection))?.name || '';
			notifyContentAdded({
				title: uploadForm.title,
				contentType: contentType,
				contentId: result?.id,
				// رابط المصدر والصورة المصغّرة: يمكّنان التطبيق من فتح المحتوى
				// مباشرةً من حمولة الإشعار دون جلب إضافيّ من الشبكة (مهمّ على
				// الإنترنت الضعيف، ويتجنّب الهبوط على قائمة القسم).
				sourceUrl: result?.downloadUrl,
				thumbnail: result?.thumbnail,
				mainSectionId: uploadForm.main_section,
				subSectionId: uploadForm.subsection,
				secondarySectionId: uploadForm.secondary_subsection,
				mainSectionName: mainName,
				subSectionName: subName,
				secondarySectionName: secName
			});
			setTimeout(() => { showUploadModal = false; if (hasSearched) fetchItems(); }, 800);
		} catch { /* error already handled via onError */ } finally {
			isUploading = false;
		}
	}

	function cancelUpload() {
		if (currentUploader) currentUploader.abort();
		showUploadModal = false;
		if (hasSearched) fetchItems();
	}

	// ─── Edit ───────────────────────────────────────────
	async function openEditModal(item) {
		editingItem = item;
		let inferredMain = item.metadata?.main_section || item.main_section || '';
		if (mainSectionsList.length === 0) await fetchMainOptions();
		const allSubs = await listMySubSections({ all: true });
		const currentSub = (allSubs.results || []).find((s) => String(s.id) === String(item.metadata?.subsection || ''));
		if (!inferredMain && currentSub?.main_section) inferredMain = currentSub.main_section;
		editSubOptions = inferredMain
			? (await listMySubSections({ main_section: inferredMain, all: true })).results || []
			: allSubs.results || [];
		editSecondaryOptions = item.metadata?.subsection
			? (await listMySecondarySections({ sub_section: item.metadata.subsection, all: true })).results || []
			: [];
		editForm = {
			title: item.metadata?.title || '',
			description: item.metadata?.description || '',
			author: item.metadata?.author || '',
			main_section: inferredMain || '',
			subsection: item.metadata?.subsection || '',
			secondary_subsection: item.metadata?.secondary_subsection || '',
			is_listed: item.metadata?.is_listed ?? true
		};
		editFile = null;
		editThumbnail = null;
		editThumbnailPreview = item.metadata?.thumbnail || '';
		editHierarchySnapshot = {
			main_section: inferredMain || '',
			subsection: item.metadata?.subsection || '',
			secondary_subsection: item.metadata?.secondary_subsection || ''
		};
		editFormError = '';
		showEditModal = true;
	}

	async function handleEditMainChange() {
		editForm.subsection = '';
		editForm.secondary_subsection = '';
		editSecondaryOptions = [];
		editSubOptions = editForm.main_section
			? (await listMySubSections({ main_section: editForm.main_section, all: true })).results || []
			: [];
	}

	async function handleEditSubChange() {
		editForm.secondary_subsection = '';
		editSecondaryOptions = editForm.subsection
			? (await listMySecondarySections({ sub_section: editForm.subsection, all: true })).results || []
			: [];
	}

	function handleEditFileSelect(e) {
		const f = e.target.files?.[0];
		if (f) editFile = f;
	}

	function handleEditThumbnailChange(e) {
		const f = e.target.files?.[0];
		if (!f) return;
		editThumbnail = f;
		const r = new FileReader();
		r.onload = (ev) => { editThumbnailPreview = ev.target.result; };
		r.readAsDataURL(f);
	}

	async function handleEdit() {
		editFormError = ''; editFormLoading = true;
		try {
			const metadata = {
				title: editForm.title,
				description: editForm.description || undefined,
				author: editForm.author || undefined,
				is_listed: editForm.is_listed
			};
			if (String(editForm.main_section || '') !== String(editHierarchySnapshot.main_section || '')) {
				metadata.main_section = editForm.main_section || undefined;
			}
			if (String(editForm.subsection || '') !== String(editHierarchySnapshot.subsection || '')) {
				metadata.subsection = editForm.subsection || undefined;
			}
			if (String(editForm.secondary_subsection || '') !== String(editHierarchySnapshot.secondary_subsection || '')) {
				metadata.secondary_subsection = editForm.secondary_subsection || undefined;
			}
			await updateFile(editingItem.id, {
				metadata,
				...(editFile ? { file: editFile } : {}),
				...(editThumbnail ? { thumbnail: editThumbnail } : {})
			});
			showEditModal = false; if (hasSearched) fetchItems();
		} catch (err) { editFormError = friendlyError(err); }
		finally { editFormLoading = false; }
	}

	// رسالة خطأ مفهومة بدل النصّ الخام/JSON الآتي من طبقة الـ API.
	function friendlyError(err, fallback = 'حدث خطأ غير متوقّع. حاول مجدداً.') {
		let msg = err?.message ?? String(err ?? '');
		if (msg.startsWith('{') || msg.startsWith('[')) {
			try { const o = JSON.parse(msg); msg = o?.message || o?.error || o?.detail || ''; } catch { /* ليست JSON */ }
		}
		msg = String(msg || '').trim();
		if (!msg) return fallback;
		if (/network|failed to fetch|networkerror/i.test(msg)) return 'تعذّر الاتصال بالخادم. تحقّق من الإنترنت وحاول مجدداً.';
		if (/permission|forbidden|unauthor/i.test(msg)) return 'لا تملك صلاحية لهذه العملية.';
		if (/quota|exceeded/i.test(msg)) return 'تم تجاوز حدّ التخزين/الحصّة. حاول لاحقاً.';
		return msg; // رسالة عربية أو مفهومة أصلاً
	}

	// ─── Delete ─────────────────────────────────────────
	function openDeleteModal(item) { deletingItem = item; showDeleteModal = true; }
	async function handleDelete() {
		deleteLoading = true;
		try { await removeFile(deletingItem.id); showDeleteModal = false; deletingItem = null; if (hasSearched) fetchItems(); }
		catch (err) { error = friendlyError(err); showDeleteModal = false; }
		finally { deleteLoading = false; }
	}

	// ─── Bulk select / delete ───────────────────────────
	let allSelected = $derived(items.length > 0 && items.every((it) => selectedIds.has(it.id)));
	function toggleSelect(id) {
		const next = new Set(selectedIds);
		if (next.has(id)) next.delete(id); else next.add(id);
		selectedIds = next;
	}
	function clearSelection() { selectedIds = new Set(); }
	function toggleSelectAll() {
		selectedIds = allSelected ? new Set() : new Set(items.map((it) => it.id));
	}
	async function handleBulkDelete() {
		if (bulkDeleting || selectedIds.size === 0) return;
		bulkDeleting = true;
		const ids = [...selectedIds];
		let ok = 0, fail = 0;
		for (const id of ids) {
			try { await removeFile(id); ok += 1; } catch { fail += 1; }
		}
		bulkDeleting = false;
		showBulkDeleteModal = false;
		selectedIds = new Set();
		error = fail > 0 ? `حُذف ${ok} عنصراً، وتعذّر حذف ${fail}.` : '';
		if (hasSearched) fetchItems();
	}

	function handleRowClick(item) {
		if (item.upload_status === 'pending') {
			openResumeModal(item);
		} else {
			openDetailModal(item);
		}
	}

	function openDetailModal(item) { detailItem = item; showDetailModal = true; }

	// ─── Resume ────────────────────────────────────────
	function openResumeModal(item) {
		resumeItem = item;
		resumeFile = null;
		resumeStatus = '';
		resumeProgress = 0;
		resumeError = '';
		currentResumeUploader = null;
		// Show initial progress for multipart
		if (item.multipart_uploader) {
			const { uploaded_parts, total_parts } = item.multipart_uploader;
			resumeProgress = Math.round((uploaded_parts / total_parts) * 100);
		}
		showResumeModal = true;
	}

	function handleResumeFileSelect(e) {
		const f = e.target.files?.[0];
		if (f) resumeFile = f;
	}

	async function startResume() {
		resumeError = '';
		if (!resumeFile) { resumeError = 'Please re-select the original file.'; return; }

		const uploader = createResumeUploader(resumeItem, resumeFile, {
			onProgress: (p) => { resumeProgress = p; },
			onStatus: (s) => { resumeStatus = s; },
			onError: (msg) => { resumeError = msg; }
		});
		currentResumeUploader = uploader;

		try {
			await uploader.start();
			setTimeout(() => { showResumeModal = false; if (hasSearched) fetchItems(); }, 800);
		} catch { /* handled via onError */ }
	}

	function cancelResume() {
		if (currentResumeUploader) currentResumeUploader.abort();
		showResumeModal = false;
		if (hasSearched) fetchItems();
	}
	function formatDate(d) { if (!d) return '—'; return new Date(d).toLocaleDateString('en-US', { year: 'numeric', month: 'short', day: 'numeric' }); }

	function statusColor(s) {
		if (s === 'completed') return 'status-completed';
		if (s === 'failed') return 'status-failed';
		return 'status-pending';
	}

	function contentTypeIcon(ct) {
		if (ct === 'video') return '🎬';
		if (ct === 'audio') return '🎵';
		return '📄';
	}

	onMount(async () => {
		const q = String(page.url?.searchParams.get('q') || '').trim();
		if (!q) return;
		searchQuery = q;
		currentPage = 1;
		await fetchItems();
		consumeModalIntent();
	});
</script>

<svelte:head><title>{t('content.title')} — Nebras</title></svelte:head>

<div class="page">
	<div class="page-header">
		<div><h1 class="page-title">{t('content.my_content')}</h1><p class="page-desc">{t('content.my_content_desc')}</p></div>
		<button class="btn btn-primary" onclick={openUploadModal}>
			<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="btn-icon"><path d="M12 5v14m-7-7h14" /></svg>
			{t('content.upload_file')}
		</button>
	</div>

	<div class="tabs">
		<a href="/moderator/content/files" class="tab active">{t('content.file_uploads')}</a>
		<a href="/moderator/content/multi" class="tab">{t('content.multi_upload')}</a>
	</div>

	<div class="toolbar">
		{#if searchQuery}
			<div class="active-query-chip" title={searchQuery}>
				<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="search-icon"><path d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" /></svg>
				<span class="active-query-text">{searchQuery}</span>
				<button type="button" class="search-clear" aria-label={t('common.search_clear')} title={t('common.search_clear')} onclick={clearSearch}>
					<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 18L18 6M6 6l12 12" /></svg>
				</button>
			</div>
		{/if}
		<select class="filter-select" bind:value={filterContentType} onchange={handleFilterChange}>
			<option value="">{t('content.all_types')}</option>
			<option value="video">{t('content.video')}</option>
			<option value="audio">{t('content.audio')}</option>
			<option value="document">{t('content.document')}</option>
		</select>
		<select class="filter-select" bind:value={filterMainSection} onchange={handleFilterChange} onfocus={() => { if (mainSectionsList.length === 0) fetchMainOptions(); }}>
			<option value="">{t('content.all_sections')}</option>
			{#each mainSectionsList as ms}<option value={ms.id}>{ms.name}</option>{/each}
		</select>
		<select class="filter-select" bind:value={filterIsListed} onchange={handleFilterChange}>
			<option value="">{t('common.all')} ({t('common.is_listed')})</option>
			<option value="true">{t('common.listed')}</option>
			<option value="false">{t('common.unlisted')}</option>
		</select>
		<div class="count-badge">{totalCount} {t('common.total')}</div>
	</div>

	{#if error}<div class="alert alert-error">{error}</div>{/if}

	{#if partialFailures.length > 0}
		<div class="alert alert-warning" style="margin-bottom:0.75rem">
			{t('common.search_partial_warning')}
			{#each partialFailures as f}
				<span style="display:inline-block;margin:0 0.35rem">· {f.source}</span>
			{/each}
		</div>
	{/if}

	<div class="content-container">
		{#if isLoading}
			<div class="file-list skeleton-list" aria-busy="true">
				{#each Array(6) as _, i (i)}
					<div class="skeleton-row"><div class="sk-line"></div><div class="sk-line sk-short"></div></div>
				{/each}
			</div>
		{:else if !hasSearched}
			<div class="state-box empty-state">
				<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" class="empty-icon"><path d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" stroke-linecap="round" stroke-linejoin="round" /></svg>
				<p class="empty-title">{t('common.search_empty_title')}</p>
				<p class="empty-hint">{t('common.search_use_header')}</p>
				<button type="button" class="btn btn-secondary" style="margin-top:0.75rem" onclick={() => { const el = document.getElementById('search-input'); if (el) { el.focus(); el.scrollIntoView({ block: 'center' }); } }}>
					{t('common.search_open_global')}
				</button>
			</div>
		{:else if items.length === 0}
			<div class="state-box empty-state">
				<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" class="empty-icon"><path d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12" stroke-linecap="round" stroke-linejoin="round" /></svg>
				<p>{t('common.search_no_results')}</p>
			</div>
		{:else}
			<div class="bulk-bar" style="display:flex; align-items:center; gap:0.75rem; flex-wrap:wrap; margin-bottom:0.75rem;">
				<label style="display:flex; align-items:center; gap:0.4rem; cursor:pointer; font-size:0.85rem;">
					<input type="checkbox" checked={allSelected} onchange={toggleSelectAll} />
					<span>تحديد الكل</span>
				</label>
				{#if selectedIds.size > 0}
					<span style="font-size:0.85rem; opacity:0.8;">{selectedIds.size} محدّد</span>
					<button type="button" class="btn btn-danger" onclick={() => (showBulkDeleteModal = true)}>🗑 حذف المحدد</button>
					<button type="button" class="btn btn-secondary" onclick={clearSelection}>إلغاء التحديد</button>
				{/if}
			</div>
			<div class="file-list">
				{#each items as item (item.id)}
					<!-- svelte-ignore a11y_click_events_have_key_events -->
					<!-- svelte-ignore a11y_no_static_element_interactions -->
					<div class="file-row" class:file-row-pending={item.upload_status === 'pending'} onclick={() => handleRowClick(item)}>
						<!-- svelte-ignore a11y_click_events_have_key_events -->
						<input type="checkbox" checked={selectedIds.has(item.id)} onclick={(e) => e.stopPropagation()} onchange={() => toggleSelect(item.id)} style="flex:none; margin-inline-start:0.25rem; width:1.05rem; height:1.05rem; cursor:pointer;" />
						<div class="file-icon">{contentTypeIcon(item.metadata?.content_type)}</div>
						<div class="file-info">
							<span class="file-name">{@html highlightMatches(item.metadata?.title || item.filename || 'Untitled', searchTokens)}</span>
							<span class="file-meta" style="color: {item.metadata?.is_listed === false ? 'var(--color-danger-400)' : 'inherit'};">
								{item.metadata?.is_listed === false ? t('common.unlisted') : `${item.file_type} · ${formatFileSize(item.file_size)}`}
							</span>
							<EngagementBadge stats={item.engagement} />
						</div>
						<span class="file-status {statusColor(item.upload_status)}">{item.upload_status}</span>
						<span class="file-date">{formatDate(item.metadata?.created_at)}</span>
						<div class="file-actions" role="presentation" onclick={(e) => e.stopPropagation()}>
							<button class="action-btn edit" title="Edit" onclick={() => openEditModal(item)}>
								<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" /></svg>
							</button>
							<button class="action-btn delete" title="Delete" onclick={() => openDeleteModal(item)}>
								<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" /></svg>
							</button>
						</div>
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

<!-- ═══════════════ Upload Modal ═══════════════ -->
{#if showUploadModal}
	<!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
	<div class="modal-overlay" role="dialog" tabindex="-1" onkeydown={(e) => e.key === 'Escape' && (showUploadModal = false)} onclick={(e) => { if (e.target === e.currentTarget && !uploadStatus) showUploadModal = false; }}>
		<div class="modal animate-fade-in">
			<div class="modal-header">
				<h2 class="modal-title">{t('content.upload_file')}</h2>
				{#if !uploadStatus}<button class="modal-close" aria-label="Close" onclick={() => (showUploadModal = false)}>
					<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M6 18L18 6M6 6l12 12" stroke-linecap="round" stroke-linejoin="round" /></svg>
				</button>{/if}
			</div>

			{#if uploadStatus}
				<!-- Upload in progress -->
				<div class="upload-progress-pane">
					<div class="progress-file-name">{uploadFile?.name}</div>
					<div class="progress-bar-track"><div class="progress-bar-fill" style="width:{uploadProgress}%"></div></div>
					<div class="progress-info">
						<span class="progress-pct">{uploadProgress}%</span>
						<span class="progress-status">{uploadStatus === 'initiating' ? t('content.preparing') : uploadStatus === 'uploading' ? t('content.uploading') : uploadStatus === 'completing' ? t('content.finalizing') : uploadStatus === 'completed' ? t('content.complete') : t('content.failed')}</span>
					</div>
					{#if uploadFormError}<div class="alert alert-error" style="margin-top:0.75rem">{uploadFormError}</div>{/if}
					{#if uploadStatus === 'completed'}
						<button class="btn btn-primary" style="margin-top:1rem;align-self:center" onclick={() => { showUploadModal = false; if (hasSearched) fetchItems(); }}>{t('common.done')}</button>
					{:else if uploadStatus === 'failed'}
						<div class="modal-actions" style="margin-top:1rem">
							<button class="btn btn-secondary" onclick={cancelUpload}>{t('common.close')}</button>
							<button class="btn btn-primary" onclick={() => { uploadStatus = ''; uploadProgress = 0; uploadFormError = ''; }}>{t('common.retry')}</button>
						</div>
					{:else}
						<button class="btn btn-secondary" style="margin-top:1rem;align-self:center" onclick={cancelUpload}>{t('common.cancel')}</button>
					{/if}
				</div>
			{:else}
				<!-- Upload form -->
				{#if uploadFormError}<div class="alert alert-error modal-alert">{uploadFormError}</div>{/if}
				<div class="modal-form">
					<!-- File picker -->
					<div class="form-group">
						<span class="form-label">{t('content.file')} *</span>
						{#if uploadFile}
							<div class="selected-file">
								<span class="selected-file-name">{uploadFile.name}</span>
								<span class="selected-file-size">{formatFileSize(uploadFile.size)}</span>
								<button type="button" class="selected-file-remove" onclick={() => { uploadFile = null; }}>×</button>
							</div>
						{:else}
							<label class="upload-zone" for="upload-file">
								<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" class="upload-icon"><path d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12" stroke-linecap="round" stroke-linejoin="round" /></svg>
								<span>{t('content.click_select')}</span>
								<span class="upload-hint">{t('content.upload_hint')}</span>
							</label>
							<input type="file" id="upload-file" accept=".pdf,.epub,.doc,.docx,.txt,.rtf,.mp3,.m4a,.wav,.ogg,.aac,.flac,.mp4,.webm,.mov,.mkv,.avi,.jpg,.jpeg,.png,.gif,.webp,.bmp,.svg" class="file-input-hidden" onchange={handleFileSelect} />
						{/if}
					</div>
					<div class="form-group"><label for="up-title" class="form-label">{t('common.title')} *</label><input type="text" id="up-title" bind:value={uploadForm.title} class="form-input" placeholder={t('common.title')} /></div>
					<div class="form-group"><label for="up-desc" class="form-label">{t('content.description')}</label><textarea id="up-desc" bind:value={uploadForm.description} class="form-input form-textarea" rows="2" placeholder={t('common.optional')}></textarea></div>
					<div class="form-group"><label for="up-author" class="form-label">{t('content.author')}</label><input type="text" id="up-author" bind:value={uploadForm.author} class="form-input" placeholder="e.g. John Doe..." /></div>
					<!-- ⚖️ المصدر والرخصة (اختياريّة) — للإسناد وامتثال الحقوق. تظهر في التطبيق وتُعين على ردّ بلاغات DMCA. -->
					<div class="form-group"><label for="up-source" class="form-label">المصدر (اختياري)</label><input type="text" id="up-source" bind:value={uploadForm.source_name} class="form-input" placeholder="مثل: Internet Archive، مؤسسة هنداوي، مكتبة نور" /></div>
					<div class="form-group"><label for="up-license-name" class="form-label">اسم الرخصة (اختياري)</label><input type="text" id="up-license-name" bind:value={uploadForm.license_name} class="form-input" placeholder="مثل: Public Domain، Creative Commons" /></div>
					<div class="form-group"><label for="up-license-url" class="form-label">رابط الرخصة (اختياري)</label><input type="url" id="up-license-url" bind:value={uploadForm.license_url} class="form-input" placeholder="https://creativecommons.org/..." /></div>
					<div class="form-group"><label for="up-license-status" class="form-label">حالة الترخيص (اختياري)</label>
						<select id="up-license-status" bind:value={uploadForm.license_status} class="form-input">
							<option value="">— غير محدَّد —</option>
							<option value="verified_open_license">ملكيّة عامّة / رخصة مفتوحة موثّقة</option>
							<option value="manual_confirmed">أكّده مشرف يدويّاً</option>
							<option value="rejected">مرفوض (يُحجَب عن التطبيق)</option>
						</select>
					</div>
					<!-- Section selectors -->
					<div class="form-group">
						<label for="up-main" class="form-label">{t('sections.main_section')} *</label>
						<select id="up-main" bind:value={uploadForm.main_section} class="form-input" onchange={handleUploadMainChange}>
							<option value="">{t('common.select')}</option>
							{#each mainSectionsList as ms}<option value={ms.id}>{ms.name}</option>{/each}
						</select>
					</div>
					{#if uploadForm.main_section}
						<div class="form-group">
							<label for="up-sub" class="form-label">{t('sections.sub_section')} *</label>
							<select id="up-sub" bind:value={uploadForm.subsection} class="form-input" onchange={handleUploadSubChange}>
								<option value="">{t('common.select')}</option>
								{#each uploadSubOptions as ss}<option value={ss.id}>{ss.name}</option>{/each}
							</select>
						</div>
					{/if}
					{#if uploadForm.subsection && uploadSecondaryOptions.length > 0}
						<div class="form-group">
							<label for="up-sec" class="form-label">{t('sections.secondary')}</label>
							<select id="up-sec" bind:value={uploadForm.secondary_subsection} class="form-input">
								<option value="">{t('common.none')}</option>
								{#each uploadSecondaryOptions as sec}<option value={sec.id}>{sec.name}</option>{/each}
							</select>
						</div>
					{/if}
					
					<div class="form-group" style="margin-top: 1.5rem; margin-bottom: 0.5rem;">
						<label class="toggle-switch">
							<input type="checkbox" id="upload-listed" bind:checked={uploadForm.is_listed} class="toggle-input" />
							<span class="toggle-slider"></span>
							<span class="toggle-label">{t('common.is_listed')}</span>
						</label>
					</div>

					<!-- Thumbnail -->
					<div class="form-group">
						<span class="form-label">{t('content.thumbnail')}</span>
						{#if uploadThumbnailPreview}
							<div class="upload-preview">
								<img src={uploadThumbnailPreview} alt="Preview" class="preview-img" />
								<button type="button" class="preview-remove" aria-label="Remove Thumbnail" onclick={() => { uploadThumbnail = null; uploadThumbnailPreview = ''; }}>
									<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M6 18L18 6M6 6l12 12" stroke-linecap="round" stroke-linejoin="round" /></svg>
								</button>
							</div>
						{:else}
							<label class="upload-zone small-zone" for="up-thumb"><span>{t('content.add_thumb')}</span></label>
							<input type="file" id="up-thumb" accept="image/*" class="file-input-hidden" onchange={handleUploadThumbChange} />
						{/if}
					</div>
					<div class="modal-actions">
						<button class="btn btn-secondary" onclick={() => (showUploadModal = false)}>{t('common.cancel')}</button>
						<button class="btn btn-primary" onclick={startUpload} disabled={isUploading}>
							<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="btn-icon"><path d="M7 16a4 4 0 01-.88-7.903A5 5 0 1115.9 6L16 6a5 5 0 011 9.9M15 13l-3-3m0 0l-3 3m3-3v12" /></svg>
							{t('content.start_upload')}
						</button>
					</div>
				</div>
			{/if}
		</div>
	</div>
{/if}

<!-- Detail Modal -->
{#if showDetailModal && detailItem}
	<!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
	<div class="modal-overlay" role="dialog" tabindex="-1" onkeydown={(e) => e.key === 'Escape' && (showDetailModal = false)} onclick={(e) => { if (e.target === e.currentTarget) showDetailModal = false; }}>
		<div class="modal animate-fade-in">
			<div class="modal-header"><h2 class="modal-title">{t('content.file_details')}</h2><button class="modal-close" aria-label="Close" onclick={() => (showDetailModal = false)}><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M6 18L18 6M6 6l12 12" stroke-linecap="round" stroke-linejoin="round" /></svg></button></div>
			<div class="detail-content">
				{#if detailItem.metadata?.thumbnail}
					<img src={detailItem.metadata.thumbnail} alt="" class="detail-thumb" />
				{/if}
				<div class="detail-fields">
					<div class="detail-row"><span class="detail-label">{t('common.title')}</span><span class="detail-value">{detailItem.metadata?.title}</span></div>
					{#if detailItem.metadata?.author}
						<div class="detail-row">
							<span class="detail-label">{t('content.author')}</span>
							<span class="detail-value">{detailItem.metadata.author}</span>
						</div>
					{/if}
					{#if detailItem.metadata?.description}<div class="detail-row"><span class="detail-label">{t('content.description')}</span><span class="detail-value">{detailItem.metadata.description}</span></div>{/if}
					<div class="detail-row"><span class="detail-label">{t('content.file')}</span><span class="detail-value">{detailItem.filename}</span></div>
					<div class="detail-row"><span class="detail-label">{t('common.type')}</span><span class="detail-value">{detailItem.file_type}</span></div>
					<div class="detail-row"><span class="detail-label">{t('content.size')}</span><span class="detail-value">{formatFileSize(detailItem.file_size)}</span></div>
					<div class="detail-row"><span class="detail-label">{t('common.is_listed')}</span><span class="detail-value" style="color: {detailItem.metadata?.is_listed !== false ? 'var(--color-primary-400)' : 'var(--color-danger-400)'};">{detailItem.metadata?.is_listed !== false ? t('common.listed') : t('common.unlisted')}</span></div>
					<div class="detail-row"><span class="detail-label">{t('content.upload')}</span><span class="detail-value">{detailItem.upload_type} — {detailItem.upload_status}</span></div>
					{#if detailItem.file_url}<div class="detail-row"><span class="detail-label">{t('content.url')}</span><span class="detail-value"><a href={detailItem.file_url} target="_blank" rel="noopener" class="link">{t('content.open_file')}</a></span></div>{/if}
					<div class="detail-row"><span class="detail-label">{t('content.created')}</span><span class="detail-value">{formatDate(detailItem.metadata?.created_at)}</span></div>
				</div>
			</div>
		</div>
	</div>
{/if}

<!-- Bulk Delete Modal -->
{#if showBulkDeleteModal}
	<!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
	<div class="modal-overlay" role="dialog" tabindex="-1" onkeydown={(e) => e.key === 'Escape' && (showBulkDeleteModal = false)} onclick={(e) => { if (e.target === e.currentTarget) showBulkDeleteModal = false; }}>
		<div class="modal modal-sm animate-fade-in">
			<div class="modal-header"><h2 class="modal-title">حذف مجمّع</h2><button class="modal-close" aria-label="Close" onclick={() => (showBulkDeleteModal = false)}><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M6 18L18 6M6 6l12 12" stroke-linecap="round" stroke-linejoin="round" /></svg></button></div>
			<p class="delete-message">سيُحذف <strong>{selectedIds.size}</strong> عنصراً نهائياً مع ملفّاتها. لا يمكن التراجع عن هذه العملية.</p>
			<div class="modal-actions pad-actions">
				<button class="btn btn-secondary" onclick={() => (showBulkDeleteModal = false)}>إلغاء</button>
				<button class="btn btn-danger" onclick={handleBulkDelete} disabled={bulkDeleting}>{bulkDeleting ? 'جارٍ الحذف…' : 'حذف الكل'}</button>
			</div>
		</div>
	</div>
{/if}

<!-- Delete Modal -->
{#if showDeleteModal && deletingItem}
	<!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
	<div class="modal-overlay" role="dialog" tabindex="-1" onkeydown={(e) => e.key === 'Escape' && (showDeleteModal = false)} onclick={(e) => { if (e.target === e.currentTarget) showDeleteModal = false; }}>
		<div class="modal modal-sm animate-fade-in">
			<div class="modal-header"><h2 class="modal-title">{t('content.delete_file')}</h2><button class="modal-close" aria-label="Close" onclick={() => (showDeleteModal = false)}><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M6 18L18 6M6 6l12 12" stroke-linecap="round" stroke-linejoin="round" /></svg></button></div>
			<p class="delete-message">{t('content.delete_confirm')} <strong>"{deletingItem.metadata?.title || deletingItem.filename}"</strong>?</p>
			<div class="modal-actions pad-actions">
				<button class="btn btn-secondary" onclick={() => (showDeleteModal = false)}>{t('common.cancel')}</button>
				<button class="btn btn-danger" onclick={handleDelete} disabled={deleteLoading}>{#if deleteLoading}<span class="spinner-sm"></span>{/if}{t('common.delete')}</button>
			</div>
		</div>
	</div>
{/if}

<!-- ═══════════════ Resume Modal ═══════════════ -->
{#if showResumeModal && resumeItem}
	<!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
	<div class="modal-overlay" role="dialog" tabindex="-1" onkeydown={(e) => e.key === 'Escape' && (!resumeStatus && (showResumeModal = false))} onclick={(e) => { if (e.target === e.currentTarget && !resumeStatus) showResumeModal = false; }}>
		<div class="modal animate-fade-in">
			<div class="modal-header">
				<h2 class="modal-title">{t('content.resume_upload')}</h2>
				{#if !resumeStatus}<button class="modal-close" aria-label="Close" onclick={() => (showResumeModal = false)}>
					<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M6 18L18 6M6 6l12 12" stroke-linecap="round" stroke-linejoin="round" /></svg>
				</button>{/if}
			</div>

			{#if resumeStatus}
				<div class="upload-progress-pane">
					<div class="progress-file-name">{resumeFile?.name || resumeItem.filename}</div>
					<div class="progress-bar-track"><div class="progress-bar-fill" style="width:{resumeProgress}%"></div></div>
					<div class="progress-info">
						<span class="progress-pct">{resumeProgress}%</span>
						<span class="progress-status">{resumeStatus === 'uploading' ? t('content.uploading') : resumeStatus === 'completing' ? t('content.finalizing') : resumeStatus === 'completed' ? t('content.complete') : t('content.failed')}</span>
					</div>
					{#if resumeError}<div class="alert alert-error" style="margin-top:0.75rem">{resumeError}</div>{/if}
					{#if resumeStatus === 'completed'}
						<button class="btn btn-primary" style="margin-top:1rem;align-self:center" onclick={() => { showResumeModal = false; if (hasSearched) fetchItems(); }}>{t('common.done')}</button>
					{:else if resumeStatus === 'failed'}
						<div class="modal-actions" style="margin-top:1rem">
							<button class="btn btn-secondary" onclick={cancelResume}>{t('common.close')}</button>
							<button class="btn btn-primary" onclick={() => { resumeStatus = ''; resumeError = ''; }}>{t('common.retry')}</button>
						</div>
					{:else}
						<button class="btn btn-secondary" style="margin-top:1rem;align-self:center" onclick={cancelResume}>{t('common.cancel')}</button>
					{/if}
				</div>
			{:else}
				<div class="modal-form">
					<div class="resume-info">
						<div class="resume-detail"><span class="resume-label">{t('content.file')}:</span> <strong>{resumeItem.filename}</strong></div>
						<div class="resume-detail"><span class="resume-label">{t('content.size')}:</span> {formatFileSize(resumeItem.file_size)}</div>
						<div class="resume-detail"><span class="resume-label">{t('common.type')}:</span> {resumeItem.upload_type}</div>
						{#if resumeItem.multipart_uploader}
							<div class="resume-detail"><span class="resume-label">{t('content.progress')}:</span> {resumeItem.multipart_uploader.uploaded_parts} / {resumeItem.multipart_uploader.total_parts} {t('content.parts_uploaded')}</div>
							<div class="progress-bar-track" style="margin-top:0.25rem"><div class="progress-bar-fill" style="width:{resumeProgress}%"></div></div>
						{/if}
					</div>

					<div class="form-group">
						<span class="form-label">{t('content.reselect_file')} *</span>
						{#if resumeFile}
							<div class="selected-file">
								<span class="selected-file-name">{resumeFile.name}</span>
								<span class="selected-file-size">{formatFileSize(resumeFile.size)}</span>
								<button type="button" class="selected-file-remove" onclick={() => { resumeFile = null; }}>×</button>
							</div>
						{:else}
							<label class="upload-zone" for="resume-file">
								<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" class="upload-icon"><path d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-8l-4-4m0 0L8 8m4-4v12" stroke-linecap="round" stroke-linejoin="round" /></svg>
								<span>{t('content.select_to_continue')}</span>
							</label>
							<input type="file" id="resume-file" class="file-input-hidden" onchange={handleResumeFileSelect} />
						{/if}
					</div>

					{#if resumeError}<div class="alert alert-error">{resumeError}</div>{/if}

					<div class="modal-actions">
						<button class="btn btn-secondary" onclick={() => (showResumeModal = false)}>{t('common.cancel')}</button>
						<button class="btn btn-primary" onclick={startResume} disabled={!resumeFile}>
							<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" class="btn-icon"><path d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-8l-4-4m0 0L8 8m4-4v12" /></svg>
							{t('content.resume')}
						</button>
					</div>
				</div>
			{/if}
		</div>
	</div>
{/if}

<!-- Edit Modal -->
{#if showEditModal && editingItem}
	<!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
	<div class="modal-overlay" role="dialog" tabindex="-1" onkeydown={(e) => e.key === 'Escape' && (showEditModal = false)} onclick={(e) => { if (e.target === e.currentTarget) showEditModal = false; }}>
		<div class="modal animate-fade-in">
			<div class="modal-header"><h2 class="modal-title">{t('content.edit_file')}</h2><button class="modal-close" aria-label="Close" onclick={() => (showEditModal = false)}><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M6 18L18 6M6 6l12 12" stroke-linecap="round" stroke-linejoin="round" /></svg></button></div>
			{#if editFormError}<div class="alert alert-error modal-alert">{editFormError}</div>{/if}
			<form onsubmit={(e) => { e.preventDefault(); handleEdit(); }} class="modal-form">
				<div class="form-group"><label for="edit-title" class="form-label">{t('common.title')}</label><input type="text" id="edit-title" bind:value={editForm.title} class="form-input" required /></div>
				<div class="form-group"><label for="edit-desc" class="form-label">{t('content.description')}</label><textarea id="edit-desc" bind:value={editForm.description} class="form-input form-textarea" rows="3"></textarea></div>
				<div class="form-group">
					<label for="edit-author" class="form-label">{t('content.author')}</label>
					<input type="text" id="edit-author" bind:value={editForm.author} class="form-input" placeholder="e.g. John Doe..." />
				</div>
				<div class="form-group">
					<label for="edit-main-section" class="form-label">{t('sections.main_section')}</label>
					<select id="edit-main-section" bind:value={editForm.main_section} class="form-select" onchange={handleEditMainChange}>
						<option value="">{t('common.none') || 'None'}</option>
						{#each mainSectionsList as section}
							<option value={section.id}>{section.name}</option>
						{/each}
					</select>
				</div>
				<div class="form-group">
					<label for="edit-sub-section" class="form-label">{t('sections.sub_section')}</label>
					<select id="edit-sub-section" bind:value={editForm.subsection} class="form-select" onchange={handleEditSubChange}>
						<option value="">{t('common.none') || 'None'}</option>
						{#each editSubOptions as section}
							<option value={section.id}>{section.name}</option>
						{/each}
					</select>
				</div>
				<div class="form-group">
					<label for="edit-secondary-section" class="form-label">{t('sections.secondary_section') || 'Secondary Section'}</label>
					<select id="edit-secondary-section" bind:value={editForm.secondary_subsection} class="form-select">
						<option value="">{t('common.none') || 'None'}</option>
						{#each editSecondaryOptions as section}
							<option value={section.id}>{section.name}</option>
						{/each}
					</select>
				</div>
				<div class="form-group">
					<span class="form-label">{t('content.file')}</span>
					{#if editFile}
						<div class="selected-file">
							<span class="selected-file-name">{editFile.name}</span>
							<span class="selected-file-size">{formatFileSize(editFile.size)}</span>
							<button type="button" class="selected-file-remove" onclick={() => { editFile = null; }}>×</button>
						</div>
					{:else}
						<label class="upload-zone" for="edit-file">
							<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" class="upload-icon"><path d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-8l-4-4m0 0L8 8m4-4v12" stroke-linecap="round" stroke-linejoin="round" /></svg>
							<span>{t('content.select_file') || 'Select replacement file'}</span>
						</label>
						<input type="file" id="edit-file" class="file-input-hidden" onchange={handleEditFileSelect} />
					{/if}
				</div>
				<div class="form-group">
					<span class="form-label">{t('content.thumbnail')}</span>
					{#if editThumbnailPreview}
						<div class="upload-preview">
							<img src={editThumbnailPreview} alt="Preview" class="preview-img" />
							<button type="button" class="preview-remove" onclick={() => { editThumbnail = null; editThumbnailPreview = ''; }} title={t('common.remove')}>
								<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M6 18L18 6M6 6l12 12" stroke-linecap="round" stroke-linejoin="round" /></svg>
							</button>
							<label class="change-thumbnail-btn" for="edit-thumb">{t('content.change_image')}</label>
							<input type="file" id="edit-thumb" accept="image/*" class="file-input-hidden" onchange={handleEditThumbnailChange} />
						</div>
					{:else}
						<label class="upload-zone" for="edit-thumb-new">
							<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" class="upload-icon"><path d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" stroke-linecap="round" stroke-linejoin="round" /></svg>
							<span>{t('content.upload_thumb')}</span>
							<span class="upload-hint">PNG, JPG, WebP</span>
						</label>
						<input type="file" id="edit-thumb-new" accept="image/*" class="file-input-hidden" onchange={handleEditThumbnailChange} />
					{/if}
				</div>
				<div class="form-group" style="margin-top: 1.5rem; margin-bottom: 0.5rem;">
					<label class="toggle-switch">
						<input type="checkbox" id="edit-listed" bind:checked={editForm.is_listed} class="toggle-input" />
						<span class="toggle-slider"></span>
						<span class="toggle-label">{t('common.is_listed')}</span>
					</label>
				</div>
				<div class="modal-actions">
					<button type="button" class="btn btn-secondary" onclick={() => (showEditModal = false)}>{t('common.cancel')}</button>
					<button type="submit" class="btn btn-primary" disabled={editFormLoading}>{#if editFormLoading}<span class="spinner-sm"></span>{/if}{t('common.save_changes')}</button>
				</div>
			</form>
		</div>
	</div>
{/if}

<style>
	.page { display: flex; flex-direction: column; gap: 1.25rem; }
	.page-header { display: flex; align-items: flex-start; justify-content: space-between; gap: 1rem; flex-wrap: wrap; }
	.page-title { font-size: 1.5rem; font-weight: 700; color: var(--color-surface-100); letter-spacing: -0.02em; }
	.page-desc { font-size: 0.8125rem; color: var(--color-surface-400); margin-top: 0.25rem; }
	.tabs { display: flex; gap: 0.25rem; border-bottom: 1px solid var(--color-surface-700); }
	.tab { padding: 0.625rem 1rem; font-size: 0.8125rem; font-weight: 500; color: var(--color-surface-400); text-decoration: none; border-bottom: 2px solid transparent; transition: all 0.15s; }
	.tab:hover { color: var(--color-surface-200); }
	.tab.active { color: var(--color-primary-400); border-bottom-color: var(--color-primary-500); }
	.toolbar { display: flex; align-items: center; gap: 0.75rem; flex-wrap: wrap; }
	:global(.hl) { background: rgba(234, 179, 8, 0.32); color: inherit; padding: 0 0.125rem; border-radius: 3px; }
	.search-clear { background: none; border: none; color: var(--color-surface-400); cursor: pointer; padding: 0; display: inline-flex; align-items: center; justify-content: center; }
	.search-clear:hover { color: var(--color-surface-100); }
	.search-clear svg { width: 14px; height: 14px; }
	.alert-warning { padding: 0.6rem 0.85rem; background: rgba(234, 179, 8, 0.12); border: 1px solid rgba(234, 179, 8, 0.35); color: #fde68a; border-radius: 8px; font-size: 0.85rem; }
	.skeleton-list { display: flex; flex-direction: column; gap: 0.5rem; }
	.skeleton-row { background: var(--color-surface-800); border: 1px solid var(--color-surface-700); border-radius: 10px; padding: 0.75rem 1rem; }
	.sk-line { height: 12px; margin-top: 0.4rem; border-radius: 6px; background: linear-gradient(90deg, var(--color-surface-700) 0%, var(--color-surface-800) 50%, var(--color-surface-700) 100%); background-size: 200% 100%; animation: sk-shimmer 1.4s infinite linear; }
	.sk-short { width: 60%; }
	@keyframes sk-shimmer { 0% { background-position: 200% 0; } 100% { background-position: -200% 0; } }
	.search-icon { width: 16px; height: 16px; color: var(--color-surface-500); flex-shrink: 0; }
	.active-query-chip { display: inline-flex; align-items: center; gap: 0.4rem; padding: 0.4rem 0.7rem; background: rgba(5,150,105,0.08); border: 1px solid var(--color-primary-700); border-radius: 999px; color: var(--color-primary-400); font-size: 0.78rem; max-width: 280px; }
	.active-query-text { font-weight: 600; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
	.filter-select { padding: 0.5rem 0.75rem; background: var(--color-surface-800); border: 1px solid var(--color-surface-700); border-radius: 10px; color: var(--color-surface-300); font-size: 0.8125rem; font-family: inherit; outline: none; cursor: pointer; }
	.filter-select option { background: var(--color-surface-800); color: var(--color-surface-100); }
	.count-badge { padding: 0.375rem 0.75rem; background: var(--color-surface-800); border: 1px solid var(--color-surface-700); border-radius: 100px; font-size: 0.75rem; color: var(--color-surface-400); font-weight: 500; margin-left: auto; }
	.alert { padding: 0.75rem 1rem; border-radius: 10px; font-size: 0.8125rem; }
	.alert-error { background: rgba(244,63,94,0.1); border: 1px solid rgba(244,63,94,0.2); color: var(--color-danger-400); }
	.content-container { min-height: 200px; }
	.state-box { display: flex; flex-direction: column; align-items: center; justify-content: center; padding: 3rem; gap: 0.75rem; color: var(--color-surface-500); font-size: 0.875rem; }
	.empty-state { padding: 4rem 2rem; }
	.empty-icon { width: 48px; height: 48px; color: var(--color-surface-600); }
	.empty-title { font-size: 1.05rem; font-weight: 600; color: var(--color-surface-800); text-align: center; max-width: 560px; margin: 0.25rem 0 0; line-height: 1.6; }
	.empty-hint { font-size: 0.9rem; color: var(--color-surface-600); text-align: center; max-width: 560px; margin: 0; line-height: 1.7; }
	.spinner { width: 24px; height: 24px; border: 3px solid var(--color-surface-700); border-top-color: var(--color-primary-500); border-radius: 50%; animation: spin 0.6s linear infinite; }

	/* File list */
	.file-list { display: flex; flex-direction: column; gap: 0.5rem; }
	.file-row { display: flex; align-items: center; gap: 1rem; padding: 0.875rem 1rem; background: var(--color-surface-800); border: 1px solid var(--color-surface-700); border-radius: 12px; cursor: pointer; transition: all 0.15s; }
	.file-row:hover { border-color: var(--color-surface-600); background: var(--color-surface-750, var(--color-surface-800)); }
	.file-icon { font-size: 1.25rem; flex-shrink: 0; }
	.file-info { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 0.15rem; }
	.file-name { font-size: 0.875rem; font-weight: 600; color: var(--color-surface-100); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
	.file-meta { font-size: 0.6875rem; color: var(--color-surface-500); }
	.file-status { font-size: 0.6875rem; font-weight: 600; padding: 0.2rem 0.5rem; border-radius: 6px; text-transform: capitalize; flex-shrink: 0; }
	.status-completed { background: rgba(5,150,105,0.15); color: var(--color-primary-400); }
	.status-pending { background: rgba(234,179,8,0.15); color: #eab308; }
	.status-failed { background: rgba(244,63,94,0.15); color: var(--color-danger-400); }
	.file-date { font-size: 0.6875rem; color: var(--color-surface-500); flex-shrink: 0; }
	.file-actions { display: flex; gap: 0.375rem; flex-shrink: 0; }
	.action-btn { width: 30px; height: 30px; display: flex; align-items: center; justify-content: center; border-radius: 8px; border: 1px solid var(--color-surface-600); background: transparent; color: var(--color-surface-400); cursor: pointer; transition: all 0.15s; }
	.action-btn svg { width: 14px; height: 14px; }
	.action-btn.delete:hover { background: rgba(244,63,94,0.1); border-color: var(--color-danger-600); color: var(--color-danger-400); }
	.action-btn.edit:hover { background: rgba(5,150,105,0.1); border-color: var(--color-primary-700); color: var(--color-primary-400); }
	.file-row-pending { border-left: 3px solid #eab308; }
	.file-row-pending:hover { border-color: #eab308; }

	/* Resume info */
	.resume-info { padding: 0.75rem 1rem; background: var(--color-surface-900); border: 1px solid var(--color-surface-600); border-radius: 10px; display: flex; flex-direction: column; gap: 0.375rem; }
	.resume-detail { font-size: 0.8125rem; color: var(--color-surface-300); }
	.resume-detail strong { color: var(--color-surface-100); }
	.resume-label { color: var(--color-surface-500); }

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

	/* Buttons */
	.btn { display: inline-flex; align-items: center; gap: 0.5rem; padding: 0.625rem 1.125rem; border-radius: 10px; font-size: 0.8125rem; font-weight: 600; font-family: inherit; cursor: pointer; border: none; transition: all 0.15s; }
	.btn-sm { padding: 0.5rem 0.875rem; font-size: 0.75rem; }
	.btn-icon { width: 16px; height: 16px; }
	.btn-primary { background: linear-gradient(135deg, var(--color-primary-700), var(--color-primary-600)); color: white; }
	.btn-primary:hover { box-shadow: 0 4px 12px rgba(5,150,105,0.25); }
	.btn-primary:disabled { opacity: 0.6; cursor: not-allowed; }
	.btn-secondary { background: var(--color-surface-700); color: var(--color-surface-300); border: 1px solid var(--color-surface-600); }
	.btn-secondary:hover { background: var(--color-surface-600); }
	.btn-danger { background: linear-gradient(135deg, var(--color-danger-600), var(--color-danger-500)); color: white; }
	.btn-danger:disabled { opacity: 0.6; cursor: not-allowed; }

	/* Modal */
	.modal-overlay { position: fixed; inset: 0; background: rgba(0,0,0,0.6); backdrop-filter: blur(4px); display: flex; align-items: center; justify-content: center; z-index: 100; padding: 1rem; }
	.modal { width: 100%; max-width: 520px; background: var(--color-surface-800); border: 1px solid var(--color-surface-700); border-radius: 16px; box-shadow: var(--shadow-elevated); max-height: 90vh; overflow-y: auto; }
	.modal-sm { max-width: 400px; }
	.modal-header { display: flex; align-items: center; justify-content: space-between; padding: 1.25rem 1.5rem; border-bottom: 1px solid var(--color-surface-700); }
	.modal-title { font-size: 1.125rem; font-weight: 700; color: var(--color-surface-100); }
	.modal-close { width: 32px; height: 32px; display: flex; align-items: center; justify-content: center; border-radius: 8px; border: none; background: transparent; color: var(--color-surface-500); cursor: pointer; }
	.modal-close:hover { background: var(--color-surface-700); color: var(--color-surface-300); }
	.modal-close svg { width: 18px; height: 18px; }
	.modal-alert { margin: 1rem 1.5rem 0; }
	.modal-form { padding: 1.25rem 1.5rem; display: flex; flex-direction: column; gap: 1rem; }
	.modal-actions { display: flex; justify-content: flex-end; gap: 0.5rem; padding-top: 0.5rem; }
	.pad-actions { padding: 0 1.5rem 1.25rem; }
	.delete-message { padding: 1.25rem 1.5rem; font-size: 0.875rem; color: var(--color-surface-300); line-height: 1.5; }
	.delete-message strong { color: var(--color-surface-100); }
	.form-group { display: flex; flex-direction: column; gap: 0.375rem; }
	.form-label { font-size: 0.8125rem; font-weight: 500; color: var(--color-surface-300); }
	.form-input { padding: 0.625rem 0.75rem; background: var(--color-surface-900); border: 1px solid var(--color-surface-600); border-radius: 8px; color: var(--color-surface-100); font-size: 0.8125rem; font-family: inherit; outline: none; }
	.form-input:focus { border-color: var(--color-primary-600); }
	.form-textarea { resize: vertical; min-height: 50px; }

	/* Upload zone */
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

	/* Selected file chip */
	.selected-file { display: flex; align-items: center; gap: 0.5rem; padding: 0.75rem 1rem; background: var(--color-surface-900); border: 1px solid var(--color-primary-700); border-radius: 10px; }
	.selected-file-name { flex: 1; font-size: 0.8125rem; color: var(--color-surface-100); font-weight: 500; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
	.selected-file-size { font-size: 0.6875rem; color: var(--color-surface-400); flex-shrink: 0; }
	.selected-file-remove { background: none; border: none; color: var(--color-surface-400); cursor: pointer; font-size: 1.25rem; padding: 0 0.25rem; }
	.selected-file-remove:hover { color: var(--color-danger-400); }

	/* Progress pane */
	.upload-progress-pane { padding: 2rem 1.5rem; display: flex; flex-direction: column; align-items: stretch; gap: 0.75rem; }
	.progress-file-name { font-size: 0.8125rem; font-weight: 600; color: var(--color-surface-100); text-align: center; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
	.progress-bar-track { width: 100%; height: 8px; background: var(--color-surface-700); border-radius: 100px; overflow: hidden; }
	.progress-bar-fill { height: 100%; background: linear-gradient(90deg, var(--color-primary-600), var(--color-primary-400)); border-radius: 100px; transition: width 0.3s ease; }
	.progress-info { display: flex; justify-content: space-between; }
	.progress-pct { font-size: 0.875rem; font-weight: 700; color: var(--color-primary-400); }
	.progress-status { font-size: 0.8125rem; color: var(--color-surface-400); }

	/* Detail */
	.detail-content { padding: 1.5rem; }
	.detail-thumb { width: 100%; max-height: 180px; object-fit: cover; border-radius: 10px; margin-bottom: 1rem; }
	.detail-fields { display: flex; flex-direction: column; gap: 0.75rem; }
	.detail-row { display: flex; align-items: flex-start; justify-content: space-between; padding: 0.5rem 0; border-bottom: 1px solid var(--color-surface-700); gap: 1rem; }
	.detail-row:last-child { border-bottom: none; }
	.detail-label { font-size: 0.8125rem; color: var(--color-surface-400); font-weight: 500; flex-shrink: 0; }
	.detail-value { font-size: 0.8125rem; color: var(--color-surface-100); font-weight: 600; text-align: right; }
	.link { color: var(--color-primary-400); text-decoration: none; }
	.link:hover { text-decoration: underline; }

	.spinner-sm { width: 14px; height: 14px; border: 2px solid rgba(255,255,255,0.3); border-top-color: white; border-radius: 50%; animation: spin 0.6s linear infinite; }
	@keyframes spin { to { transform: rotate(360deg); } }
	:global(.animate-fade-in) { animation: fadeIn 0.15s ease-out; }
	@keyframes fadeIn { from { opacity: 0; transform: translateY(8px); } to { opacity: 1; transform: translateY(0); } }

	@media (max-width: 640px) {
		.toolbar { flex-direction: column; align-items: stretch; }
		.filter-select, .active-query-chip { max-width: 100%; width: 100%; }
		.count-badge { margin-left: 0; align-self: flex-start; }
		
		.file-row { flex-wrap: wrap; gap: 0.5rem; }
		.file-info { min-width: 100%; order: -1; }
		.file-name { white-space: normal; word-break: break-all; }
		.file-actions { margin-left: auto; justify-content: flex-end; width: 100%; }

		.detail-row { flex-direction: column; gap: 0.25rem; }
		.detail-value { text-align: left; word-break: break-all; }
	}
</style>
