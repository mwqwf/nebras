#!/usr/bin/env node
/* تشخيص مؤقّت (read-only) لمحرّك الأرشيف — يُحذف بعد الاستعمال. */
import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { getDatabase } from 'firebase-admin/database';
import { resolveServiceAccount } from './load-admin-credential.mjs';

const { credentials } = resolveServiceAccount();
const dbUrl = process.env.FIREBASE_DATABASE_URL || process.env.NEBRAS_DATABASE_URL;
const app = initializeApp({ credential: cert(credentials), projectId: credentials.project_id, databaseURL: dbUrl });
const fs = getFirestore(app, process.env.NEBRAS_FIRESTORE_DATABASE_ID || 'default');
const rtdb = getDatabase(app);

function J(x) { return JSON.stringify(x, null, 2); }

async function rt(path) {
  const s = await rtdb.ref(path).get();
  return s.exists() ? s.val() : null;
}

console.log('=== STATS ===');
console.log(J(await rt('ia_library_engine/stats')));
console.log('=== CURSOR ===');
console.log(J(await rt('ia_library_engine/cursor')));

console.log('=== LOG (recent 30, level+reason+msg) ===');
const log = (await rt('ia_library_engine/log')) || {};
const entries = Object.values(log).sort((a, b) => Number(b?.ts || 0) - Number(a?.ts || 0)).slice(0, 30);
for (const e of entries) console.log(`[${e.level}] ${e.reason || ''} | ${(e.message || '').slice(0, 160)}`);

console.log('=== FAILURES (reason counts) ===');
const fails = (await rt('ia_library_failures')) || {};
const reasonCount = {};
for (const f of Object.values(fails)) { const r = f?.lastReason || 'unknown'; reasonCount[r] = (reasonCount[r] || 0) + 1; }
console.log(J(reasonCount));

console.log('=== REGISTRY (count + byType) ===');
const reg = (await rt('ia_library_registry')) || {};
const regVals = Object.values(reg);
const byType = {};
const bySection = {};
for (const r of regVals) {
  byType[r?.nebrasContentType || '?'] = (byType[r?.nebrasContentType || '?'] || 0) + 1;
  const m = r?.hierarchy?.mainId || '?';
  bySection[m] = (bySection[m] || 0) + 1;
}
console.log(`registry total=${regVals.length} byType=${J(byType)}`);

console.log('=== SECTIONS (counts + IA-created + EMPTY) ===');
const [mainDoc, subDoc, secDoc, filesSnap, ytSnap] = await Promise.all([
  fs.collection('sections_unified').doc('main').get(),
  fs.collection('sections_unified').doc('sub').get(),
  fs.collection('sections_unified').doc('secondary').get(),
  fs.collection('content_unified_files').get(),
  fs.collection('content_unified_youtube').get()
]);
const mains = mainDoc.exists ? mainDoc.data() : {};
const subs = subDoc.exists ? subDoc.data() : {};
const secs = secDoc.exists ? secDoc.data() : {};
console.log(`main=${Object.keys(mains).length} sub=${Object.keys(subs).length} secondary=${Object.keys(secs).length}`);

// عدّ المحتوى لكل subsection لاكتشاف الأقسام الفارغة
const contentBySub = {};
const iaContent = [];
const urlIssues = [];
function pick(d) {
  const f = ['file_url','sourceUrl','source_url','audio_url','video_url','downloadUrl'];
  for (const k of f) if (typeof d?.[k] === 'string' && d[k].length > 8) return d[k];
  const m = d?.metadata || {};
  for (const k of f) if (typeof m?.[k] === 'string' && m[k].length > 8) return m[k];
  return '';
}
for (const doc of filesSnap.docs) {
  const d = doc.data() || {};
  const sub = String(d.subsection ?? d.metadata?.subsection ?? '');
  contentBySub[sub] = (contentBySub[sub] || 0) + 1;
  const isIa = d.__provider === 'internet_archive';
  const url = pick(d);
  if (isIa) iaContent.push({ id: doc.id, ct: d.content_type || d.metadata?.content_type, url: url.slice(0, 60) });
  if (!url || !/^https?:\/\//.test(url) || url.includes('archive.org') || !url.includes('firebasestorage')) {
    if (urlIssues.length < 20) urlIssues.push({ id: doc.id, ct: d.content_type || d.metadata?.content_type, provider: d.__provider || 'manual', url: url.slice(0, 70) });
  }
}
console.log(`content_files=${filesSnap.size} youtube=${ytSnap.size} ia_content=${iaContent.length}`);

// أقسام فرعية فارغة (لا محتوى)
const emptySubs = Object.keys(subs).filter((id) => !contentBySub[id]);
const iaEmptySubs = emptySubs.filter((id) => subs[id]?.__createdBy === 'ia_library_engine');
console.log(`EMPTY subs=${emptySubs.length} (of which IA-created=${iaEmptySubs.length})`);
console.log('sample IA empty subs:', J(iaEmptySubs.slice(0, 10).map((id) => ({ id, name: subs[id]?.name }))));

console.log('=== URL ISSUES (non-storage / archive / bad) ===');
console.log(`count=${urlIssues.length}`);
console.log(J(urlIssues));

console.log('=== IA content content_type sample ===');
console.log(J(iaContent.slice(0, 10)));

await app.delete().catch(() => {});
