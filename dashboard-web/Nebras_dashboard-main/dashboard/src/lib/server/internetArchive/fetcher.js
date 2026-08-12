/**
 * fetcher.js — جلب metadata + اختيار أفضل ملفّ قابل للتشغيل + بناء كائن
 * "preview" موحَّد يُمرَّر لمحرّك الاستيراد.
 *
 * نقطة دخول واحدة: `previewItem(identifier, opts)`.
 *   1) يستدعي IA metadata API
 *   2) يفحص الترخيص عبر licenseFilter
 *   3) يفحص قائمة الملفّات عبر playabilityFilter ويختار الأفضل
 *   4) يبني thumbnailUrl (https://archive.org/services/img/{id})
 *   5) يُرجع كائناً معياريّاً يمكن للمعاينة عرضه وللمحرّك تمريره لـ
 *      adminUploader.
 *
 * إن فشل أيّ من الفحوصات (license/playability/files) **نرمي خطأً واضحاً
 * قبل أيّ كتابة** — وهذا يضمن: "المحتوى الذي لا يُشغَّل لا يظهر إطلاقاً".
 */

import { fetchItemMetadata, buildDownloadUrl } from './search.js';
import { evaluateLicense } from './licenseFilter.js';
import { chooseBestPlayableFile } from './playabilityFilter.js';

/**
 * @typedef {Object} ItemPreview
 * @property {string} identifier
 * @property {string} title
 * @property {string} author
 * @property {string} description
 * @property {string} thumbnailUrl
 * @property {'document'|'audio'|'video'} nebrasContentType
 * @property {{
 *   name: string,
 *   format?: string,
 *   size: number,
 *   source?: string,
 *   downloadUrl: string,
 *   contentType: string
 * }} pickedFile
 * @property {{ licenseMatched?: string, collection?: string }} licenseInfo
 * @property {string} iaSourceUrl
 * @property {string[]} subjects
 * @property {string[]} collections
 * @property {string} language
 * @property {string} date
 */

/** يلتقط أوّل قيمة نصّيّة غير فارغة من مصفوفة قد تكون نصّاً أو مصفوفة. */
function firstString(value) {
	if (Array.isArray(value)) return firstString(value[0]);
	if (value == null) return '';
	return String(value).trim();
}

function asStringArray(value) {
	if (Array.isArray(value)) return value.map((v) => String(v || '').trim()).filter(Boolean);
	if (value == null) return [];
	const s = String(value || '').trim();
	return s ? [s] : [];
}

/**
 * يبني عنواناً ذا معنى للعنصر. كثير من عناصر IA (خاصّة تلاوات/مقاطع مرقّمة)
 * عنوانها مجرّد رقم مثل "001" أو "تتمة 3"، فيظهر في التطبيق اسماً عابثاً.
 * عند اكتشاف عنوان فقير (رقم بحت أو قصير جداً) نُثريه بالألبوم ثمّ المؤلّف
 * (المُنشد/المحاضر) فيصير مثل «الشيخ محمود الحصري - 001» بدل «001».
 * إن لم يتوفّر بديل نُبقي العنوان كما هو (أفضل من لا شيء).
 */
function buildItemTitle(metadata, id) {
	const title = firstString(metadata?.title) || '';
	if (!title) return String(id);
	const isPoor = /^\d{1,4}$/.test(title) || title.length < 2;
	if (!isPoor) return title;
	const album = firstString(metadata?.album);
	const creator = firstString(metadata?.creator);
	const context = album || creator;
	return context ? `${context} - ${title}` : title;
}

/**
 * يبني رابط الـ thumbnail الذي يصلح كصورة غلاف.
 * IA يقدّم thumbnail خدمي ثابت: https://archive.org/services/img/{id}
 */
function buildItemThumbnail(identifier) {
	return `https://archive.org/services/img/${encodeURIComponent(identifier)}`;
}

/**
 * يُعيد content-type الـ MIME المستنبط من الامتداد بدقّة (لتمريره إلى
 * adminUploader عند الرفع). يُفضّل أن يكون قاطعاً قدر الإمكان.
 */
function mimeForExtension(name) {
	const lower = String(name || '').toLowerCase();
	if (lower.endsWith('.pdf')) return 'application/pdf';
	if (lower.endsWith('.mp3')) return 'audio/mpeg';
	if (lower.endsWith('.m4a')) return 'audio/mp4';
	if (lower.endsWith('.aac')) return 'audio/aac';
	if (lower.endsWith('.wav')) return 'audio/wav';
	if (lower.endsWith('.ogg')) return 'audio/ogg';
	if (lower.endsWith('.opus')) return 'audio/opus';
	if (lower.endsWith('.flac')) return 'audio/flac';
	if (lower.endsWith('.mp4')) return 'video/mp4';
	return 'application/octet-stream';
}

/**
 * @param {string} identifier
 * @param {{
 *   trustedCollections?: string[],
 *   allowMissingLicenseInTrustedCollections?: boolean
 * }} [opts]
 * @returns {Promise<ItemPreview>}
 */
export async function previewItem(identifier, opts = {}) {
	const id = String(identifier || '').trim();
	if (!id) {
		throw Object.assign(new Error('identifier فارغ.'), { reason: 'empty_identifier', status: 400 });
	}

	const { metadata, files } = await fetchItemMetadata(id);

	// 1) فلتر الترخيص — قبل أيّ شيء آخر
	const lic = evaluateLicense(metadata, opts);
	if (!lic.ok) {
		throw Object.assign(
			new Error(`الترخيص غير مسموح للنشر: ${lic.reason} (${lic.licenseMatched || ''}).`),
			{ reason: `license_${lic.reason}`, status: 451 }
		);
	}

	// 2) فلتر الصيغ — لا يدخل التطبيق إلا ما يستطيع تشغيله
	const choice = chooseBestPlayableFile(files, metadata, {
		preferSmallest: Boolean(opts.preferSmallestFile)
	});
	if (!choice.ok) {
		throw Object.assign(
			new Error(`لا يوجد ملفّ قابل للتشغيل في "${id}": ${choice.reason}.`),
			{ reason: `playability_${choice.reason}`, status: 422 }
		);
	}

	const pickedName = choice.file.name;
	const downloadUrl = buildDownloadUrl(id, pickedName);
	const contentType = mimeForExtension(pickedName);

	/** @type {ItemPreview} */
	const preview = {
		identifier: id,
		title: buildItemTitle(metadata, id),
		author: firstString(metadata?.creator) || '',
		description: firstString(metadata?.description) || '',
		thumbnailUrl: buildItemThumbnail(id),
		nebrasContentType: choice.type,
		pickedFile: {
			name: pickedName,
			format: choice.file.format,
			size: choice.file.size,
			source: choice.file.source,
			downloadUrl,
			contentType
		},
		licenseInfo: {
			licenseMatched: lic.licenseMatched,
			collection: lic.collection,
			// 'verified_open_license' لو وُجد ترخيص صريح PD/CC،
			// 'community_collection' لو قبلناه عبر fallback المجموعة الموثوقة.
			licenseTier: lic.licenseTier || (lic.licenseMatched ? 'verified_open_license' : null)
		},
		iaSourceUrl: `https://archive.org/details/${encodeURIComponent(id)}`,
		subjects: asStringArray(metadata?.subject),
		collections: asStringArray(metadata?.collection),
		language: firstString(metadata?.language),
		date: firstString(metadata?.date)
	};

	return preview;
}
