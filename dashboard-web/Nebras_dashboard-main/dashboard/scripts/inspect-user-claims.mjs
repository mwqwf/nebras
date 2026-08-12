#!/usr/bin/env node
/**
 * تشخيص: يطبع customClaims لأوّل مستخدم في dashboard_users في RTDB.
 * يُساعد على تأكيد ما إذا كان `role` claim مضبوطاً فعلاً على Firebase Auth.
 *
 * Usage:
 *   GOOGLE_APPLICATION_CREDENTIALS=... node scripts/inspect-user-claims.mjs
 */
import { readFileSync } from 'node:fs';
import { initializeApp, cert } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getDatabase } from 'firebase-admin/database';

const saPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
if (!saPath) {
  console.error('GOOGLE_APPLICATION_CREDENTIALS env var required');
  process.exit(1);
}
const sa = JSON.parse(readFileSync(saPath, 'utf8'));
initializeApp({
  credential: cert(sa),
  projectId: sa.project_id,
  databaseURL: `https://${sa.project_id}-default-rtdb.firebaseio.com`
});

const auth = getAuth();
const db = getDatabase();

const snap = await db.ref('dashboard_users').get();
if (!snap.exists()) {
  console.log('dashboard_users branch is empty.');
  process.exit(0);
}
const users = snap.val();
console.log(`Found ${Object.keys(users).length} dashboard user(s):\n`);

for (const [uid, record] of Object.entries(users)) {
  let u = null;
  let getUserErr = null;
  try {
    u = await auth.getUser(uid);
  } catch (err) {
    getUserErr = err;
  }
  console.log(`UID: ${uid}`);
  console.log(`  email = ${record?.email || u?.email || '(none)'}`);
  console.log(`  RTDB role = ${record?.role}`);
  console.log(`  RTDB isBlocked = ${record?.isBlocked}`);
  console.log(`  lastSignedInAt = ${record?.lastSignedInAt ? new Date(record.lastSignedInAt).toISOString() : 'n/a'}`);
  if (getUserErr) {
    console.log(`  Firebase Auth: ERROR ${getUserErr.code || ''} — ${getUserErr.message}`);
  } else {
    console.log(`  Firebase Auth emailVerified = ${u?.emailVerified}`);
    console.log(`  Firebase Auth customClaims = ${JSON.stringify(u?.customClaims || null)}`);
  }
  console.log('');
}

process.exit(0);
