/**
 * توليد مصغّرة من الصفحة الأولى لملف PDF (للرفع المتعدد).
 */
import * as pdfjs from 'pdfjs-dist';

pdfjs.GlobalWorkerOptions.workerSrc = new URL(
	'pdfjs-dist/build/pdf.worker.min.mjs',
	import.meta.url
).toString();

/**
 * @param {File} file
 * @param {{ maxWidth?: number, quality?: number }} [opts]
 * @returns {Promise<{ file: File, preview: string } | null>}
 */
export async function generatePdfThumbnail(file, { maxWidth = 320, quality = 0.82 } = {}) {
	if (!file || file.type !== 'application/pdf') return null;
	try {
		const data = await file.arrayBuffer();
		const pdf = await pdfjs.getDocument({ data }).promise;
		const page = await pdf.getPage(1);
		const viewport = page.getViewport({ scale: 1 });
		const scale = maxWidth / viewport.width;
		const scaled = page.getViewport({ scale: Math.min(scale, 2) });

		const canvas = document.createElement('canvas');
		canvas.width = Math.floor(scaled.width);
		canvas.height = Math.floor(scaled.height);
		const ctx = canvas.getContext('2d');
		if (!ctx) return null;

		await page.render({ canvasContext: ctx, viewport: scaled }).promise;

		const preview = canvas.toDataURL('image/jpeg', quality);
		const blob = await new Promise((resolve) =>
			canvas.toBlob((b) => resolve(b), 'image/jpeg', quality)
		);
		if (!blob) return null;

		const thumbName = file.name.replace(/\.pdf$/i, '') + '_thumb.jpg';
		const thumbFile = new File([blob], thumbName, { type: 'image/jpeg' });
		return { file: thumbFile, preview };
	} catch (err) {
		console.warn('[pdfThumbnail] failed:', err);
		return null;
	}
}
