# تكامل الرفوف والشعبيّة — لوحة التحكّم

النسخة الكاملة مع سياق التطبيق: مستودع `archive_mobileapp-master` → `DASHBOARD_TODO.md`.

---

## منفّذ في هذا المستودع

| المهمّة | الملفّ / المسار |
|---------|----------------|
| قواعد Firestore (`view_count`، `aggregates_popular`) | `firestore.rules` |
| تجميع أسبوعي (يدوي) | `POST /api/admin/aggregates/popularity` → `src/lib/server/aggregatePopularity.js` |
| جدولة يومية (Vercel Cron) | `GET /api/cron/aggregates-popularity` + `vercel.json` → `crons` |
| شارات عدّادات في قوائم المحتوى | `EngagementBadge.svelte` — صفحات الملفّات ويوتيوب |

---

## مطلوب منك بعد النشر

1. **نشر القواعد**

```bash
cd Nebras_dashboard-main/dashboard
firebase deploy --only firestore:rules
```

2. **متغيّر `CRON_SECRET` على Vercel**  
   أنشئ سرّاً عشوائياً طويلاً وأضفه في إعدادات المشروع. Vercel يمرّره تلقائياً كـ `Authorization: Bearer …` لمسار الـ cron.

3. **تحقّق يدويّ (اختياري)**

```bash
curl -X GET "https://YOUR_HOST/api/cron/aggregates-popularity" \
  -H "Authorization: Bearer YOUR_CRON_SECRET"
```

أوّل تشغيل بعد نشر القواعد: افتح محتوى من التطبيق ثم نفّذ الـ cron وتحقّق من `aggregates_popular/top_weekly`.

---

## 🟡 لم يُنفَّذ بعد (اختياري)

| # | المهمّة | ملاحظة |
|---|---------|--------|
| 4 | سحب لإعادة `selectionOrder` **داخل قسم منشور** | الرفع المتعدّد يدعم السحب قبل الرفع فقط (`multi/+page.svelte`) |
| 5 | صفحة Analytics | — |
| 6 | `config/home_rails` من Firestore | — |

---

## التحقّق من التكامل

1. افتح محتوى من التطبيق → `view_count` يزيد.
2. شغّل >25% → `play_count: 1`.
3. نفّذ cron أو POST التجميع → `aggregates_popular/top_weekly`.
4. الصفحة الرئيسيّة في التطبيق → رفّ «الأكثر مشاهدة».
