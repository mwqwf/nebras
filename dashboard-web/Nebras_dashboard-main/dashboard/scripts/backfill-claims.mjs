#!/usr/bin/env node
/**
 * Backfill: لكلّ مستخدم في `dashboard_users` يضبط Custom Claim `role`
 * مطابقاً لقيمة الـ RTDB (`role`) إن لم يكن مضبوطاً مسبقاً. يُصلِح حالة
 * المشرفين/المالكين الذين سُجّلوا قبل تفعيل مزامنة الـ claims.
 */
import { readFileSync } from 'node:fs';
import { initializeApp, cert } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getDatabase } from 'firebase-admin/database';

const sa = JSON.parse(readFileSync(process.env.GOOGLE_APPLICATION_CREDENTIALS, 'utf8'));
initializeApp({
  credential: cert(sa),
  projectId: sa.project_id,
  databaseURL: `https://${sa.project_id}-default-rtdb.firebaseio.com`
});

const snap = await getDatabase().ref('dashboard_users').get();
if (!snap.exists()) {
  console.log('No dashboard users.');
  process.exit(0);
}

let synced = 0, skipped = 0, errors = 0;
for (const [uid, record] of Object.entries(snap.val() || {})) {
  if (record?.isBlocked === true) {
    skipped++;
    continue;
  }
  const rawRole = record?.role === 'admin' ? 'supervisor' : record?.role;
  if (rawRole !== 'owner' && rawRole !== 'supervisor') {
    skipped++;
    continue;
  }
  try {
    const user = await getAuth().getUser(uid);
    const current = user.customClaims?.role;
    if (current === rawRole) {
      skipped++;
      continue;
    }
    await getAuth().setCustomUserClaims(uid, { role: rawRole });
    console.log(`  ✅ synced ${uid.slice(0, 6)}… → role=${rawRole} (was ${current || 'none'})`);
    synced++;
  } catch (err) {
    console.log(`  ❌ ${uid.slice(0, 6)}… ${err.code || err.message}`);
    errors++;
  }
}
console.log(`\nSummary: synced=${synced}, skipped=${skipped}, errors=${errors}`);
