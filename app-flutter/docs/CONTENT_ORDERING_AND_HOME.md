# ترتيب المحتوى والصفحة الرئيسيّة — مرجع المطوّر

## 1. داخل الأقسام (فرعي / ثانوي / قائمة قسم)

**القاعدة الثابتة:** الأقدم أولاً، الأحدث في الأسفل.

| الأولوية | الحقل | الاتجاه |
|----------|--------|---------|
| 1 | `createdAt` | تصاعدي |
| 2 | `selectionOrder` | تصاعدي (عند تساوي التاريخ — دفعات الرفع المتعدد من اللوحة) |
| 3 | `fb_<epoch>` في المعرّف | تصاعدي |
| 4 | `id` نصّي | تصاعدي |

**التنفيذ:** `lib/core/data/content_ordering.dart` — `compareContentOldestFirst` / `sortContentOldestFirst`.

**أين يُطبَّق:**
- `HomeDatasource` — `bySub`, `bySecondary`, `mainItems`
- `SearchDatasource.getSectionContent`
- `ContentListScreen`, `content_metadata_cache`

**اختبارات:** `test/content_ordering_test.dart`

**لوحة التحكّم:** عند الرفع المتعدد يُكتب `selectionOrder` من ترتيب الطابور (`multi/+page.svelte`). إعادة ترتيب يدوي لمحتوى منشور = تعديل الحقل على المستند.

---

## 2. الصفحة الرئيسيّة — نموذج الرفوف (Rails)

الرفوف **ليست** أقسام Firestore. تُبنى في `HomeProvider.homeRails` عبر `lib/features/home/services/home_rail_builders.dart`.

| الترتيب | الرفّ | المصدر | الظهور |
|---------|-------|--------|--------|
| 1 | الجديد في نبراس | كل المحتوى، `createdAt` ↓، 12 عنصر | دائم |
| 2 | الأكثر مشاهدة | `aggregates_popular/top_weekly` أو `view_count` | دائم |
| 3 | مقترَح لك | `RecommendationService.rank` | بعد إشارة اهتمام |
| 4 | من اهتماماتك في البحث | `InterestProfileService.topKeywords` | بعد بحث/اهتمام |
| 5 | تابع التصفّح | `ContinueWatchingService` (SharedPreferences) | عند وجود تقدّم |
| 6 | تصفّح الأقسام | `HomeProvider.sections` (ترتيب ذكي) | دائم |

**Cold start:** عند غياب إشارات الاهتمام، `RecommendationService` يُرجع مزيج 50% أحدث + 50% شعبي — لا صفحة فارغة.

---

## 3. الشعبيّة (Firestore)

حقول على `content_unified_files` / `content_unified_youtube` (مرآة `dashboard_uploads` للملفات):

- `view_count`, `play_count`, `complete_count`, `last_played_at`
- `popularity_score_7d`, `popularity_score_30d`

**التطبيق:** `ContentEngagementService` — `FieldValue.increment` مع debounce (دقيقة/عنصر).

**التجميع:** مستند `aggregates_popular/top_weekly` — يُحدَّث من لوحة التحكّم:
`POST /api/admin/aggregates/popularity` (Admin SDK).

**القراءة:** `PopularityFeedService` — كاش 6 ساعات محلّي.

---

## 4. الخصوصيّة

- ملفّ الاهتمامات والسلوك و«تابع التصفّح»: **محليّ فقط** (`SharedPreferences`).
- عدّادات المشاهدة: **بدون UID** — مجهولة على Firestore.
- **نسيان اهتماماتي** (الإعدادات): `PersonalizationResetService.forgetAllLocalSignals()` — يمسح الاهتمامات والسلوك والمتابعة المحليّة دون المساس بعدّادات الخادم.
- عند `signOut`: نفس المسح عبر `PersonalizationResetService`.

راجع أيضاً: [lib/features/home/HOME_RAILS_ARCHITECTURE.md](../lib/features/home/HOME_RAILS_ARCHITECTURE.md) و [DASHBOARD_TODO.md](DASHBOARD_TODO.md).

---

## 5. ما لا يُغيَّر

- ترتيب **شريط الأقسام الذكي** في `HomeProvider._rankSections` منفصل عن ترتيب **عناصر داخل القسم** (الأقدم أولاً دائماً).
