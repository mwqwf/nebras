/**
 * smartUpload.js — رفع الملفّات إلى دلو Nebras عبر Web SDK.
 *
 * يعيد:
 *   { url, path, bucket?, contentType, size, filename, target }
 */

import {
	ref as storageRef,
	uploadBytes,
	uploadBytesResumable,
	getDownloadURL
} from 'firebase/storage';
import { getFirebaseStorage } from '$lib/firebase/client.js';

/** @typedef {'nebras'} UploadTarget */

/**
 * @typedef {Object} SmartUploadResult
 * @property {string} url          رابط التنزيل المباشر (قابل للحفظ في الـ DB).
 * @property {string} path         المسار الداخلي داخل الدلو.
 * @property {string|null} [bucket] اسم الدلو
 * @property {string} contentType
 * @property {number} size
 * @property {string} filename
 * @property {UploadTarget} target
 */

function sanitizeSegment(name) {
	return String(name || 'file')
		.trim()
		.replace(/[\u0000-\u001F\u007F]/g, '')
		.replace(/[#$\[\]./\\:*?"<>|]+/g, '_')
		.slice(0, 180) || 'file';
}

function inferContentType(file) {
	return String(file?.type || '').trim() || 'application/octet-stream';
}

/**
 * @param {Object} opts
 * @param {File}   opts.file
 * @param {UploadTarget} [opts.target] — يُتجاهل؛ يبقى Nebras فقط.
 * @param {string} [opts.folder]
 * @param {string} [opts.filename]
 * @param {(pct:number)=>void} [opts.onProgress]
 * @param {()=>boolean} [opts.isAborted]
 * @param {(task:any)=>void} [opts.onTaskCreated]
 * @returns {Promise<SmartUploadResult>}
 */
export async function smartUpload(opts) {
	const { file, target = 'nebras' } = opts;
	if (!file || typeof file !== 'object' || !('size' in file)) {
		throw makeError('لم يُقدَّم ملف صالح للرفع.', 'invalid_file');
	}
	if (target !== 'nebras') {
		throw makeError('هدف الرفع غير مدعوم — استخدم مشروع Nebras فقط.', 'unknown_target');
	}
	return uploadToNebras(opts);
}

/**
 * @param {File} file
 * @param {string} path المسار داخل دلو Nebras
 */
export async function uploadSmallToNebras(file, path) {
	const storage = getFirebaseStorage();
	if (!storage) {
		throw makeError('Firebase غير مهيّأ. تحقّق من متغيّرات VITE_FIREBASE_* في .env.', 'nebras_not_configured');
	}
	const ref = storageRef(storage, path);
	await uploadBytes(ref, file, { contentType: inferContentType(file) });
	return getDownloadURL(ref);
}

async function uploadToNebras(opts) {
	const { file, folder = 'dashboard/uploads', filename, onProgress, isAborted, onTaskCreated } = opts;
	const storage = getFirebaseStorage();
	if (!storage) {
		throw makeError(
			'Firebase غير مهيّأ. تحقّق من متغيّرات VITE_FIREBASE_* في .env.',
			'nebras_not_configured'
		);
	}

	const safeName = sanitizeSegment(filename || file.name || 'file');
	const path = `${folder.replace(/^\/+|\/+$/g, '')}/${Date.now()}_${safeName}`;
	const ref = storageRef(storage, path);
	const contentType = inferContentType(file);

	const needsResumable = typeof onProgress === 'function' || typeof isAborted === 'function';

	if (!needsResumable) {
		await uploadBytes(ref, file, { contentType });
		const url = await getDownloadURL(ref);
		return {
			url,
			path,
			bucket: null,
			contentType,
			size: file.size,
			filename: safeName,
			target: /** @type {UploadTarget} */ ('nebras')
		};
	}

	const task = uploadBytesResumable(ref, file, { contentType });
	onTaskCreated?.(task);

	await new Promise((resolve, reject) => {
		task.on(
			'state_changed',
			(snap) => {
				if (typeof isAborted === 'function' && isAborted()) {
					task.cancel();
					return;
				}
				const total = snap.totalBytes || file.size || 1;
				onProgress?.((snap.bytesTransferred / total) * 100);
			},
			(err) => {
				if (err?.code === 'storage/canceled') reject(makeError('تمّ إلغاء الرفع.', 'aborted'));
				else reject(err);
			},
			() => resolve(undefined)
		);
	});

	if (typeof isAborted === 'function' && isAborted()) {
		throw makeError('تمّ إلغاء الرفع.', 'aborted');
	}

	const url = await getDownloadURL(task.snapshot.ref);
	return {
		url,
		path,
		bucket: null,
		contentType,
		size: file.size,
		filename: safeName,
		target: /** @type {UploadTarget} */ ('nebras')
	};
}

function makeError(message, reason = null, status = 0, cause = null, payload = null) {
	const err = /** @type {any} */ (new Error(message));
	err.reason = reason;
	err.status = status;
	err.payload = payload;
	if (cause) err.cause = cause;
	return err;
}
