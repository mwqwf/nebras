/**
 * طابور كتابة Firestore المتسلسل (FIFO) لميزة الرفع المتعدد.
 *
 * رفع Storage يعمل بالتوازي؛ عند اكتمال أي ملف يُضاف إلى هذا الطابور.
 * لا يُنفَّذ commit إلا عندما يصبح selectionIndex مساوياً للمؤشر التالي،
 * فيُضمن أن أوّل ملف اختاره المستخدم يُكتَب في قاعدة البيانات أوّلاً.
 */

/**
 * @param {number} [startIndex]
 */
export function createCommitQueue(startIndex = 0) {
	let nextIndex = startIndex;
	/** @type {Map<number, () => Promise<void>>} */
	const waiting = new Map();
	/** @type {Promise<void>} */
	let chain = Promise.resolve();

	/**
	 * @param {number} selectionIndex
	 * @param {() => Promise<void>} fn
	 */
	function enqueue(selectionIndex, fn) {
		return new Promise((resolve, reject) => {
			const wrapped = async () => {
				try {
					await fn();
					resolve();
				} catch (err) {
					reject(err);
				}
			};
			waiting.set(selectionIndex, wrapped);
			chain = chain.then(() => drain());
		});
	}

	async function drain() {
		while (waiting.has(nextIndex)) {
			const fn = waiting.get(nextIndex);
			waiting.delete(nextIndex);
			try {
				await fn();
			} catch {
				/* يُعالَج الخطأ داخل الـ wrapper */
			}
			nextIndex += 1;
		}
	}

	function reset(start = 0) {
		nextIndex = start;
		waiting.clear();
		chain = Promise.resolve();
	}

	/** انتظار اكتمال كل الكتابات المعلّقة */
	async function flush() {
		await chain;
	}

	return { enqueue, reset, flush };
}
