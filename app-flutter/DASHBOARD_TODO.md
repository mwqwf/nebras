# لوحة التحكّم — مهام تكامل الرفوف والشعبيّة

مرجع التطبيق: `docs/CONTENT_ORDERING_AND_HOME.md` و `lib/features/home/HOME_RAILS_ARCHITECTURE.md`.

---

## 🔴 حرجة

### 1. قواعد Firestore — عدّادات المشاهدة

**الحالة:** مُنفَّذة في `Nebras_dashboard-main/dashboard/firestore.rules` — انشرها:

```bash
cd Nebras_dashboard-main/dashboard
firebase deploy --only firestore:rules
```

تسمح للمستخدم العاديّ بـ `update` على `view_count`, `play_count`, `complete_count`, `last_played_at` فقط (merge + increment).

`aggregates_popular/{docId}`: قراءة عامّة، كتابة عبر Admin SDK فقط.

### 2. تجميع أسبوعي — `aggregates_popular/top_weekly`

**الحالة:** API جاهز — `POST /api/admin/aggregates/popularity` (مشرف/مالك).

```bash
# بعد تسجيل الدخول للوحة (جلسة مشرف)
curl -X POST https://YOUR_DASHBOARD_HOST/api/admin/aggregates/popularity \
  -H "Cookie: ..." \
  -H "Content-Type: application/json" \
  -d '{"limit": 50}'
```

**الحالة:** جدولة Vercel Cron — `GET /api/cron/aggregates-popularity` (يتطلّب `CRON_SECRET` على Vercel). يدويّاً: نفس `POST` أعلاه. الكود: `src/lib/server/aggregatePopularity.js`.

---

## 🟡 متوسّطة

| # | المهمّة | الملاحظات |
|---|---------|-----------|
| 3 | شارات `👁 view · ▶ play · ✓ complete` بجانب كلّ ملفّ في واجهة المحتوى | **مُنفَّذ** — `EngagementBadge.svelte` في قوائم الملفّات/يوتيوب |
| 4 | سحب لإعادة ترتيب `selectionOrder` داخل القسم | يكتب على `content_unified_*` |

---

## 🟢 منخفضة

| # | المهمّة |
|---|---------|
| 5 | صفحة Analytics (أكثر مشاهدة/تشغيل) |
| 6 | `config/home_rails` لتفعيل/ترتيب الرفوف من Firestore |

---

## التحقّق من التكامل

1. افتح محتوى من التطبيق → `view_count` يزيد في `content_unified_files` أو `content_unified_youtube`.
2. شغّل >25% → `play_count: 1`.
3. نفّذ POST التجميع → تحقّق من `aggregates_popular/top_weekly` (`ids`, `scores`).
4. اسحب الصفحة الرئيسيّة → رفّ «الأكثر مشاهدة» يعرض المحتوى المُجمَّع.

---

## حقول Firestore المتوقّعة على المحتوى

```
view_count, play_count, complete_count, last_played_at
popularity_score_7d, popularity_score_30d  // اختياري — التجميع يحسب من العدّادات
```

مستند التجميع:

```
aggregates_popular/top_weekly
  ids: string[]
  scores: { [id]: number }
  updatedAt: timestamp
```
