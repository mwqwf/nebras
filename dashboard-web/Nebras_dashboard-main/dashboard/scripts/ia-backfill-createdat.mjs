#!/usr/bin/env node
/**
 * ia-backfill-createdat.mjs — يُصلح حقل createdAt المكسور (`{}` أو
 * `{_methodName:'serverTimestamp'}`) لوثائق Internet Archive، ويستبدله
 * بـ millis رقميّة حقيقيّة مأخوذة من:
 *   1) created_at النصيّ (ISO) إن وُجد، وإلا
 *   2) الطابع الزمنيّ المضمّن في المعرّف fb_<epoch_ms>_…
 *
 * يصلح فقط وثائق __provider==='internet_archive' في المجموعتين، حتى لا
 * يلمس المحتوى اليدويّ. تشغيل لمرّة واحدة (آمن للتكرار — idempotent).
 */
import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { resolveServiceAccount } from './load-admin-credential.mjs';

const { credentials } = resolveServiceAccount();
const app = initializeApp({ credential: cert(credentials), projectId: credentials.project_id });
const fs = getFirestore(app, process.env.NEBRAS_FIRESTORE_DATABASE_ID || 'default');

function epochFromId(id) {
	const m = /^fb_(\d{10,})/.exec(String(id || ''));
	return m ? Number(m[1]) : 0;
}

function isBrokenCreatedAt(v) {
	if (v == null) return true;
	if (typeof v === 'number') return false; // سليم بالفعل
	if (typeof v === 'object') {
		// Timestamp حقيقيّ له toDate؛ أيّ كائن آخر ({} أو {_methodName}) مكسور.
		if (typeof v.toDate === 'function') return false;
		return true;
	}
	return false;
}

function resolveMillis(d, id) {
	const iso = typeof d.created_at === 'string' ? Date.parse(d.created_at) : NaN;
	if (!Number.isNaN(iso) && iso > 0) return iso;
	const fromId = epochFromId(id);
	if (fromId > 0) return fromId;
	return Date.now();
}

let fixed = 0;
let skipped = 0;
for (const coll of ['content_unified_files', 'dashboard_uploads']) {
	const snap = await fs.collection(coll).get();
	for (let i = 0; i < snap.docs.length; i += 200) {
		const batch = fs.batch();
		let inBatch = 0;
		for (const doc of snap.docs.slice(i, i + 200)) {
			const d = doc.data() || {};
			if (d.__provider !== 'internet_archive') continue;
			if (!isBrokenCreatedAt(d.createdAt)) {
				skipped += 1;
				continue;
			}
			const millis = resolveMillis(d, doc.id);
			batch.update(doc.ref, {
				createdAt: millis,
				created_at: new Date(millis).toISOString()
			});
			inBatch += 1;
			fixed += 1;
		}
		if (inBatch > 0) await batch.commit();
	}
}

console.log(`=== BACKFILL createdAt DONE ===  fixed=${fixed}  alreadyOk=${skipped}`);
await app.delete().catch(() => {});
