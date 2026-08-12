/**
 * registry.js — سجلّ العناصر المُستوردة من Internet Archive لمنع التكرار،
 * وسجلّ موازٍ للفشل (blacklist تدريجيّ) لتجنّب إعادة محاولة العناصر
 * المسمومة باستمرار.
 *
 * مسارات RTDB:
 *   ia_library_registry/{safeIdentifier}   — سجلّ كلّ عنصر استُورد بنجاح
 *   ia_library_failures/{safeIdentifier}   — عدّاد فشل مع آخر سبب
 *
 * المفاتيح: نطهّر الـ identifier من الحروف الممنوعة في مفاتيح RTDB
 * (`. $ # [ ] /`) ونحدّد طوله. هذا يضمن أنّ identifier الذي يأتي من IA
 * (يقتصر عادةً على alphanumeric + dash + underscore) يبقى مقروءاً.
 *
 * البنية متطابقة مع noor_library_registry لجعل factoryReset مزدوج المصدر
 * يعمل بنفس النمط ولتسهيل قراءة لوحة التحكّم.
 */

import { getAdminDatabase } from '$lib/server/firebaseAdmin.js';
import { PERMANENT_FAILURE_REASONS, LICENSE_GATE_VERSION } from './licenseFilter.js';

const REGISTRY_ROOT = 'ia_library_registry';
const FAILURES_ROOT = 'ia_library_failures';

/** بعد هذا العدد من الإخفاقات يُعتبر العنصر blacklisted نهائياً. */
export const FAILURE_BLACKLIST_THRESHOLD = 3;

function safeKey(identifier) {
	return String(identifier || '')
		.replace(/[.$#\[\]/]/g, '_')
		.slice(0, 700);
}

/**
 * يفحص ما إذا كان العنصر مُستورداً سابقاً (= موجود في registry).
 *
 * @param {string} identifier
 * @returns {Promise<boolean>}
 */
export async function isItemImported(identifier) {
	const key = safeKey(identifier);
	if (!key) return false;
	const snap = await getAdminDatabase().ref(`${REGISTRY_ROOT}/${key}`).get();
	return snap.exists();
}

/**
 * يقسّم قائمة من معرّفات IA إلى:
 *   - knownIds: ما هو مستورد سابقاً، أو blacklisted (failures ≥ العتبة)
 *   - newIds: الباقي القابل للمعالجة
 *
 * @param {string[]} identifiers
 * @returns {Promise<{ knownIds: Set<string>, newIds: string[] }>}
 */
export async function partitionKnownItems(identifiers) {
	const ids = (identifiers || []).map(safeKey).filter(Boolean);
	const db = getAdminDatabase();

	const [regSnap, failSnap, dmcaSnap] = await Promise.all([
		db.ref(REGISTRY_ROOT).get(),
		db.ref(FAILURES_ROOT).get(),
		// ⚖️ DMCA blacklist — أي عنصر هنا لا يُستورد أبداً (تنفيذ takedown)
		db.ref('ia_library_dmca_blacklist').get()
	]);

	const known = new Set(regSnap.exists() ? Object.keys(regSnap.val() || {}) : []);
	if (failSnap.exists()) {
		const failures = failSnap.val() || {};
		for (const [id, rec] of Object.entries(failures)) {
			const count = Number(rec?.count || 0);
			// permanent flag = من DMCA takedown → blacklist فوري دائم.
			if (rec?.permanent === true) {
				known.add(id);
				continue;
			}
			// أخطاء الترخيص قابلة لإعادة التقييم (الفحص يجري قبل التنزيل فهو
			// رخيص، ومنطق البوّابة قد يتغيّر). نحظرها فقط إذا سُجّلت تحت
			// إصدار البوّابة الحاليّ؛ أمّا ما حُظر تحت إصدار قديم فيُعاد مرّة
			// واحدة تحت البوّابة المُصلَحة (يستعيد عناصر الملكية العامّة).
			const reason = String(rec?.lastReason || '');
			if (reason.startsWith('license_')) {
				const stampedVersion = Number(rec?.gateVersion || 0);
				if (stampedVersion === LICENSE_GATE_VERSION && count >= FAILURE_BLACKLIST_THRESHOLD) {
					known.add(id);
				}
				continue;
			}
			// أخطاء غير الترخيص (تنزيل/تحقّق بايتات/شبكة) — حظر عند العتبة.
			if (count >= FAILURE_BLACKLIST_THRESHOLD) known.add(id);
		}
	}
	if (dmcaSnap.exists()) {
		for (const id of Object.keys(dmcaSnap.val() || {})) known.add(id);
	}

	if (ids.length === 0) return { knownIds: known, newIds: [] };
	const newIds = [];
	for (const id of ids) {
		if (!known.has(id)) newIds.push(id);
	}
	return { knownIds: known, newIds };
}

/**
 * يسجّل عنصراً استُورد بنجاح.
 *
 * @param {string} identifier
 * @param {{
 *   fileId: string,
 *   title?: string,
 *   iaSourceUrl?: string,
 *   licenseMatched?: string,
 *   collection?: string,
 *   hierarchy?: { mainId:string, subId:string, secondaryId?:string|null },
 *   createdSectionsIds?: string[],
 *   pickedFileName?: string,
 *   pickedFileSize?: number,
 *   nebrasContentType?: 'document'|'audio'|'video'
 * }} record
 */
export async function recordImported(identifier, record) {
	const key = safeKey(identifier);
	if (!key) throw new Error('identifier غير صالح للتسجيل.');
	const payload = {
		fileId: String(record?.fileId || ''),
		title: String(record?.title || '').slice(0, 400),
		iaSourceUrl: String(record?.iaSourceUrl || '').slice(0, 1000),
		licenseMatched: String(record?.licenseMatched || '').slice(0, 200),
		collection: String(record?.collection || '').slice(0, 200),
		hierarchy: record?.hierarchy || null,
		createdSectionsIds: Array.isArray(record?.createdSectionsIds)
			? record.createdSectionsIds.slice(0, 10)
			: [],
		pickedFileName: String(record?.pickedFileName || '').slice(0, 240),
		pickedFileSize: Number(record?.pickedFileSize || 0),
		nebrasContentType: String(record?.nebrasContentType || '').slice(0, 16),
		importedAt: { '.sv': 'timestamp' }
	};
	await getAdminDatabase().ref(`${REGISTRY_ROOT}/${key}`).set(payload);
}

/**
 * يسجّل محاولة فاشلة. بعد بلوغ العتبة يُعدّ العنصر blacklisted آلياً عبر
 * partitionKnownItems.
 *
 * @param {string} identifier
 * @param {{ reason?: string, message?: string, iaSourceUrl?: string }} info
 */
export async function recordFailure(identifier, info = {}) {
	const key = safeKey(identifier);
	if (!key) return;
	const ref = getAdminDatabase().ref(`${FAILURES_ROOT}/${key}`);
	const reason = String(info?.reason || 'unknown').slice(0, 80);
	const reasonKey = reason.replace(/^license_/, '');
	const bump =
		PERMANENT_FAILURE_REASONS.has(reasonKey) || reason.startsWith('license_')
			? FAILURE_BLACKLIST_THRESHOLD
			: 1;

	const isLicenseReason = reason.startsWith('license_');
	await ref.transaction((current) => {
		const c = current || { count: 0, firstFailedAt: Date.now() };
		// عند إعادة محاولة عنصر مرفوض ترخيصياً تحت بوّابة جديدة: نبدأ العدّ
		// من الصفر بدل التراكم، كي لا يبقى محظوراً بعدّ قديم متضخّم.
		const baseCount =
			isLicenseReason && Number(c.gateVersion || 0) !== LICENSE_GATE_VERSION
				? 0
				: Number(c.count || 0);
		const nextCount = Math.max(baseCount + bump, bump);
		return {
			count: nextCount,
			firstFailedAt: c.firstFailedAt || Date.now(),
			lastFailedAt: Date.now(),
			lastReason: reason,
			lastMessage: String(info?.message || '').slice(0, 300),
			iaSourceUrl: String(info?.iaSourceUrl || c.iaSourceUrl || '').slice(0, 1000),
			// ختم إصدار البوّابة على أخطاء الترخيص لتمييز الحظر القديم.
			gateVersion: isLicenseReason ? LICENSE_GATE_VERSION : (c.gateVersion || null)
		};
	});
}

/**
 * يحذف سجلّاً واحداً (لإعادة المحاولة لاحقاً).
 * @param {string} identifier
 */
export async function clearImported(identifier) {
	const key = safeKey(identifier);
	if (!key) return;
	await getAdminDatabase().ref(`${REGISTRY_ROOT}/${key}`).remove();
}

/**
 * @returns {Promise<{ totalImported: number, totalFailed: number, blacklistedCount: number }>}
 */
export async function getRegistryStats() {
	const [regSnap, failSnap] = await Promise.all([
		getAdminDatabase().ref(REGISTRY_ROOT).get(),
		getAdminDatabase().ref(FAILURES_ROOT).get()
	]);
	const totalImported = regSnap.exists() ? Object.keys(regSnap.val() || {}).length : 0;
	let totalFailed = 0;
	let blacklisted = 0;
	if (failSnap.exists()) {
		const val = failSnap.val() || {};
		for (const k of Object.keys(val)) {
			totalFailed += 1;
			if (Number(val[k]?.count || 0) >= FAILURE_BLACKLIST_THRESHOLD) blacklisted += 1;
		}
	}
	return { totalImported, totalFailed, blacklistedCount: blacklisted };
}
