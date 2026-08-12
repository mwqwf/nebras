#!/usr/bin/env node
import { readFileSync } from 'node:fs';
import { initializeApp, cert } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

const sa = JSON.parse(readFileSync(process.env.GOOGLE_APPLICATION_CREDENTIALS, 'utf8'));
const app = initializeApp({ credential: cert(sa), projectId: sa.project_id });
const db = getFirestore(app);

console.log(`project: ${sa.project_id}`);
console.log(`testing default database...`);
try {
  const ref = db.collection('sections_unified').doc('main');
  const snap = await ref.get();
  console.log(`  ✅ default DB exists. doc.exists=${snap.exists}, fields=${snap.exists ? Object.keys(snap.data()).length : 0}`);
} catch (err) {
  console.log(`  ❌ default DB error: ${err?.code || ''} — ${err?.message || err}`);
}
