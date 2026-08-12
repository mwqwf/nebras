# Nebras Mobile (nebras_mobile_app) — Claude Code Context (دليل شامل)

> هذا الملف يُحمَّل تلقائياً عند بدء كل جلسة. اقرأه أولاً قبل أي عمل،
> وتذكّر القواعد فيه طوال الجلسة. الهدف: **تقليل استهلاك التوكنز** بإعطائك
> كل ما تحتاجه دفعةً واحدة بدون ترداد المستخدم.

---

## 0. تفضيلات المستخدم (يجب احترامها دائماً)

### 0.1 اللغة
- **الردود دائماً بالعربية** حتى لو خاطبك المستخدم بالإنجليزية أو لصق رسالة خطأ بالإنجليزية.
- الكود (أسماء classes/methods، Dart syntax) يبقى بالإنجليزية.
- التعليقات داخل الكود: المشروع يستعمل تعليقات عربية مكثَّفة — تابع الأسلوب.

### 0.2 المثابرة
- كل طلب من المستخدم يجب أن تُنفّذه **بكل الطرق الممكنة** حتى تنجح.
- لا تتوقف عند أول فشل وتسأل "هل أكمل؟" — جرّب أداة أخرى، طريقاً التفافياً، صياغة بديلة.

### 0.3 خارج النطاق
- داخل النطاق → نفّذ مباشرة.
- **خارج** الطلب (تحسينات، إعادة هيكلة، حذف كود تظنّه ميتاً، إضافة ميزة جانبية) → **اعرضها أولاً** وانتظر الإذن.

### 0.4 الصلاحيات
- وضع `bypassPermissions` مُفعَّل في `C:\Users\slxc\Documents\GitHub\.claude\settings.local.json` — لن يطلب النظام إذناً لأي أداة.
- قبل أي أمر مدمّر (`flutter clean`, حذف `build/`, تعديل `key.properties`, `gradle clean`) اشرح ماذا ستفعل ثم نفّذ.
- لا تطبع محتوى `key.properties`, keystore passwords, أو محتوى `google-services.json` السرّي في الردّ.

---

## 1. ما هو المشروع

**Nebras Mobile** = تطبيق Flutter للمستخدم النهائي لمنصّة "نبراس" — منصّة محتوى موسوعي **معرفيّ عامّ** (ثقافة عامّة لا تقتصر على دين أو طائفة أو توجّه). التطبيق **قارئ فقط** للمحتوى الذي تُنتجه لوحة التحكم (`Nebras_dashboard-main/`).

ميزات رئيسية:
- تصفّح أقسام موسوعية (رئيسية/فرعية/ثانوية).
- قراءة كتب PDF مع حفظ آخر صفحة.
- تشغيل صوت في الخلفية مع إشعار دائم وأزرار تحكّم.
- تشغيل فيديو (YouTube + ملفات).
- تنزيل للمحتوى للعمل دون إنترنت.
- إشعارات FCM.
- مزامنة مفضّلات وحالة "تابع المشاهدة".
- تسجيل دخول Google (اختياريّ).

### 1.1 التقنيات
- **Flutter SDK ≥ 3.7.0** (يستعمل wildcard patterns `_` في closures).
- **Dart** (null-safety).
- **Provider** + **get_it** للحالة والـ DI.
- **Firebase**: `cloud_firestore`, `firebase_auth`, `firebase_messaging`, `firebase_storage`, `firebase_core`.
- **Hive** + `hive_flutter` للتخزين المحلي.
- **Dio** للـ HTTP.
- **just_audio** + `just_audio_background` + `audio_session` — الصوت.
- **video_player** + `youtube_player_flutter` + `floating` (PiP).
- **syncfusion_flutter_pdfviewer** — قارئ PDF.
- **go_router** — للتنقّل (تدريجيّ).
- **easy_localization** — الترجمة (عربي/فرنسي/إنجليزي).
- **flutter_screenutil** — responsive UI.
- **flutter_native_splash** — Splash.
- **flutter_local_notifications** — إشعارات محلية.
- **google_sign_in** — تسجيل Google.

### 1.2 معلومات الإصدار
- اسم الحزمة: **`com.nebras.mobile`** (Android + iOS).
- Version: انظر `version:` في `pubspec.yaml` (حالياً `1.0.4+8`).
- `compileSdk = 36`, `targetSdk = 35`, `minSdk = 23`.
- Firebase project ID: `nebras-9118c`.

### 1.3 قواعد صارمة (لا تُنتهك أبداً)
- ⛔ **التطبيق قارئ فقط** للمجموعات الموحَّدة من Firestore. لا يكتب فيها (إلا في مساحات خاصّة كـ tokens, saved items, behavior).
- ⛔ **ممنوع وضع أيّ سرّ في الـ assets** — يمكن استخراجها من الـ APK بـ `unzip`. ملف `.env` أُزيل من `pubspec.yaml > assets` عمداً.
- ⛔ القيم الحسّاسة تُمرَّر عبر `--dart-define` أو Firebase Remote Config.
- ⛔ ممنوع تفعيل أيّ ربط بـ `archive.org`, IslamHouse, Mshcat, OldApp. التطبيق يعتمد فقط على Firestore الذي تكتبه اللوحة.
- ⛔ **لا تُغيّر اسم الحزمة** من `com.nebras.mobile` — كسر سلسلة التوقيع يفصل المستخدمين الحاليين.
- ⚠️ `isMinifyEnabled = true` + `isShrinkResources = true` مُفعَّلان مع
  قواعد `proguard-rules.pro` الشاملة. لا تحذف قواعد `-keep` لنماذج
  Firebase/Firestore/Hive/`com.nebras.mobile.**` — حذفها يُعيد علّة
  اختفاء الأقسام في نسخة المتجر. اختبر بناء release على جهاز قبل الرفع.

---

## 2. خريطة المشروع (Layout)

```
archive_mobileapp-master/
├── pubspec.yaml                ★ التبعيات + إعدادات flutter_launcher_icons
├── pubspec.lock
├── analysis_options.yaml
├── devtools_options.yaml
├── native_splash.yaml
├── firebase.json               ← projectId + appIds
├── README.md
├── STORE_RELEASE.md            ★ دليل الإصدار للمتاجر (Play / App Store)
├── DASHBOARD_TODO.md           ← سجل قديم، قد لا يكون حديثاً
├── build-log.txt
├── live-log.txt
├── tools/
│   └── app_icon_master.png     ← أيقونة 1024×1024 master (للـ flutter_launcher_icons)
├── docs/                       ★ توثيق إضافي (راجع GOOGLE_SIGNIN_ANDROID.md)
├── assets/
│   ├── translations/           ← .json لكل لغة (easy_localization)
│   ├── images/
│   ├── videos/
│   └── lottie/
├── android/                    ← المشروع الأصلي Android
│   └── app/
│       ├── google-services.json        ⚠ حسّاس
│       ├── key.properties              ⚠ سرّي (gitignored)
│       └── src/main/
│           ├── AndroidManifest.xml
│           ├── kotlin/com/nebras/mobile/   ← MainActivity + Application class
│           └── res/
│               ├── values/, values-ar/, values-fr/   ← strings.xml للترجمات
│               ├── drawable/ic_stat_notify.xml        ← أيقونة الإشعار
│               └── mipmap-anydpi-v26/ic_launcher.xml ★ inset=25% للـ adaptive icon
├── ios/                        ← المشروع الأصلي iOS
│   └── Runner/
│       ├── Info.plist
│       └── GoogleService-Info.plist     ⚠ حسّاس
├── web/, windows/, linux/, macos/   ← Flutter desktop/web (غير منشورة عادةً)
├── test/                       ← Flutter tests (شبه فارغ)
├── build/                      ← ⛔ لا تقرأ
└── lib/                        ← 👑 الكود الفعلي
    ├── main.dart               ★ نقطة الدخول، تهيئة Firebase + Hive + DI + Providers
    ├── firebase_options.dart   ← يُولَّد بـ flutterfire configure
    ├── core/
    │   ├── config/                       ← remote_backend_config, إلخ
    │   ├── data/
    │   │   ├── content_ordering.dart            ★ ترتيب المحتوى داخل الأقسام (الأقدم أولاً)
    │   │   └── rtdb_upload_normalizer.dart      ★ تطبيع dashboard_uploads → JSON التطبيق
    │   ├── di/                           ← setup_locator.dart (get_it)
    │   ├── error/
    │   ├── extensions/
    │   ├── firebase/                     ← firestore_sync_config, إلخ
    │   ├── media/
    │   ├── network/                      ← dio_client, api_constants
    │   ├── providers/                    ← providers مشتركة (theme, sections_layout)
    │   ├── routing/                      ← notification_navigator
    │   ├── services/                     ← continue_watching, interest_profile, user_behavior_tracker
    │   ├── theme/                        ← apptheme + provider
    │   ├── utils/
    │   └── widgets/                      ← widgets مشتركة (auto_link_text, إلخ)
    └── features/                ★ كل ميزة منفصلة بـ Clean Architecture خفيف
        ├── splash/              ← splash_screen.dart
        ├── auth/                ← Google Sign-In
        ├── home/
        │   ├── HOME_RAILS_ARCHITECTURE.md   ★ يشرح بنية الـ rails
        │   ├── data/
        │   ├── domain/
        │   ├── model/
        │   ├── providers/
        │   ├── services/
        │   └── view/
        ├── search/
        ├── content/             ← Content model + cache + view
        │   ├── cache/                     ← content_metadata_cache
        │   ├── model/                     ★ content_model.dart (المصدر الأهم)
        │   └── view/
        ├── reader/              ← PDF reader + حفظ آخر صفحة
        ├── audio_player/        ← مشغّل الصوت
        ├── video_player/        ← فيديو + YouTube + PiP
        ├── download/            ← تنزيل للعمل دون إنترنت
        ├── notifications/       ← FCM + notifications محلية + datasource
        ├── saved/               ← المفضّلة
        └── splash/
```

---

## 3. أوامر التشغيل

كل الأوامر من **جذر مجلد التطبيق** (`archive_mobileapp-master/`):

```bash
# جلب التبعيات
flutter pub get

# قائمة الأجهزة المتاحة
flutter devices

# تشغيل (يلتقط أوّل جهاز متاح)
flutter run

# تشغيل على جهاز محدّد
flutter run -d <deviceId>

# مع dart-define لتجاوز baseUrl
flutter run --dart-define=NEBRAS_API_BASE_URL=https://example.com

# تنظيف (يحذف build/ و .dart_tool/)
flutter clean

# اختبارات (شبه فارغ)
flutter test

# تحليل ثابت
flutter analyze

# توليد الأيقونات (يكتب فوق inset adaptive icon — انتبه)
dart run flutter_launcher_icons

# توليد Hive adapters
dart run build_runner build --delete-conflicting-outputs

# بناء AAB للنشر
flutter build appbundle --release

# بناء APK
flutter build apk --release --split-per-abi

# بناء iOS
flutter build ipa --release
```

### 3.1 ADB سريعة
```bash
adb devices
adb logcat -s flutter
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

### 3.2 قائمة فحص الإصدار
- راجع **`STORE_RELEASE.md`** قبل أي رفع للمتجر — فيه تفاصيل توقيع + Google Sign-In + إعادة توليد `google-services.json`.
- راجع **`docs/GOOGLE_SIGNIN_ANDROID.md`** لو هناك مشاكل `ApiException 10`.

---

## 4. عقد البيانات (Firestore — مشترك مع اللوحة)

### 4.1 المجموعات التي يقرأها التطبيق
| Collection | الشكل | يستعمله |
|---|---|---|
| `sections_unified` | 3 مستندات: `main`, `sub`, `secondary`. كلّ مستند `{id → record}` | `lib/features/home/`, `lib/features/search/` |
| `content_unified_files` | rows لملفات (PDF/audio/video) | `lib/features/home/`, `lib/features/search/`, `lib/features/content/` |
| `dashboard_uploads` | مرآة موازية، تُدمج عند القراءة | عبر `rtdb_upload_normalizer.dart` |
| `content_unified_youtube` | فيديوهات YouTube (`content_type: "youtube"`) | نفس الميزات |

### 4.2 مجموعات يكتب فيها التطبيق (مساحاته الخاصّة فقط)
- `users/{uid}/fcm_tokens`
- `users/{uid}/saved_items`
- `users/{uid}/last_pages` (آخر صفحة PDF)
- مجموعات Behavior tracker (انظر `core/services/user_behavior_tracker.dart`).

### 4.3 نموذج البيانات الرئيسي
- **`lib/features/content/model/content_model.dart`** = مصدر الحقيقة لتحويل document → كائن Dart.
- **`lib/core/data/rtdb_upload_normalizer.dart`** = يدمج `dashboard_uploads` مع `content_unified_files`.
- **`lib/core/data/content_ordering.dart`** = ترتيب المحتوى داخل قسم (الأقدم أولاً).

---

## 5. ملفّات تحتاج فتحها حسب المهمة

عند العمل على... | افتح هذه الملفات
---|---
نموذج محتوى أو إضافة حقل | `lib/features/content/model/content_model.dart`
دمج dashboard_uploads | `lib/core/data/rtdb_upload_normalizer.dart`
ترتيب المحتوى | `lib/core/data/content_ordering.dart`
شاشة الرئيسية + rails | `lib/features/home/` (راجع `HOME_RAILS_ARCHITECTURE.md`)
البحث | `lib/features/search/`
قارئ PDF | `lib/features/reader/`
الصوت في الخلفية | `lib/features/audio_player/`, `lib/main.dart` (init JustAudioBackground)
فيديو + PiP | `lib/features/video_player/`
التنزيل | `lib/features/download/`
الإشعارات FCM | `lib/features/notifications/`, `lib/main.dart` (background handler)
المفضّلة | `lib/features/saved/`
السمات (Dark/Light) | `lib/core/theme/apptheme.dart`, `lib/core/theme/provider/theme_provider.dart`
الترجمة | `assets/translations/`, `lib/main.dart` (easy_localization init)
الراوتر | `lib/core/routing/notification_navigator.dart`
DI | `lib/core/di/setup_locator.dart`
Dio + baseUrl | `lib/core/network/dio_client.dart`, `lib/core/network/api_constants.dart`
Firestore sync settings | `lib/core/firebase/firestore_sync_config.dart`
Splash | `lib/features/splash/splash_screen.dart`
Google Sign-In | `lib/features/auth/`, `docs/GOOGLE_SIGNIN_ANDROID.md`

---

## 6. أنماط وقواعد كتابة

### 6.1 معمارية
- **Clean Architecture مبسَّطة لكل ميزة**: `data/`, `domain/`, `model/`, `provider/`, `view/`, `service/`, `usecase/`.
- **State** عبر Provider (وليس BLoC/Riverpod).
- **DI** عبر `get_it` في `lib/core/di/setup_locator.dart`.
- **Navigation**: مزيج من Navigator القديم و `go_router` (تدريجيّ).

### 6.2 Dart
- Null safety كاملة.
- **Wildcard patterns** `(_, _) => ...` مستعملة — لذلك Dart SDK ≥ 3.7.0 إلزامي.
- **Hive adapters**: تُولَّد بـ `build_runner`. لا تعدّل `*.g.dart` يدوياً.

### 6.3 Performance
- **`CachedNetworkImage` دائماً مع `memCacheWidth/Height`** = (logical × `devicePixelRatio`). نسيان هذا يسبّب OOM على أجهزة 2GB.
- **`Hive.openBox` دائماً ضمن try-catch** مع fallback إلى `deleteBoxFromDisk` ثم re-open فارغ (يمنع تعطيل الإقلاع على ملفّ تالف).
- **خدمات الإقلاع المؤجَّلة** في `_warmUpDeferredServices()` تعمل بالتوازي مع UI — لا تُضف خدمات ثقيلة قبل `runApp`.
- استثناء: `JustAudioBackground.init` **يجب** أن يبقى قبل `runApp` (متطلَّب المكتبة).

### 6.4 Logging
- استعمل `debugPrint` لا `print` (يُخفَّف في الإنتاج).
- لا تطبع PII أو tokens.

### 6.5 الترجمة
- مفاتيح الترجمة في `assets/translations/{ar,en,fr}.json`.
- استعمال: `'key'.tr()` (من easy_localization).
- النصوص النظاميّة لـ Android في `android/app/src/main/res/values{,-ar,-fr}/strings.xml` (مهمّ لاسم التطبيق).

---

## 7. توفير التوكنز (مهم جداً)

1. **اقرأ هذا الملف أولاً** — يحوي 90% مما تحتاجه. لا تستكشف البنية بـ `ls` متعدّد.
2. **لا تقرأ أبداً**:
   - `build/**` (مخرجات بناء — ضخمة)
   - `.dart_tool/**`
   - `android/.gradle/**`, `android/build/**`
   - `ios/Pods/**`, `ios/.symlinks/**`
   - `linux/`, `macos/`, `windows/`, `web/` (إلا لو طُلب صراحة)
   - `.claude/worktrees/**` (نسخ مكرّرة من جلسات سابقة)
   - `pubspec.lock` (إلا لو سُئلت عن نزاع تبعيات)
   - `*.g.dart` (مولَّد) — اقرأ المصدر بدلاً منه
   - `build-log.txt`, `live-log.txt` (سجلات بناء قديمة)
3. **استعمل Grep قبل Read** — لو تبحث عن class أو method.
4. **استعمل Glob قبل find**.
5. **اقرأ ملفّات كبيرة (`main.dart` فيها 500+ سطر) بـ `limit` و `offset`**.
6. **لا تشغّل `flutter pub get` أو `flutter build` افتراضياً** — فقط إذا طُلب اختبار عملي.
7. **استعمل subagent `Explore`** للأسئلة الاستكشافية الواسعة فقط.
8. **اختصر الردود**: جمل قصيرة، لا مقدّمات، لا خواتم تكرّر ما فعلت.

### 7.1 ملفّات يستحقّ تخزينها في الذاكرة عند القراءة الأولى
- `lib/features/content/model/content_model.dart` — schema الكائن الأساسي.
- `lib/core/data/rtdb_upload_normalizer.dart` — منطق دمج التحميلات.
- `lib/main.dart` (الأجزاء العليا) — ترتيب التهيئة.

---

## 8. أمان ومعلومات حسّاسة

- 🚫 **لا تطبع** في الردّ: `key.properties`, keystore passwords, محتوى `google-services.json` الكامل، `GoogleService-Info.plist`، أي tokens.
- 🚫 لا تضع أسراراً في الـ assets (يمكن استخراجها من APK).
- ✅ استعمل `--dart-define` للقيم الحسّاسة وقت البناء.
- 🚫 لا تُغيّر اسم الحزمة `com.nebras.mobile`.
- ⚠️ `isMinifyEnabled` مُفعَّل مع قواعد keep شاملة في `proguard-rules.pro` — لا تحذف قواعد keep لنماذج Firebase/Hive.
- 🚫 لا ترفع build إلى المتجر بدون اتّباع `STORE_RELEASE.md`.
- ✅ قبل `flutter clean` اشرح ماذا ستفعل (يحذف cache + build).

---

## 9. مهام متكرّرة (قوالب جاهزة)

### 9.1 إضافة حقل جديد إلى Content model
1. عدّل `lib/features/content/model/content_model.dart` (أضف الحقل + `fromJson` + `toJson`).
2. عدّل `lib/core/data/rtdb_upload_normalizer.dart` لو الحقل يأتي من dashboard_uploads.
3. عدّل `lib/features/content/cache/content_metadata_cache.dart` لو نحتاج caching.
4. أضف الحقل في `Content.fromJson` بطريقة آمنة (default value لو غائب).
5. أبلغ المستخدم أن اللوحة تحتاج تحديث `nebrasMobileUploadSchema.js` أيضاً.

### 9.2 إضافة شاشة جديدة
1. أنشئ مجلد ميزة في `lib/features/<feature>/` بنفس البنية: `data/`, `domain/`, `model/`, `provider/`, `view/`.
2. سجّل dependencies في `lib/core/di/setup_locator.dart`.
3. سجّل provider في `lib/main.dart` ضمن `MultiProvider`.
4. أضف الترجمات إلى `assets/translations/*.json`.
5. ربط navigation عبر Navigator أو go_router.

### 9.3 إضافة حقل ترجمة
1. أضف المفتاح في `assets/translations/ar.json`, `en.json`, `fr.json`.
2. استعمل `'key.path'.tr()` في UI.
3. لا حاجة إلى hot restart — `easy_localization` يدعم hot reload.

### 9.4 تحديث أيقونة التطبيق
1. ضع النسخة 1024×1024 في `tools/app_icon_master.png`.
2. `dart run flutter_launcher_icons`.
3. **أعد** كتابة `<inset android:inset="25%" />` في `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml` (الأمر يكتب فوقه).

### 9.5 رفع نسخة جديدة للمتجر
- اقرأ `STORE_RELEASE.md` كاملاً قبل البدء.
- زِد `version: X.Y.Z+N` في `pubspec.yaml`.
- لا تشغّل أوامر النشر بدون إذن صريح من المستخدم.

---

## 10. التعامل مع worktrees و ملفّات السجلّ

- مجلد `.claude/worktrees/` يحوي **نسخ مكرّرة** من المشروع لجلسات سابقة. **تجاهلها** — لا تقرأ، لا تعدّل.
- `build-log.txt`, `live-log.txt` = سجلّات بناء قديمة، تجاهلها إلا لو طُلب التحقّق منها.
- `DASHBOARD_TODO.md` = قائمة مهام تاريخيّة قد تكون ناقصة، لا تعتمد عليها بدون التحقّق.

---

## 11. ملخّص قراءة سريع (TL;DR)

- **العربية افتراضياً** • **استمرّ حتى التنفيذ** • **خارج النطاق اعرضه أولاً**.
- التطبيق **قارئ فقط** لمجموعات Firestore التي تكتبها اللوحة.
- `flutter pub get` ثم `flutter run` من جذر مجلد التطبيق.
- الاسم: `com.nebras.mobile` — لا تُغيّره.
- نموذج البيانات الأهم: `lib/features/content/model/content_model.dart`.
- التهيئة في `lib/main.dart` — JustAudioBackground قبل runApp، الباقي مؤجَّل.
- لا أسرار في assets. استعمل `--dart-define`.
- توفير التوكنز: لا تقرأ `build/`, `.dart_tool/`, `Pods/`, `worktrees/`، استعمل Grep قبل Read، اختصر الردود.
- قبل أي إصدار للمتجر: راجع `STORE_RELEASE.md`.
