/**
 * File Upload Orchestrator (Firebase-only)
 *
 * مرحلتان: Storage (متوازٍ) ثم Firestore (متسلسل عبر commit queue في المتجر).
 */
import {
	firebaseUploadFileToStorage,
	firebaseWriteFileRecord,
	firebaseUploadContentFile,
	uploadContentThumbnail,
	firebaseDeleteStoragePath
} from '$lib/firebase/storageUpload.js';
import imageCompression from 'browser-image-compression';

const RETRY_DELAYS_MS = [1000, 2000, 4000];
const MAX_UPLOAD_ATTEMPTS = 3;

function sleep(ms) {
	return new Promise((r) => setTimeout(r, ms));
}

/**
 * @template T
 * @param {() => Promise<T>} fn
 * @param {{ maxAttempts?: number, onRetry?: (attempt: number, err: Error) => void }} [opts]
 */
export async function withUploadRetries(fn, { maxAttempts = MAX_UPLOAD_ATTEMPTS, onRetry } = {}) {
	let lastErr;
	for (let attempt = 1; attempt <= maxAttempts; attempt++) {
		try {
			return await fn();
		} catch (err) {
			lastErr = err;
			if (attempt >= maxAttempts) break;
			if (String(err?.message || '').includes('aborted')) break;
			onRetry?.(attempt, err);
			await sleep(RETRY_DELAYS_MS[attempt - 1] ?? 4000);
		}
	}
	throw lastErr;
}

/**
 * المرحلة 1: رفع الملف والمصغّرة إلى Storage فقط.
 * @param {File} file
 * @param {Record<string, unknown>} metadata
 * @param {File|null} thumbnail
 * @param {{ onProgress?: (n: number) => void, isAborted?: () => boolean, onTaskCreated?: (task: import('firebase/storage').UploadTask) => void, fileId?: string }} opts
 */
export async function uploadStoragePhase(file, metadata, thumbnail, opts = {}) {
	const { onProgress, isAborted = () => false, onTaskCreated, fileId: presetFileId } = opts;
	const fileId = presetFileId || newStableFileId();
	if (isAborted()) throw new Error('Upload aborted');

	const thumbPromise = thumbnail
		? uploadContentThumbnail(fileId, thumbnail).catch((thumbErr) => {
				console.warn('[fileUpload] Thumbnail upload failed, continuing without it:', thumbErr);
				return null;
			})
		: Promise.resolve(null);

	const storagePromise = firebaseUploadFileToStorage(file, fileId, {
		onProgress: (pct) => onProgress?.(pct),
		isAborted,
		onTaskCreated
	});

	const [thumbnailUrl, storageRes] = await Promise.all([thumbPromise, storagePromise]);
	if (isAborted()) throw new Error('Upload aborted');

	const finalMetadata = thumbnailUrl ? { ...metadata, thumbnail: thumbnailUrl } : metadata;

	return {
		fileId,
		file,
		downloadUrl: storageRes.downloadUrl,
		storagePath: storageRes.storagePath,
		metadata: finalMetadata
	};
}

/**
 * المرحلة 2: كتابة السجل في Firestore (مع استرداد Storage عند الفشل).
 * @param {{ fileId: string, file: File, downloadUrl: string, storagePath: string, metadata: Record<string, unknown> }} storageResult
 */
export async function commitFirestorePhase(storageResult) {
	try {
		await firebaseWriteFileRecord({
			fileId: storageResult.fileId,
			file: storageResult.file,
			downloadUrl: storageResult.downloadUrl,
			storagePath: storageResult.storagePath,
			metadata: storageResult.metadata
		});
		// نُعيد رابط المصدر والصورة المصغّرة أيضاً (إضافة غير كاسرة) كي يستطيع
		// المتصل تمريرهما في إشعار FCM، فيفتح التطبيق المحتوى نفسه مباشرةً من
		// حمولة الإشعار دون انتظار جلب من الشبكة (أهمّ على الإنترنت الضعيف).
		return {
			id: storageResult.fileId,
			provider: 'firebase',
			downloadUrl: storageResult.downloadUrl,
			thumbnail:
				(storageResult.metadata && storageResult.metadata.thumbnail) || ''
		};
	} catch (err) {
		await firebaseDeleteStoragePath(storageResult.storagePath);
		throw err;
	}
}

/**
 * @param {File} file
 * @param {Object} metadata
 * @param {File|null} thumbnail
 * @param {Object} callbacks
 * @param {{ fileId?: string, deferFirestore?: boolean }} [options]
 */
export function createFileUploader(
	file,
	metadata,
	thumbnail,
	{ onProgress, onStatus, onError } = {},
	options = {}
) {
	let aborted = false;
	/** @type {import('firebase/storage').UploadTask | null} */
	let firebaseUploadTask = null;
	const presetFileId = options.fileId;

	function setStatus(s) {
		onStatus?.(s);
	}
	function setProgress(p) {
		onProgress?.(Math.round(p));
	}

	function uploadStorage() {
		return uploadStoragePhase(file, metadata, thumbnail, {
			onProgress: setProgress,
			isAborted: () => aborted,
			onTaskCreated: (task) => {
				firebaseUploadTask = task;
			},
			fileId: presetFileId
		});
	}

	function commitFirestore(storageResult) {
		return commitFirestorePhase(storageResult);
	}

	async function start() {
		try {
			setStatus('initiating');
			setProgress(0);
			setStatus('uploading');
			const storageResult = await uploadStorage();
			if (options.deferFirestore) return storageResult;
			const result = await commitFirestore(storageResult);
			if (aborted) throw new Error('Upload aborted');
			setProgress(100);
			setStatus('completed');
			return result;
		} catch (err) {
			if (!aborted) {
				setStatus('failed');
				onError?.(err.message || 'Upload failed');
			}
			throw err;
		} finally {
			firebaseUploadTask = null;
		}
	}

	function abort() {
		aborted = true;
		try {
			firebaseUploadTask?.cancel();
		} catch {
			/* ignore */
		}
		firebaseUploadTask = null;
	}

	function pause() {
		try {
			firebaseUploadTask?.pause();
		} catch {
			/* ignore */
		}
	}

	function resume() {
		try {
			firebaseUploadTask?.resume();
		} catch {
			/* ignore */
		}
	}

	return { start, uploadStorage, commitFirestore, abort, pause, resume };
}

/**
 * Resume an interrupted upload for a pending file.
 */
export function createResumeUploader(fileRecord, file, { onProgress, onStatus, onError } = {}) {
	let aborted = false;
	/** @type {import('firebase/storage').UploadTask | null} */
	let firebaseUploadTask = null;

	function setStatus(s) {
		onStatus?.(s);
	}
	function setProgress(p) {
		onProgress?.(Math.round(p));
	}

	async function start() {
		try {
			setStatus('uploading');
			const fileId = fileRecord?.id || `fb_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
			await firebaseUploadContentFile(file, fileId, fileRecord?.metadata || {}, {
				onProgress: (pct) => setProgress(pct),
				isAborted: () => aborted,
				onTaskCreated: (task) => {
					firebaseUploadTask = task;
				}
			});
			if (aborted) throw new Error('Upload aborted');
			setProgress(100);
			setStatus('completed');
			return { id: fileId, provider: 'firebase' };
		} catch (err) {
			if (!aborted) {
				setStatus('failed');
				onError?.(err.message || 'Resume failed');
			}
			throw err;
		} finally {
			firebaseUploadTask = null;
		}
	}

	function abort() {
		aborted = true;
		try {
			firebaseUploadTask?.cancel();
		} catch {
			/* ignore */
		}
		firebaseUploadTask = null;
	}

	function pause() {
		try {
			firebaseUploadTask?.pause();
		} catch {
			/* ignore */
		}
	}

	function resume() {
		try {
			firebaseUploadTask?.resume();
		} catch {
			/* ignore */
		}
	}

	return { start, abort, pause, resume };
}

export function formatFileSize(bytes) {
	if (!bytes) return '0 B';
	const units = ['B', 'KB', 'MB', 'GB'];
	let i = 0;
	let size = bytes;
	while (size >= 1024 && i < units.length - 1) {
		size /= 1024;
		i++;
	}
	return `${size.toFixed(i > 0 ? 1 : 0)} ${units[i]}`;
}

export function mimeToContentType(mime) {
	if (!mime) return 'document';
	if (mime.startsWith('video/')) return 'video';
	if (mime.startsWith('audio/')) return 'audio';
	return 'document';
}

/** حدود حجم الملف للرفع المتعدد */
export const MULTI_UPLOAD_MAX_BYTES = 500 * 1024 * 1024;
export const MULTI_UPLOAD_WARN_BYTES = 200 * 1024 * 1024;

/** امتدادات مدعومة للرفع المتعدد (رفض الباقي قبل الإضافة للطابور). */
const ALLOWED_EXTENSIONS = new Set([
	'.pdf',
	'.epub',
	'.doc',
	'.docx',
	'.txt',
	'.rtf',
	'.mp3',
	'.m4a',
	'.wav',
	'.ogg',
	'.aac',
	'.flac',
	'.mp4',
	'.webm',
	'.mov',
	'.mkv',
	'.avi',
	'.jpg',
	'.jpeg',
	'.png',
	'.gif',
	'.webp',
	'.bmp',
	'.svg'
]);

export function newStableFileId() {
	return `fb_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
}

/**
 * @param {File} file
 * @returns {{ ok: boolean, error?: string, warn?: string }}
 */
export function validateMultiUploadFile(file) {
	const sizeCheck = validateMultiUploadFileSize(file);
	if (!sizeCheck.ok) return sizeCheck;

	const name = String(file?.name || '').toLowerCase();
	const dot = name.lastIndexOf('.');
	const ext = dot >= 0 ? name.slice(dot) : '';
	if (!ext || !ALLOWED_EXTENSIONS.has(ext)) {
		return {
			ok: false,
			error: `Unsupported file type${ext ? `: ${ext}` : ''}`
		};
	}
	return sizeCheck;
}

/**
 * @param {File} file
 * @returns {{ ok: boolean, error?: string, warn?: string }}
 */
export function validateMultiUploadFileSize(file) {
	if (!file?.size) return { ok: true };
	if (file.size > MULTI_UPLOAD_MAX_BYTES) {
		return {
			ok: false,
			error: `File exceeds 500 MB limit (${formatFileSize(file.size)})`
		};
	}
	if (file.size > MULTI_UPLOAD_WARN_BYTES) {
		return {
			ok: true,
			warn: `Large file (${formatFileSize(file.size)}) — upload may take a while`
		};
	}
	return { ok: true };
}

/**
 * يضغط الصورة إذا كانت أكبر من الحجم المسموح به.
 * @param {File} file
 * @param {number} [maxSizeMB]
 * @param {number} [maxWidthOrHeight]
 * @returns {Promise<File>}
 */
export async function compressImageFile(file, maxSizeMB = 2, maxWidthOrHeight = 1920) {
	if (!file || !file.type.startsWith('image/')) return file;
	if (file.type === 'image/gif' || file.type === 'image/svg+xml') return file;
	if (file.size <= maxSizeMB * 1024 * 1024) return file;

	try {
		const options = {
			maxSizeMB,
			maxWidthOrHeight,
			useWebWorker: true,
			initialQuality: 0.85
		};
		const compressedBlob = await imageCompression(file, options);
		return new File([compressedBlob], file.name, {
			type: compressedBlob.type,
			lastModified: Date.now()
		});
	} catch (err) {
		console.warn('[fileUpload] Image compression failed:', err);
		return file;
	}
}
