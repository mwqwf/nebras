/**
 * notifyEvents — طبقة رقيقة فوق POST /api/notify
 *
 * توفّر دوالّ بأسماء دلالية لاستدعاء الإشعارات عند إضافة محتوى جديد أو إنشاء قسم.
 * الدوالّ هنا "fire-and-forget": عند الفشل لا تُلقي استثناء — تكتفي بـ console.warn
 * حتى لا تُعطّل تدفّق الرفع في الواجهة.
 *
 * صياغة النصوص بالعربية حتى تظهر بشكل طبيعي لجميع المستخدمين.
 */

const ENDPOINT = '/api/notify';

async function postNotification(payload) {
	try {
		const res = await fetch(ENDPOINT, {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: JSON.stringify(payload)
		});
		if (res.status === 501) {
			// غير مفعّل — لا نريد ضجيجاً كبيراً في الكونسول.
			if (import.meta.env?.DEV) {
				console.info(
					'[notifyEvents] تخطّي إرسال إشعار: Firebase Admin غير مُهيّأ (FIREBASE_SERVICE_ACCOUNT_JSON).'
				);
			}
			return { ok: false, skipped: true };
		}
		if (!res.ok) {
			const text = await res.text().catch(() => '');
			console.warn('[notifyEvents] فشل الاستجابة من /api/notify:', res.status, text);
			return { ok: false };
		}
		return await res.json();
	} catch (err) {
		console.warn('[notifyEvents] استثناء أثناء إرسال الإشعار:', err);
		return { ok: false };
	}
}

// ─── صياغة النصوص ──────────────────────────────────────────────

function contentTypeLabelAr(type) {
	const t = String(type || '').toLowerCase();
	if (t === 'audio') return 'صوتية';
	if (t === 'video') return 'فيديو';
	if (t === 'youtube') return 'فيديو يوتيوب';
	return 'محتوى';
}

function sectionLevelLabelAr(level) {
	const t = String(level || '').toLowerCase();
	if (t === 'main') return 'قسم رئيسي';
	if (t === 'sub') return 'قسم فرعي';
	if (t === 'secondary') return 'قسم ثانوي';
	return 'قسم';
}

function buildContentBody({ title, mainSectionName, subSectionName, secondarySectionName }) {
	const parts = [];
	if (title) parts.push(`"${String(title).trim()}"`);
	const chain = [mainSectionName, subSectionName, secondarySectionName]
		.map((s) => (s || '').trim())
		.filter(Boolean);
	if (chain.length > 0) {
		parts.push('في');
		parts.push(chain.join(' › '));
	}
	return `تمت إضافة ${parts.join(' ')}`.replace(/\s+/g, ' ').trim();
}

// ─── واجهات عامة ────────────────────────────────────────────────

// FCM data payload accepts string values فقط؛ ندعّم أرقام المعرّفات
// بتحويلها إلى String بشكل آمن قبل الإرسال.
function idToString(value) {
	if (value === null || value === undefined) return '';
	return String(value).trim();
}

/**
 * إشعار: تمّت إضافة محتوى جديد.
 *
 * @param {{
 *   title: string,
 *   contentType?: string,
 *   contentId?: string|number,
 *   mainSectionId?: string|number,
 *   subSectionId?: string|number,
 *   secondarySectionId?: string|number,
 *   mainSectionName?: string,
 *   subSectionName?: string,
 *   secondarySectionName?: string,
 *   sourceUrl?: string,
 *   thumbnail?: string
 * }} info
 */
export function notifyContentAdded(info) {
	const kind = contentTypeLabelAr(info?.contentType);
	const title = `${kind} جديد في نبراس`;
	const body = buildContentBody(info || {});
	return postNotification({
		title,
		body,
		// كلّ المفاتيح يجب أن تكون سلاسل نصية — مطلب FCM data payload.
		// نُرسل المعرّفات إضافة إلى الأسماء حتى يستطيع التطبيق فتح
		// الشاشة الصحيحة مباشرة عند الضغط على الإشعار (deep-link).
		data: {
			type: 'content_added',
			contentType: info?.contentType || '',
			// الاسم الحقيقيّ للمحتوى — يقرأه التطبيق ليعرض العنوان الصحيح
			// بدل عنوان العرض العامّ عند فتح المحتوى من الإشعار.
			contentTitle: idToString(info?.title),
			contentId: idToString(info?.contentId),
			mainSectionId: idToString(info?.mainSectionId),
			subSectionId: idToString(info?.subSectionId),
			secondarySectionId: idToString(info?.secondarySectionId),
			mainSectionName: info?.mainSectionName || '',
			subSectionName: info?.subSectionName || '',
			secondarySectionName: info?.secondarySectionName || '',
			sourceUrl: info?.sourceUrl || '',
			// الصورة المصغّرة — يقرأها التطبيق (data['thumbnail']) ليعرضها فور فتح
			// المحتوى من الإشعار دون انتظار جلب من الشبكة.
			thumbnail: info?.thumbnail || ''
		}
	});
}

/**
 * إشعار: تمّ إنشاء قسم جديد.
 *
 * @param {{
 *   level: 'main'|'sub'|'secondary',
 *   name: string,
 *   parentName?: string,
 *   sectionId?: string|number,
 *   parentId?: string|number,
 * }} info
 */
export function notifySectionCreated(info) {
	// 🔕 الإشعارات يجب أن تتعلّق بالمحتوى فقط لا الأقسام: عُطِّل إرسال إشعار
	// إنشاء القسم عمداً. إنشاء القسم نفسه (في الواجهة) يبقى يعمل — هذه الدالّة
	// فقط لم تَعُد تُرسل أيّ إشعار. للتراجع مستقبلاً: اجعل القيمة true.
	const NOTIFY_SECTION_CREATION = false;
	if (!NOTIFY_SECTION_CREATION) return Promise.resolve({ ok: false, skipped: true });
	const levelLabel = sectionLevelLabelAr(info?.level);
	const name = (info?.name || '').trim();
	const parent = (info?.parentName || '').trim();
	const title = `${levelLabel} جديد في نبراس`;
	const body = parent
		? `تمّت إضافة ${levelLabel} "${name}" ضمن ${parent}`
		: `تمّت إضافة ${levelLabel} "${name}"`;
	const level = info?.level || '';
	const sectionId = idToString(info?.sectionId);
	const parentId = idToString(info?.parentId);

	// نملأ حقول main/sub/secondary وفقاً للمستوى حتى يفتح التطبيق
	// الشاشة المناسبة مباشرة على الشجرة الصحيحة.
	const data = {
		type: 'section_created',
		level,
		sectionName: name,
		parentName: parent,
		sectionId,
		parentId,
		mainSectionId: '',
		subSectionId: '',
		secondarySectionId: ''
	};
	if (level === 'main') {
		data.mainSectionId = sectionId;
	} else if (level === 'sub') {
		data.mainSectionId = parentId;
		data.subSectionId = sectionId;
	} else if (level === 'secondary') {
		data.subSectionId = parentId;
		data.secondarySectionId = sectionId;
	}

	return postNotification({ title, body, data });
}
