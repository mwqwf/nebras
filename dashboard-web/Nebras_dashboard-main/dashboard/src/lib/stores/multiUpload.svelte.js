/**
 * Multi-Upload Store — Svelte 5 Reactive Store
 *
 * مرحلتان:
 *   1) رفع Storage متوازٍ (3–5 ملفات) — سرعة قصوى
 *   2) كتابة Firestore متسلسلة عبر commitQueue — ترتيب الاختيار مضمون 100%
 */

import {
	createFileUploader,
	mimeToContentType,
	withUploadRetries,
	compressImageFile,
	validateMultiUploadFile,
	newStableFileId
} from '$lib/utils/fileUpload.js';
import { computeFileSha256 } from '$lib/utils/fileHash.js';
import { notifyContentAdded } from '$lib/utils/notifyEvents.js';
import { createCommitQueue } from '$lib/stores/multiUploadCommitQueue.js';

/** @typedef {'queued'|'uploading'|'committing'|'completed'|'failed'} QueueStatus */

/**
 * @typedef {Object} QueueItem
 * @property {string} id
 * @property {number} selectionIndex
 * @property {File} file
 * @property {File|null} thumbnail
 * @property {string} thumbnailPreview
 * @property {{ title:string, description:string, author:string, main_section:(string|number), subsection:(string|number), secondary_subsection:(string|number), is_listed:boolean }} form
 * @property {{ main:string, sub:string, secondary:string }} labels
 * @property {QueueStatus} status
 * @property {number} progress
 * @property {string} error
 * @property {number} [retryCount]
 * @property {string|null} [fileId]
 */

const STORAGE_KEY = 'nebras_multi_upload_v2';

/** @type {Map<string, { start: ()=>Promise<any>, abort: ()=>void, pause?: ()=>void, resume?: ()=>void, uploadStorage?: ()=>Promise<any>, commitFirestore?: (r:any)=>Promise<any> }>} */
const uploaderRegistry = new Map();

/** @type {import('$lib/stores/multiUploadCommitQueue.js').createCommitQueue extends (...a: any)=>infer R ? R : never | null} */
let commitQueue = null;

let selectionCounter = 0;
let networkCalibrated = false;

/** تقدّم الرفع خارج كائنات الطابور لتقليل إعادة التصيير ($state.raw). */
let uploadProgressRaw = $state.raw({});
let uploadProgressTick = $state(0);

export const DEFAULT_CONCURRENCY = 3;

export function getItemProgress(id) {
	void uploadProgressTick;
	const raw = uploadProgressRaw[id];
	if (raw != null) return raw;
	return multiState.queue.find((q) => q.id === id)?.progress ?? 0;
}

function setItemProgress(id, progress) {
	uploadProgressRaw[id] = progress;
	uploadProgressTick++;
	const idx = multiState.queue.findIndex((it) => it.id === id);
	if (idx !== -1) multiState.queue[idx].progress = progress;
}

function calibrateConcurrencyFromSample(bytes, durationMs) {
	if (networkCalibrated || !bytes || durationMs < 400) return;
	networkCalibrated = true;
	const bps = bytes / (durationMs / 1000);
	if (bps < 250_000) setConcurrency(1);
	else if (bps < 800_000) setConcurrency(2);
	else if (bps < 2_500_000) setConcurrency(3);
	else setConcurrency(5);
}

let multiState = $state({
	queue: [],
	isUploading: false,
	isPaused: false,
	currentId: null,
	lastError: '',
	allDoneAt: 0,
	batchId: null,
	concurrency: DEFAULT_CONCURRENCY,
	lastSections: { main_section: '', subsection: '', secondary_subsection: '' }
});

export function getMultiUploadState() {
	return multiState;
}

export function setConcurrency(n) {
	const v = Math.max(1, Math.min(5, Number(n) || DEFAULT_CONCURRENCY));
	multiState.concurrency = v;
}

export function setLastSections({ main_section = '', subsection = '', secondary_subsection = '' } = {}) {
	multiState.lastSections = {
		main_section: String(main_section ?? ''),
		subsection: String(subsection ?? ''),
		secondary_subsection: String(secondary_subsection ?? '')
	};
}

export function clearLastSections() {
	multiState.lastSections = { main_section: '', subsection: '', secondary_subsection: '' };
}

function newId() {
	return `q_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
}

function newBatchId() {
	if (typeof crypto !== 'undefined' && crypto.randomUUID) return crypto.randomUUID();
	return `batch_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
}

/** إعادة ترقيم selectionIndex وفق ترتيب الطابور (قبل البدء فقط). */
function reindexFileQueue() {
	for (let i = 0; i < multiState.queue.length; i++) {
		const it = multiState.queue[i];
		if (it.status === 'queued' || it.status === 'failed') {
			it.selectionIndex = i;
		}
	}
	selectionCounter = multiState.queue.length;
}

function persistQueueSnapshot() {
	if (typeof localStorage === 'undefined') return;
	try {
		const payload = {
			batchId: multiState.batchId,
			queue: multiState.queue.map((it) => ({
				id: it.id,
				selectionIndex: it.selectionIndex,
				status: it.status,
				progress: it.progress,
				error: it.error,
				form: it.form,
				labels: it.labels,
				fileMeta: it.file
					? { name: it.file.name, size: it.file.size, type: it.file.type }
					: null,
				thumbnailPreview: it.thumbnailPreview || ''
			}))
		};
		localStorage.setItem(STORAGE_KEY, JSON.stringify(payload));
	} catch {
		/* ignore quota */
	}
}

export function restoreQueueFromStorage() {
	if (typeof localStorage === 'undefined') return false;
	try {
		const raw = localStorage.getItem(STORAGE_KEY);
		if (!raw) return false;
		const data = JSON.parse(raw);
		if (!data?.queue?.length) return false;
		multiState.lastError =
			'تم استعادة بيانات الطابور من الجلسة السابقة — أعد إرفاق الملفات قبل المتابعة.';
		multiState.batchId = data.batchId || null;
		return true;
	} catch {
		return false;
	}
}

export function clearPersistedQueue() {
	try {
		localStorage.removeItem(STORAGE_KEY);
	} catch {
		/* ignore */
	}
}

export function addItem({ file, thumbnail = null, thumbnailPreview = '', form, labels }) {
	const check = validateMultiUploadFile(file);
	if (!check.ok) {
		multiState.lastError = check.error || 'Invalid file';
		return null;
	}
	if (check.warn) multiState.lastError = '';

	const id = newId();
	const selectionIndex = selectionCounter++;
	multiState.queue.push({
		id,
		selectionIndex,
		file,
		thumbnail,
		thumbnailPreview,
		form: { ...form },
		labels: { ...labels },
		status: 'queued',
		progress: 0,
		error: '',
		retryCount: 0,
		fileId: null
	});
	uploadProgressRaw[id] = 0;
	persistQueueSnapshot();
	return id;
}

export function updateItem(id, patch) {
	const idx = multiState.queue.findIndex((it) => it.id === id);
	if (idx === -1) return;
	Object.assign(multiState.queue[idx], patch);
	persistQueueSnapshot();
}

export function replaceItemFields(id, fields) {
	updateItem(id, fields);
}

export function removeItem(id) {
	const up = uploaderRegistry.get(id);
	if (up) {
		try {
			up.abort();
		} catch {
			/* ignore */
		}
		uploaderRegistry.delete(id);
	}
	multiState.queue = multiState.queue.filter((it) => it.id !== id);
	reindexFileQueue();
	if (multiState.currentId === id) multiState.currentId = null;
	persistQueueSnapshot();
}

export function moveItem(id, direction) {
	const idx = multiState.queue.findIndex((it) => it.id === id);
	if (idx === -1) return;
	const target = idx + direction;
	if (target < 0 || target >= multiState.queue.length) return;
	if (
		multiState.queue[idx].status === 'uploading' ||
		multiState.queue[idx].status === 'committing' ||
		multiState.queue[target].status === 'uploading' ||
		multiState.queue[target].status === 'committing'
	) {
		return;
	}
	const a = multiState.queue[idx];
	multiState.queue[idx] = multiState.queue[target];
	multiState.queue[target] = a;
	reindexFileQueue();
	persistQueueSnapshot();
}

/** إعادة ترتيب الطابور بالسحب والإفلات (قبل بدء الرفع). */
export function reorderItem(fromIndex, toIndex) {
	if (fromIndex === toIndex) return;
	const q = multiState.queue;
	if (fromIndex < 0 || toIndex < 0 || fromIndex >= q.length || toIndex >= q.length) return;
	const item = q[fromIndex];
	if (item.status === 'uploading' || item.status === 'committing') return;
	const target = q[toIndex];
	if (target?.status === 'uploading' || target?.status === 'committing') return;
	q.splice(fromIndex, 1);
	q.splice(toIndex, 0, item);
	reindexFileQueue();
	persistQueueSnapshot();
}

export function clearCompleted() {
	multiState.queue = multiState.queue.filter((it) => it.status !== 'completed');
	reindexFileQueue();
	persistQueueSnapshot();
}

export function resetQueue() {
	stopAll({ markUploadingAsFailed: false });
	multiState.queue = [];
	multiState.lastError = '';
	multiState.allDoneAt = 0;
	multiState.batchId = null;
	selectionCounter = 0;
	commitQueue = null;
	clearLastSections();
	clearPersistedQueue();
}

// ─── Upload control ──────────────────────────────────────────

export async function startAll({ concurrency } = {}) {
	if (multiState.isUploading) return;
	multiState.isUploading = true;
	multiState.isPaused = false;
	multiState.lastError = '';
	multiState.allDoneAt = 0;
	multiState.batchId = newBatchId();
	clearLastSections();
	networkCalibrated = false;
	for (const k of Object.keys(uploadProgressRaw)) delete uploadProgressRaw[k];
	uploadProgressTick++;

	commitQueue = createCommitQueue(0);

	const limit = Math.max(
		1,
		Math.min(5, Number(concurrency) || multiState.concurrency || DEFAULT_CONCURRENCY)
	);

	const active = new Set();

	function pickNext() {
		return multiState.queue.find((it) => it.status === 'queued' || it.status === 'failed');
	}

	try {
		while (multiState.isUploading) {
			if (!multiState.isPaused) {
				while (multiState.isUploading && active.size < limit) {
					const next = pickNext();
					if (!next) break;
					updateItem(next.id, { status: 'uploading', progress: 0, error: '' });
					if (!multiState.currentId) multiState.currentId = next.id;
					const p = uploadOne(next.id).finally(() => active.delete(p));
					active.add(p);
				}
			}
			if (active.size === 0) {
				const hasPending = multiState.queue.some(
					(it) => it.status === 'queued' || it.status === 'failed'
				);
				if (!hasPending) break;
				if (multiState.isPaused) {
					await sleep(300);
					continue;
				}
				break;
			}
			await Promise.race(active);
		}
		if (active.size > 0) await Promise.allSettled(active);
		if (commitQueue) await commitQueue.flush();
	} finally {
		multiState.isUploading = false;
		multiState.currentId = null;
		commitQueue = null;

		const anythingLeft = multiState.queue.length > 0;
		const everyDone =
			anythingLeft && multiState.queue.every((it) => it.status === 'completed');
		if (everyDone) {
			multiState.allDoneAt = Date.now();
			notifyBatchCompleteIfAllowed();
		}
		persistQueueSnapshot();
	}
}

function sleep(ms) {
	return new Promise((r) => setTimeout(r, ms));
}

function notifyBatchCompleteIfAllowed() {
	if (typeof Notification === 'undefined' || Notification.permission !== 'granted') return;
	try {
		new Notification('Nebras — Multi Upload', {
			body: 'All files in the batch finished uploading.',
			icon: '/favicon.png'
		});
	} catch {
		/* ignore */
	}
}

export function requestUploadNotificationPermission() {
	if (typeof Notification === 'undefined') return;
	if (Notification.permission === 'default') {
		Notification.requestPermission().catch(() => {});
	}
}

export function stopAll({ markUploadingAsFailed = false } = {}) {
	multiState.isUploading = false;
	multiState.isPaused = false;
	for (const [id, up] of uploaderRegistry.entries()) {
		try {
			up.abort();
		} catch {
			/* ignore */
		}
		uploaderRegistry.delete(id);
	}
	for (let i = 0; i < multiState.queue.length; i++) {
		const it = multiState.queue[i];
		if (it.status !== 'uploading' && it.status !== 'committing') continue;
		if (markUploadingAsFailed) {
			Object.assign(it, { status: 'failed', progress: 0, error: 'Upload stopped' });
		} else {
			Object.assign(it, { status: 'queued', progress: 0, error: '' });
		}
	}
	multiState.currentId = null;
	persistQueueSnapshot();
}

export function pauseAll() {
	multiState.isPaused = true;
	for (const up of uploaderRegistry.values()) {
		try {
			up.pause?.();
		} catch {
			/* ignore */
		}
	}
}

export function resumeAll() {
	multiState.isPaused = false;
	for (const up of uploaderRegistry.values()) {
		try {
			up.resume?.();
		} catch {
			/* ignore */
		}
	}
}

async function uploadOne(itemId) {
	const startSnapshot = multiState.queue.find((it) => it.id === itemId);
	if (!startSnapshot || !commitQueue) return;

	const batchId = multiState.batchId;
	const selectionIndex = startSnapshot.selectionIndex;
	const contentType = mimeToContentType(startSnapshot.file.type);
	const metadata = {
		title: startSnapshot.form.title,
		description: startSnapshot.form.description || undefined,
		author: startSnapshot.form.author || undefined,
		subsection: String(startSnapshot.form.subsection),
		content_type: contentType,
		is_listed: startSnapshot.form.is_listed,
		selectionOrder: selectionIndex,
		selectionIndex,
		batchId
	};
	if (startSnapshot.form.secondary_subsection) {
		metadata.secondary_subsection = String(startSnapshot.form.secondary_subsection);
	}

	let lastReported = -1;
	let lastReportedAt = 0;
	const onProgressThrottled = (p) => {
		const rounded = Math.min(89, Math.round(p * 0.89));
		const now = Date.now();
		if (rounded < 89 && rounded === lastReported && now - lastReportedAt < 100) return;
		if (rounded < 89 && now - lastReportedAt < 80) return;
		lastReported = rounded;
		lastReportedAt = now;
		setItemProgress(itemId, rounded);
	};

	const stableFileId = startSnapshot.fileId || newStableFileId();
	if (!startSnapshot.fileId) {
		updateItem(itemId, { fileId: stableFileId });
	}

	let finalFile = startSnapshot.file;
	let finalThumb = startSnapshot.thumbnail;
	try {
		finalFile = await compressImageFile(finalFile);
		if (finalThumb) finalThumb = await compressImageFile(finalThumb, 1, 1024);
	} catch (err) {
		console.warn('Compression step failed, using original files', err);
	}

	try {
		const sha = await computeFileSha256(finalFile);
		if (sha) metadata.content_sha256 = sha;
	} catch {
		/* optional */
	}

	const uploader = createFileUploader(finalFile, metadata, finalThumb, {
		onProgress: onProgressThrottled,
		onStatus: () => {},
		onError: (msg) => updateItem(itemId, { error: msg })
	}, { fileId: stableFileId });

	uploaderRegistry.set(itemId, uploader);

	try {
		const storageT0 = performance.now();
		const storageResult = await withUploadRetries(() => uploader.uploadStorage(), {
			onRetry: (attempt) => {
				updateItem(itemId, {
					error: `Retry ${attempt}/3 (storage)…`,
					retryCount: attempt
				});
			}
		});
		calibrateConcurrencyFromSample(finalFile.size, performance.now() - storageT0);

		if (!multiState.queue.some((it) => it.id === itemId)) return;

		updateItem(itemId, { status: 'committing', progress: 92, error: '' });

		await commitQueue.enqueue(selectionIndex, async () => {
			if (!multiState.queue.some((it) => it.id === itemId)) return;
			await withUploadRetries(() => uploader.commitFirestore(storageResult), {
				onRetry: (attempt) => {
					updateItem(itemId, {
						error: `Retry ${attempt}/3 (database)…`,
						retryCount: attempt
					});
				}
			});
		});

		const stillThere = multiState.queue.some((it) => it.id === itemId);
		if (stillThere) {
			updateItem(itemId, { status: 'completed', progress: 100, error: '' });
			notifyContentAdded({
				title: startSnapshot.form.title,
				contentType,
				contentId: storageResult.fileId,
				// رابط المصدر والصورة المصغّرة من نتيجة رفع Storage — يفتح بهما
				// التطبيق المحتوى مباشرةً من حمولة الإشعار دون جلب من الشبكة.
				sourceUrl: storageResult.downloadUrl,
				thumbnail:
					(storageResult.metadata && storageResult.metadata.thumbnail) || '',
				mainSectionId: startSnapshot.form?.main_section,
				subSectionId: startSnapshot.form?.subsection,
				secondarySectionId: startSnapshot.form?.secondary_subsection,
				mainSectionName: startSnapshot.labels?.main || '',
				subSectionName: startSnapshot.labels?.sub || '',
				secondarySectionName: startSnapshot.labels?.secondary || ''
			});
		}
	} catch (err) {
		if (multiState.queue.some((it) => it.id === itemId)) {
			const msg = err?.message || 'Upload failed';
			updateItem(itemId, { status: 'failed', error: msg });
		}
	} finally {
		uploaderRegistry.delete(itemId);
	}
}
