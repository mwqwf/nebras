/**
 * playabilityFilter.js — تَحكُم الصيغ القابلة فعلاً للتشغيل داخل تطبيق
 * نبراس Flutter. لا يدخل أيّ ملف إلى Firebase ما لم يجتز هذا الفلتر.
 *
 * ╔══════════════════════════════════════════════════════════════════╗
 * ║  ⚠️ هذا الملفّ هو الحارس النهائي بين Internet Archive والتطبيق.    ║
 * ║  أيّ تساهل هنا = ظهور محتوى في التطبيق لا يستطيع تشغيله = تجربة   ║
 * ║  مكسورة للمستخدم. نتبنّى سياسة "كلّ ما لم يُسمح به صراحةً مرفوض".  ║
 * ╚══════════════════════════════════════════════════════════════════╝
 *
 * المنطلق العملي:
 *   - الكتب: المشغّل في التطبيق هو SfPdfViewer (Syncfusion) — يقبل
 *     PDF فقط بشكل موثوق على Android و iOS. لذلك نسمح بـ .pdf حصراً
 *     ونرفض .epub/.djvu/.doc/.docx/.txt/.rtf حتى لو وردتْ في content_model.
 *   - الصوت: المشغّل هو just_audio — يتعامل جيّداً مع mp3/m4a/aac/wav/ogg/opus/flac.
 *     نُبقي القائمة محدودة بهذه الصيغ ونتجنّب wma/ape/midi.
 *   - الفيديو: المشغّل هو video_player الرسمي — موثوق فقط مع mp4 (H.264 + AAC).
 *     webm/mkv/avi غير موثوقة على iOS؛ نرفضها لئلّا يظهر فيديو لا يعمل.
 *
 * هذا الملفّ معزول عن أيّ I/O، خالص في الذاكرة، لكي يكون قابلاً للاختبار
 * بسهولة. كلّ نقطة فحص تُرجع كائناً يفسّر سبب القبول/الرفض.
 */

/**
 * أنواع محتوى التطبيق (ContentType في content_model.dart).
 * @typedef {'document'|'audio'|'video'} NebrasContentType
 */

/**
 * الصيغ المسموحة لكلّ نوع. **القائمة موحَّدة** ومتطابقة مع
 * _looksLikeBookUrl / _looksLikeAudioUrl في تطبيق Flutter، باستثناء:
 *   - الكتب: نُلزم PDF فقط (Syncfusion لا يفتح غيره موثوقاً).
 *   - الفيديو: MP4 فقط (video_player الرسمي لا يضمن غيره).
 */
export const ALLOWED_EXTENSIONS = Object.freeze({
	document: Object.freeze(['.pdf']),
	audio: Object.freeze(['.mp3', '.m4a', '.aac', '.wav', '.ogg', '.opus', '.flac']),
	video: Object.freeze(['.mp4'])
});

/**
 * أنواع MIME المقبولة. مكمِّلة للامتداد — إن غاب الامتداد نستعملها.
 */
export const ALLOWED_MIME = Object.freeze({
	document: Object.freeze(['application/pdf']),
	audio: Object.freeze([
		'audio/mpeg',
		'audio/mp3',
		'audio/mp4',
		'audio/m4a',
		'audio/aac',
		'audio/x-aac',
		'audio/wav',
		'audio/x-wav',
		'audio/ogg',
		'audio/opus',
		'audio/flac',
		'audio/x-flac'
	]),
	video: Object.freeze(['video/mp4'])
});

/**
 * حدود الحجم القصوى لكل نوع (بايت). يحمي من ملفّات ضخمة تستهلك Storage
 * وbandwidth وتفشل في تشغيل التطبيق. القيم اخْتيرَت بتحفّظ.
 */
/**
 * حدود الحجم العليا. الحاكم الفعليّ للزمن هو **مهلة التنزيل** في
 * downloader.js (يلغي البثّ عند تجاوز الحدّ أو المهلة) لا هذه القيمة:
 * أيّ ملفّ أكبر/أبطأ من اللازم يُلغى ويُتخطّى بصمت — فلا يدخل التطبيق إلا
 * ما تنزّل وتحقّق فعلاً. لذلك نوسّع الحدود لتمرّ الكتب الكبيرة والصوتيّات
 * والفيديوهات الحقيقيّة (كان 30/40 م.ب يرفض شبه كلّ صوت/فيديو إسلاميّ).
 */
export const MAX_SIZE_BYTES = Object.freeze({
	document: 100 * 1024 * 1024, // 100 م.ب — مسوحات كتب عربيّة كبيرة
	audio: 150 * 1024 * 1024, //  150 م.ب — محاضرة/تلاوة كاملة
	video: 200 * 1024 * 1024 //   200 م.ب — درس/خطبة مرئيّة
});

/**
 * يستخرج الامتداد من اسم ملفّ أو رابط (مع تنظيف الـ query/hash).
 * @param {string} nameOrUrl
 * @returns {string} الامتداد بحرف لاتيني صغير ومع النقطة، أو '' إن غاب.
 */
export function extractExtension(nameOrUrl) {
	const raw = String(nameOrUrl || '').trim().toLowerCase();
	if (!raw) return '';
	const pathOnly = raw.split('?')[0].split('#')[0];
	const lastSlash = pathOnly.lastIndexOf('/');
	const tail = lastSlash >= 0 ? pathOnly.slice(lastSlash + 1) : pathOnly;
	const lastDot = tail.lastIndexOf('.');
	if (lastDot < 0) return '';
	return tail.slice(lastDot); // يبدأ بـ '.'
}

/**
 * يستخرج نوع المحتوى المقصود (document/audio/video) من ملف IA واحد.
 * @param {{ name?: string, format?: string, source?: string }} iaFile
 * @returns {NebrasContentType | null}
 */
export function inferNebrasContentType(iaFile) {
	const ext = extractExtension(iaFile?.name);
	for (const type of /** @type {NebrasContentType[]} */ (['document', 'audio', 'video'])) {
		if (ALLOWED_EXTENSIONS[type].includes(ext)) return type;
	}
	return null;
}

/**
 * يفحص ملفّاً واحداً من قائمة ملفات IA: هل هو من نوع مقبول؟ هل امتداده
 * مسموح؟ هل حجمه ضمن الحدّ؟ هل ليس derivative ضخماً (مثل _bw.pdf أو
 * jp2.zip) قد يُسبّب تشويهاً للنسخة الأصليّة؟
 *
 * مفهوم derivative: IA يولّد نسخاً متعدّدة من نفس العنصر. الأصل يحمل
 * `source: 'original'`. النسخ الأخرى تحمل `source: 'derivative'`. نُفضّل
 * الأصل دائماً ثم derivatives ذات الجودة الجيّدة (lossless/abbyy.gz غير
 * مدعوم في التطبيق فنتجاوزها). نحدد ذلك بـ name pattern.
 *
 * @param {{
 *   name: string,
 *   format?: string,
 *   size?: string | number,
 *   source?: 'original' | 'derivative' | string
 * }} iaFile
 * @returns {{ ok: boolean, reason?: string, type?: NebrasContentType, size?: number }}
 */
export function evaluateIaFile(iaFile) {
	if (!iaFile?.name) return { ok: false, reason: 'no_name' };
	const name = String(iaFile.name).toLowerCase();

	// 1) رفض derivatives قطعيّاً معروفة لا تعمل في التطبيق
	if (
		name.endsWith('_bw.pdf') || // مسح أبيض/أسود ضعيف الجودة
		name.endsWith('_text.pdf') || // OCR-only، عادةً مشوَّش
		name.endsWith('_abbyy.gz') ||
		name.endsWith('_djvu.txt') ||
		name.endsWith('_djvu.xml') ||
		name.endsWith('_jp2.zip') ||
		name.endsWith('_scandata.xml') ||
		name.endsWith('.gif') || // ميتاداتا/شعارات IA لا محتوى
		name.endsWith('.sqlite') ||
		name.endsWith('_meta.xml') ||
		name.endsWith('_meta.sqlite') ||
		name.endsWith('_files.xml') ||
		name.endsWith('.torrent')
	) {
		return { ok: false, reason: 'derivative_blocked' };
	}

	// 2) تحديد النوع من الامتداد
	const type = inferNebrasContentType(iaFile);
	if (!type) {
		return { ok: false, reason: 'unsupported_extension' };
	}

	// 3) فحص الحجم (إن أعطاه IA)
	const size = Number(iaFile.size || 0);
	if (size > 0 && size > MAX_SIZE_BYTES[type]) {
		return { ok: false, reason: 'size_over_limit', type, size };
	}

	return { ok: true, type, size };
}

/**
 * يختار **أفضل ملفّ قابل للتشغيل** من قائمة ملفّات عنصر IA كامل، مع
 * ترتيب صارم:
 *   1) ملفّ من نوع document (PDF) أصلي  →  ثم derivative مسموح
 *   2) ملفّ من نوع audio (MP3) أصلي    →  ثم derivative مسموح
 *   3) ملفّ من نوع video (MP4) أصلي    →  ثم derivative مسموح
 *
 * لكن نقدّم النوع المُعلَن من IA (mediatype) إن وُجد:
 *   - mediatype=texts  → نختار document
 *   - mediatype=audio  → نختار audio
 *   - mediatype=movies → نختار video
 *
 * هذا يمنع جلب MP3 من كتاب فيه ملف تلاوة جانبيّ، أو جلب PDF index من
 * عنصر فيديو.
 *
 * @param {Array<{ name:string, format?:string, size?:string|number, source?:string }>} files
 * @param {{ mediatype?: string }} item metadata الكامل للعنصر
 * @returns {{
 *   ok: boolean,
 *   reason?: string,
 *   file?: { name:string, format?:string, size?:number, source?:string },
 *   type?: NebrasContentType,
 *   size?: number
 * }}
 */
export function chooseBestPlayableFile(files, item, opts = {}) {
	const preferSmallest = Boolean(opts.preferSmallest);
	if (!Array.isArray(files) || files.length === 0) {
		return { ok: false, reason: 'no_files' };
	}

	// تطبيع mediatype من IA → نوع نبراس
	const mediatype = String(item?.mediatype || '').toLowerCase();
	let priority;
	if (mediatype === 'texts') priority = ['document'];
	else if (mediatype === 'audio') priority = ['audio'];
	else if (mediatype === 'movies') priority = ['video'];
	else priority = ['document', 'audio', 'video']; // fallback (نادر)

	for (const wantedType of priority) {
		// نُجمّع جميع الملفّات المقبولة من النوع المرغوب، ثم نرتّبها:
		// (أ) original أوّلاً، (ب) الأكبر حجماً أوّلاً (عادةً أعلى جودة).
		const candidates = [];
		for (const f of files) {
			const eval_ = evaluateIaFile(f);
			if (!eval_.ok) continue;
			if (eval_.type !== wantedType) continue;
			candidates.push({ file: f, eval: eval_ });
		}
		if (candidates.length === 0) continue;

		candidates.sort((a, b) => {
			const aOrig = (a.file.source || '').toLowerCase() === 'original' ? 0 : 1;
			const bOrig = (b.file.source || '').toLowerCase() === 'original' ? 0 : 1;
			if (aOrig !== bOrig) return aOrig - bOrig;
			const aSize = Number(a.eval.size || 0);
			const bSize = Number(b.eval.size || 0);
			return preferSmallest ? aSize - bSize : bSize - aSize;
		});

		const winner = candidates[0];
		return {
			ok: true,
			file: {
				name: winner.file.name,
				format: winner.file.format,
				size: Number(winner.eval.size || 0),
				source: winner.file.source
			},
			type: /** @type {NebrasContentType} */ (wantedType),
			size: Number(winner.eval.size || 0)
		};
	}

	return { ok: false, reason: 'no_playable_file' };
}

/**
 * يفحص **رأس** الملفّ فقط (أوّل بايتات) دون تنزيله كاملاً — لاستعماله في
 * وضع metadata-only حيث نطلب من IA `Range: bytes=0-511` بدل تنزيل الملفّ.
 * يتحقّق من توقيع magic bytes ومن توافق الـ MIME (إن وُجد).
 *
 * هذا هو نفس منطق magic bytes في verifyDownloadedBuffer لكن بدون فحص
 * الحجم الكامل (الحجم يأتي من Content-Range/Content-Length) وبدون فحص
 * تشفير PDF (يتطلّب نهاية الملفّ — يُفحص عبر headTailHasPdfEncrypt إن
 * أُحضِر ذيل الملفّ منفصلاً).
 *
 * @param {Buffer | Uint8Array} head أوّل بايتات الملفّ (≥ 16 بايت يكفي).
 * @param {{ contentType?: string, declaredType: NebrasContentType }} opts
 * @returns {{ ok: boolean, reason?: string }}
 */
export function verifyHeadBytes(head, { contentType, declaredType }) {
	if (!head || head.byteLength === 0) {
		return { ok: false, reason: 'empty_head' };
	}
	const ct = String(contentType || '').toLowerCase();
	const allowedCt = ALLOWED_MIME[declaredType] || [];
	if (ct && !allowedCt.some((m) => ct.includes(m)) && !ct.includes('octet-stream')) {
		return { ok: false, reason: 'mime_mismatch' };
	}
	const h = Buffer.isBuffer(head) ? head.subarray(0, 16) : Buffer.from(head.slice(0, 16));
	if (declaredType === 'document') {
		if (!(h[0] === 0x25 && h[1] === 0x50 && h[2] === 0x44 && h[3] === 0x46)) {
			return { ok: false, reason: 'magic_bytes_not_pdf' };
		}
	} else if (declaredType === 'audio') {
		const isId3 = h[0] === 0x49 && h[1] === 0x44 && h[2] === 0x33;
		const isFlac = h[0] === 0x66 && h[1] === 0x4c && h[2] === 0x61 && h[3] === 0x43;
		const isOgg = h[0] === 0x4f && h[1] === 0x67 && h[2] === 0x67 && h[3] === 0x53;
		const isRiff = h[0] === 0x52 && h[1] === 0x49 && h[2] === 0x46 && h[3] === 0x46;
		const isMp4 = h[4] === 0x66 && h[5] === 0x74 && h[6] === 0x79 && h[7] === 0x70;
		const isMpegFrame = h[0] === 0xff && (h[1] & 0xe0) === 0xe0;
		if (!isId3 && !isFlac && !isOgg && !isRiff && !isMp4 && !isMpegFrame) {
			return { ok: false, reason: 'magic_bytes_not_audio' };
		}
	} else if (declaredType === 'video') {
		const isMp4 = h[4] === 0x66 && h[5] === 0x74 && h[6] === 0x79 && h[7] === 0x70;
		if (!isMp4) {
			return { ok: false, reason: 'magic_bytes_not_mp4' };
		}
	}
	return { ok: true };
}

/**
 * يكتشف PDF مُشفَّر/محميّ بكلمة مرور من ذيله (الـ trailer قرب النهاية).
 * يُستعمل في وضع metadata-only بطلب Range منفصل لذيل الملفّ، لأنّ قارئ
 * Syncfusion في التطبيق لا يفتح PDF المشفّر فيظهر "المصدر غير متاح".
 *
 * @param {Buffer | Uint8Array} tail آخر بايتات الملفّ (~8KB).
 * @returns {boolean}
 */
export function pdfTailIsEncrypted(tail) {
	if (!tail || tail.byteLength === 0) return false;
	const buf = Buffer.isBuffer(tail) ? tail : Buffer.from(tail);
	return buf.toString('latin1').includes('/Encrypt');
}

/**
 * يفحص buffer منزَّل + رؤوس Response قبل الكتابة في Firebase. هذه آخر
 * نقطة دفاع: حتى لو نجح كلّ ما سبق، نتأكّد:
 *   - الحجم > 0 وضمن الحدّ
 *   - الـ Content-Type المُستلم يطابق النوع المعلن
 *   - الـ buffer يبدأ بـ magic bytes الصحيحة (مثل %PDF, ID3, RIFF, ftyp)
 *
 * @param {Buffer | Uint8Array} buffer
 * @param {{ contentType?: string, declaredType: NebrasContentType }} opts
 * @returns {{ ok: boolean, reason?: string }}
 */
export function verifyDownloadedBuffer(buffer, { contentType, declaredType }) {
	if (!buffer || buffer.byteLength === 0) {
		return { ok: false, reason: 'empty_buffer' };
	}
	if (buffer.byteLength > MAX_SIZE_BYTES[declaredType]) {
		return { ok: false, reason: 'size_over_limit_runtime' };
	}

	const ct = String(contentType || '').toLowerCase();
	const allowedCt = ALLOWED_MIME[declaredType] || [];
	// MIME ليس قاطعاً (بعض السيرفرات تُرجع octet-stream)، لكن إن كان موجوداً
	// ولا يطابق فهو إشارة قويّة على ملف تالف/خاطئ.
	if (ct && !allowedCt.some((m) => ct.includes(m)) && !ct.includes('octet-stream')) {
		return { ok: false, reason: 'mime_mismatch' };
	}

	// magic bytes — تحقّق سريع جدّاً (أوّل 16 بايت)
	const head = Buffer.isBuffer(buffer) ? buffer.subarray(0, 16) : Buffer.from(buffer.slice(0, 16));
	if (declaredType === 'document') {
		// PDF: '%PDF-'
		if (!(head[0] === 0x25 && head[1] === 0x50 && head[2] === 0x44 && head[3] === 0x46)) {
			return { ok: false, reason: 'magic_bytes_not_pdf' };
		}
		// رفض PDF مُشفّر/محميّ بكلمة مرور — قارئ Syncfusion في التطبيق لا يفتحه
		// فيظهر "المصدر غير متاح". نفحص طرفي الملفّ (الـ trailer غالباً قرب النهاية).
		const buf = Buffer.isBuffer(buffer) ? buffer : Buffer.from(buffer);
		const headStr = buf.subarray(0, Math.min(buf.length, 8192)).toString('latin1');
		const tailStr = buf.subarray(Math.max(0, buf.length - 8192)).toString('latin1');
		if (headStr.includes('/Encrypt') || tailStr.includes('/Encrypt')) {
			return { ok: false, reason: 'pdf_encrypted' };
		}
	} else if (declaredType === 'audio') {
		// نقبل أيًّا من: ID3 (mp3) | 'fLaC' | 'OggS' | 'RIFF' (wav) | 'ftyp' (m4a/aac)
		const isId3 = head[0] === 0x49 && head[1] === 0x44 && head[2] === 0x33;
		const isFlac = head[0] === 0x66 && head[1] === 0x4c && head[2] === 0x61 && head[3] === 0x43;
		const isOgg = head[0] === 0x4f && head[1] === 0x67 && head[2] === 0x67 && head[3] === 0x53;
		const isRiff = head[0] === 0x52 && head[1] === 0x49 && head[2] === 0x46 && head[3] === 0x46;
		const isMp4 = head[4] === 0x66 && head[5] === 0x74 && head[6] === 0x79 && head[7] === 0x70;
		// mp3 بدون ID3 يبدأ بإطار MPEG (0xFF 0xFB/0xFA/0xF3/0xF2)
		const isMpegFrame = head[0] === 0xff && (head[1] & 0xe0) === 0xe0;
		if (!isId3 && !isFlac && !isOgg && !isRiff && !isMp4 && !isMpegFrame) {
			return { ok: false, reason: 'magic_bytes_not_audio' };
		}
	} else if (declaredType === 'video') {
		// MP4: 4 بايت size ثمّ 'ftyp'
		const isMp4 = head[4] === 0x66 && head[5] === 0x74 && head[6] === 0x79 && head[7] === 0x70;
		if (!isMp4) {
			return { ok: false, reason: 'magic_bytes_not_mp4' };
		}
	}

	return { ok: true };
}
