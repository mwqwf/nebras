/**
 * حقول مرآة Firestore المتوافقة مع تطبيق Flutter (Content.fromJson +
 * compareContentOldestFirst). يُستعمل من الرفع اليدوي والاستيراد الخادمي.
 */

/**
 * @returns {string} معرّف ملفّ بصيغة fb_<epoch>_… ليتوافق ترتيب التطبيق (الأقدم أولاً).
 */
export function generateNebrasFileId() {
	return `fb_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
}

/**
 * @param {Record<string, unknown>} metadata
 * @param {string} downloadUrl
 */
export function buildMobileCompatibleFields(metadata, downloadUrl) {
	const normalized = metadata && typeof metadata === 'object' ? metadata : {};
	const contentType =
		String(normalized.content_type || 'document').trim().toLowerCase() || 'document';
	const sourceFields = {
		sourceUrl: downloadUrl,
		source_url: downloadUrl,
		file_url: downloadUrl
	};
	if (contentType === 'audio') sourceFields.audio_url = downloadUrl;
	if (contentType === 'video') sourceFields.video_url = downloadUrl;
	return {
		id: normalized.id || undefined,
		title: normalized.title || undefined,
		description: normalized.description || undefined,
		author: normalized.author || undefined,
		thumbnail: normalized.thumbnail || undefined,
		content_type: normalized.content_type || undefined,
		subsection: normalized.subsection,
		subsection_name:
			normalized.subsection_name || normalized.subsection_title || undefined,
		secondary_subsection: normalized.secondary_subsection,
		secondary_subsection_name:
			normalized.secondary_subsection_name ||
			normalized.secondary_subsection_title ||
			undefined,
		main_section: normalized.main_section,
		main_section_id: normalized.main_section_id,
		main_section_name: normalized.main_section_name,
		...sourceFields
	};
}
