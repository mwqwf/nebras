/** حد أقصى لحساب الـ checksum (تجنّب قراءة ملفات ضخمة كاملة في الذاكرة). */
const MAX_HASH_BYTES = 50 * 1024 * 1024;

/**
 * @param {File} file
 * @returns {Promise<string|null>}
 */
export async function computeFileSha256(file) {
	if (!file?.size || file.size > MAX_HASH_BYTES) return null;
	const buffer = await file.arrayBuffer();
	if (typeof Worker !== 'undefined') {
		try {
			return await computeFileSha256InWorker(buffer);
		} catch {
			/* fallback */
		}
	}
	const hash = await crypto.subtle.digest('SHA-256', buffer);
	return Array.from(new Uint8Array(hash))
		.map((b) => b.toString(16).padStart(2, '0'))
		.join('');
}

/**
 * @param {ArrayBuffer} buffer
 */
function computeFileSha256InWorker(buffer) {
	return new Promise((resolve, reject) => {
		const worker = new Worker(new URL('../workers/fileHash.worker.js', import.meta.url), {
			type: 'module'
		});
		worker.onmessage = (e) => {
			worker.terminate();
			if (e.data?.ok) resolve(e.data.hash);
			else reject(new Error(e.data?.error || 'hash failed'));
		};
		worker.onerror = (err) => {
			worker.terminate();
			reject(err);
		};
		worker.postMessage({ buffer }, [buffer]);
	});
}
