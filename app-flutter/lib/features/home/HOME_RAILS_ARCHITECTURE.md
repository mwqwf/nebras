# معمارية رفوف الصفحة الرئيسيّة (Home Rails)

## 1. القاعدة الذهبيّة

**داخل الأقسام** (فرعي / ثانوي / قائمة قسم): **الأقدم أولاً** — راجع `lib/core/data/content_ordering.dart`.

**على الصفحة الرئيسيّة** (الرفوف الأفقيّة): ترتيب اكتشاف مختلف (أحدث، شعبي، مخصّص) — لا يغيّر ترتيب عناصر القسم عند الدخول إليه.

---

## 2. أنواع الرفوف

| النوع | الملف | المصدر |
|--------|--------|--------|
| `newest` | `home_rail_builders.dart` | `createdAt` تنازلي، 12 عنصر |
| `popular` | + `popularity_feed_service.dart` | `aggregates_popular/top_weekly` ثم `view_count` |
| `forYou` | + `recommendation_service.dart` | ملفّ اهتمام + cold-start 50/50 |
| `searchAffinity` | + `interest_profile_service.dart` | كلمات بحث محلية |
| `continueWatching` | `continue_watching_service.dart` | SharedPreferences فقط |
| `browseSections` | `home_provider._rankSections` | أقسام رئيسية مرتّبة ذكياً |

النموذج: `lib/features/home/model/home_rail.dart`  
التجميع: `HomeProvider._rebuildHomeRails` → `HomeRailBuilders.buildAll`  
الواجهة: `lib/features/home/view/widgets/home_rails_sliver.dart`  
«اعرض الكلّ»: `lib/features/home/view/rail_view_all_screen.dart`

---

## 3. الإشارات والخصوصيّة

| الإشارة | التخزين | الاستخدام |
|---------|---------|-----------|
| زيارة قسم / bounce | `UserBehaviorTracker` | `_rankSections` (decay + عقوبة خروج سريع) |
| ملفّ اهتمام | `InterestProfileService` | «مقترَح لك»، بحث، ترتيب |
| تابع التصفّح | `ContinueWatchingService` | رفّ التقدّم المحلي |
| مشاهدة/تشغيل | `ContentEngagementService` → Firestore | `view_count`، `play_count`، `complete_count` — **بدون UID** |

**نسيان اهتماماتي / تسجيل الخروج:** `PersonalizationResetService.forgetAllLocalSignals()` — لا يمسّ عدّادات الخادم.

---

## 4. ترتيب الأقسام الذكي (`_rankSections`)

- تعزيز أقسام عربية/إسلامية خفيف.
- `visitBoost` × `visitDecayMultiplier` (>30 يوم ⇒ تقليل).
- `quickExitPenalty` بعد 5 زيارات <2 ثانية.
- كلمات مفتاحية من عنوان القسم.

---

## 5. لوحة التحكّم

راجع [`DASHBOARD_TODO.md`](../../../DASHBOARD_TODO.md) في جذر مستودع التطبيق: قواعد Firestore، تجميع أسبوعي، شارات عدّادات.

---

## 6. اختبارات

- `test/content_ordering_test.dart` — الأقدم أولاً داخل القسم.
- `test/home_rails_test.dart` — بناة الرفوف.
- `test/continue_watching_service_test.dart` — تقدّم محلي.

---

## 7. Checklist قبل تعديل الترتيب

- [ ] هل التعديل يمسّ **داخل قسم**؟ استخدم `content_ordering.dart` فقط.
- [ ] هل التعديل يمسّ **الصفحة الرئيسيّة**؟ عدّل `home_rail_builders.dart` / `HomeProvider`.
- [ ] هل أضفت حقلاً على Firestore؟ حدّث القواعد في اللوحة + `Content.fromJson`.
- [ ] شغّل `flutter test test/content_ordering_test.dart test/home_rails_test.dart test/continue_watching_service_test.dart`.
