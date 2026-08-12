# دليل إصدار نبراس للمتاجر (Play Store / App Store)

> مرجع تشغيليّ موجَّه للإصدار. الكود مُعدّ بالفعل لتطبيق كلّ ما هنا، لكنّ
> بعض الخطوات تتطلّب الوصول إلى Firebase Console / Play Console / Apple
> Developer Portal ولا يمكن أتمتتها داخل المستودع.

---

## ✅ الإصلاحات المُطبَّقة في الكود

- اسم الحزمة على Android و iOS أصبح `com.nebras.mobile`
  (لم تعد `com.example.*` المرفوضة من المتجرَين).
- مجلد Kotlin أُعيد تسميته إلى `android/app/src/main/kotlin/com/nebras/mobile/`.
- `applicationId` و `namespace` و `PRODUCT_BUNDLE_IDENTIFIER` كلّها مُحدَّثة.
- `compileSdk = 35`, `targetSdk = 35`, `minSdk = 23` مُثبَّتة صراحةً.
- R8 + تصغير الموارد مُفعَّلان (`isMinifyEnabled = true` +
  `isShrinkResources = true`) **مع** ملفّ `android/app/proguard-rules.pro`
  يحوي قواعد `-keep` شاملة لكلّ ما يعتمد على الانعكاس (Firebase/Firestore،
  gRPC/Protobuf، Hive adapters، نماذج `com.nebras.mobile.**`، just_audio،
  Syncfusion، gson…). الانهيار القديم (اختفاء الأقسام في نسخة المتجر) كان
  بسبب تصغير بلا قواعد keep — لا بسبب التصغير نفسه. **إلزاميّ** اختبار
  بناء `--release` على جهاز فعليّ والتأكّد من ظهور كلّ المحتوى قبل الرفع.
- توقيع الإصدار يعتمد `key.properties` (مُهمَل عن git) ويرجع إلى debug
  فقط عند غياب الملف لتطوير سلس.
- `RECEIVE_BOOT_COMPLETED` غير المستخدم أُزيل من `AndroidManifest.xml`.
- `taskAffinity=""` أُزيل لإصلاح سلوك Deep Links من إشعارات FCM.
- `android:label="نبراس"` نُقل إلى `@string/app_name` مع ترجمات
  (`values/`, `values-ar/`, `values-fr/`).
- أيقونة الإشعار الافتراضيّة صارت `ic_stat_notify.xml` أحاديّة اللون
  (silhouette أبيض) كما يفرض Android ≥ 5.0، مع لون accent للقناة.
- Adaptive icon foreground inset رُفِع إلى 25% للحفاظ على المنطقة الآمنة.
- `gms:google-services` رُفِع إلى 4.4.2.
- ملف `.env` أُزيل من قائمة `pubspec.yaml > assets` (كان يُفشل البناء على
  أيّ نسخة نظيفة وكان قابلاً للاستخراج من الـ APK).
- `flutter_dotenv` غير المستخدم أُزيل من الـ dependencies.
- Dart SDK constraint = `>=3.7.0 <4.0.0` (3.7 إلزاميّ لأنّ الكود يستعمل
  wildcard patterns `(_, _) =>` المُدخلة في Dart 3.7).
- **امتثال الحقوق + الإبلاغ** (مُطبَّق في الكود):
  - `Content` يقرأ `license_status` / `source_name` / `license_name` /
    `license_url` من Firestore. أيّ عنصر `license_status: 'rejected'`
    يُحجب عن الجميع في حُرّاس القوائم (home + search).
  - زرّ «إبلاغ» يُظهر إشعار «إزالة خلال 24 ساعة عند ثبوت المخالفة»،
    ويُخفي المحتوى محلّياً عن المُبلِّغ فوراً (`HiddenContentService`،
    صندوق Hive `hidden_content`) — يعمل للضيوف أيضاً.
  - سطر إسناد المصدر/الرخصة يظهر في شاشات التفاصيل عند توفّر الحقول.
  - ⚠️ على لوحة التحكّم ملء `license_status`/`source_name`/`license_name`/
    `license_url` عند الرفع (انظر §التحقّق من الترخيص أدناه).
- `JustAudioBackground.init` لا يزال قبل `runApp` (ضروريّ) لكنّ كلّ ما
  عداه نُقل إلى `_warmUpDeferredServices()` يعمل بالتوازي مع بناء الـ UI:
  AudioSession، UserBehaviorTracker، InterestProfileService، FCM token
  registration. ⇒ Cold Start أسرع بشكل ملموس.
- تأخير السبلاش الثابت 2200ms استُبدل بانتقال **حدثيّ** عند انتهاء
  الفيديو، مع شبكة أمان 3500ms في حال فشل المكتبة بإطلاق حدث النهاية.
- `Hive.openBox` كلّها مُغلَّفة بـ try-catch مع استرداد تلقائيّ
  (`deleteBoxFromDisk` ثمّ إعادة فتح فارغ) لمنع تعطيل الإقلاع على ملفّ تالف.
- كلّ `CachedNetworkImage` في التطبيق صار يحدّد `memCacheWidth/Height`
  بضرب البُعد المنطقيّ في `devicePixelRatio` ⇒ لا OOM على أجهزة 2GB.
- ملفّ Lottie المكرّر (`empty_dark.json` + `empty_light.json` كانا
  متطابقَين بايتيّاً) دُمج في `empty.json` (توفير ~158KB من الـ AAB).
- `ApiConstants.baseUrl` صار getter يقبل تجاوزاً عبر
  `--dart-define=NEBRAS_API_BASE_URL=...` أو `ApiConstants.setOverride()`
  من runtime (نقطة الاتّصال المستقبليّة بـ Firebase Remote Config).
- **Google Sign-In / حزمة التطبيق:** التفاصيل الكاملة في
  [`docs/GOOGLE_SIGNIN_ANDROID.md`](docs/GOOGLE_SIGNIN_ANDROID.md)
  (جدول debug vs متجر، أخطاء ApiException 10، أوامر التحقّق).

---

## 🔧 الخطوات التي يجب على المُصدِّر تنفيذها يدوياً قبل الرفع

### 1) إعادة توليد `google-services.json` و `GoogleService-Info.plist`

في الكود حدّثنا `package_name` داخل `android/app/google-services.json`
إلى `com.nebras.mobile`، لكنّ بصمات التوقيع (`certificate_hash`) المُسجَّلة
ضمن OAuth Client تخصّ المفتاح القديم. لذلك:

1. اذهب إلى **Firebase Console → نبراس → إعدادات المشروع → تطبيقاتك**.
2. **سجّل تطبيق Android جديداً** باسم الحزمة `com.nebras.mobile` وأضف
   بصمتَي SHA-1 و SHA-256 للـ keystore الإنتاجيّ.
3. **سجّل تطبيق iOS جديداً** بـ bundle id = `com.nebras.mobile`.
4. حمّل الملفّ الجديد `google-services.json` واستبدل به القديم في
   `android/app/`.
5. حمّل `GoogleService-Info.plist` وأضِفه إلى `ios/Runner/` عبر Xcode.
6. أضِف SHA-256 لمفتاح **Play App Signing** (يظهر بعد أوّل رفعة لـ Play
   Console) داخل نفس قائمة بصمات Android، وإلّا تسجيل دخول Google
   سيفشل على نسخة المتجر.

### 2) توليد keystore الإنتاج وملف `key.properties`

```bash
keytool -genkey -v -keystore android/nebras-release.jks \
        -keyalg RSA -keysize 2048 -validity 10000 -alias nebras
```

ثمّ أنشئ `android/key.properties`:

```
storePassword=...
keyPassword=...
keyAlias=nebras
storeFile=nebras-release.jks
```

كلا الملفّين مُهمَلان عن git بالفعل في `.gitignore`. **لا ترفعهما أبداً**.

### 3) Firebase App Check

لتفعيل App Check يجب:

1. تفعيل الموفّر في Firebase Console:
   - Android → **Play Integrity API** (يستلزم تفعيله من Google Cloud Console
     للمشروع المرتبط).
   - iOS → **App Attest** (يتطلّب iOS 14+) أو **DeviceCheck** كـ fallback.
2. إضافة الـ dependency في `pubspec.yaml`:
   ```yaml
   firebase_app_check: ^0.4.1   # تحقّق من آخر إصدار متوافق مع firebase_core 4.x
   ```
3. تفعيله مبكّراً في `_warmUpDeferredServices()` بعد `Firebase.initializeApp`:
   ```dart
   await FirebaseAppCheck.instance.activate(
     androidProvider: AndroidProvider.playIntegrity,
     appleProvider: AppleProvider.appAttestWithDeviceCheckFallback,
   );
   ```
4. في Firebase Console فعّل **Enforcement** لـ Firestore و Storage بعد
   التأكّد من عمل الموفّر على إصدار اختباريّ.

### 4) Firebase Remote Config (اختياريّ لكنّه موصى به بشدّة)

لتغيير `baseUrl` بدون إصدار جديد:

1. أضِف `firebase_remote_config: ^6.x` لـ pubspec.
2. في `_warmUpDeferredServices()` أضف:
   ```dart
   final rc = FirebaseRemoteConfig.instance;
   await rc.setDefaults({'api_base_url': ''});
   await rc.setConfigSettings(RemoteConfigSettings(
     fetchTimeout: const Duration(seconds: 8),
     minimumFetchInterval: const Duration(hours: 1),
   ));
   await rc.fetchAndActivate();
   ApiConstants.setOverride(rc.getString('api_base_url'));
   ```
3. في Firebase Console → Remote Config: أنشئ مفتاح `api_base_url` وأَفلِته
   فارغاً للإنتاج (يُعيد التطبيق إلى القيمة المضمَّنة).

### 5) iOS — Permissions descriptions

التطبيق حالياً لا يستخدم الكاميرا/الميكروفون/مكتبة الصور، لذلك لا حاجة
إلى `NSCameraUsageDescription` و أخواتها. **إن أُضيفت لاحقاً** يجب
تعريفها في `ios/Runner/Info.plist` وإلا App Store يرفض الإصدار.

### 6) Data Safety Form (Play Console)

يجب الإفصاح في Data Safety عن:

- **Third-party content**: تشغيل فيديوهات YouTube داخل التطبيق.
- **Personal info** (Email, Name, User IDs): جمعها لتسجيل الدخول Google
  (مع تحديد "Not shared with third parties" إن لم نُرسلها لخادمنا).
- **Device & other IDs**: FCM token لإرسال الإشعارات.
- **User-generated content** (بلاغات المحتوى): يُكتب `reporterUid` +
  بيانات العنصر في `content_reports`. أفصِح عنها كـ "User content"
  مُجمَّعة لأغراض الإشراف، غير مُشارَكة. (تُحذف عند حذف الحساب.)
- **App info & performance**: Firebase Crashlytics (إن فُعِّل لاحقاً).
- ⚠️ **لا تُفصِح** عن إعلانات/Ad ID — التطبيق لا يجمعها (لا توجد صلاحية
  `AD_ID` في الـ manifest المدمج)، وسياسة الخصوصية تنصّ على ذلك صراحةً.
- بيانات السلوك/الاهتمامات (`UserBehaviorTracker`/`InterestProfile`)
  **محلّيّة على الجهاز فقط** ولا تُرسَل — لا تُفصِح عنها كبيانات مُجمَّعة.

### 7) Review Notes (App Store)

في "Review Notes" أرفِق:

- إنّ `UIBackgroundModes` تشمل `audio` و `fetch` و `remote-notification`
  لأنّ المشغّل يعمل في الخلفيّة وتصل الإشعارات الصامتة.
- المحتوى معرفيّ ثقافيّ عامّ غير ربحيّ (ليس دينيّاً ولا موجَّهاً لطائفة).
- كلّ المحتوى ملكيّة عامّة أو مرخّص للتوزيع (مصادر: Internet Archive،
  مؤسسة هنداوي، مكتبة نور)، مع زرّ إبلاغ وآليّة إزالة خلال 24 ساعة.

### 8) رفع نسخة AAB

```bash
flutter build appbundle --release \
  --dart-define=NEBRAS_API_BASE_URL=https://api.your-domain.com/
```

تحقّق من أنّ الناتج موقّع بمفتاح الإنتاج:

```bash
jarsigner -verify -verbose build/app/outputs/bundle/release/app-release.aab
```

### 9) التحقّق من ترخيص المحتوى (حقوق النشر — الخطر الأعلى)

التطبيق يفرض الامتثال عبر حقل `license_status` (يحجب `rejected`) ويعرض
الإسناد. لكنّ **التحقّق الفعليّ من كون العنصر ملكيّة عامّة/مرخّصاً** يجب أن
يجري في **لوحة التحكّم وقت الرفع** (التطبيق قارئ فقط ولا يتّصل بالمصادر).
الطرق الموصى بها حسب المصدر:

- **Internet Archive:** استعلم Metadata API لكلّ عنصر:
  `https://archive.org/metadata/<identifier>` ثمّ افحص الحقول:
  - `metadata.licenseurl` (يحتوي `creativecommons.org/...` أو
    `/publicdomain/` ⇒ مرخّص/ملكيّة عامّة).
  - `metadata.possible-copyright-status` = `"NOT_IN_COPYRIGHT"` ⇒ آمن.
  - `metadata.rights` لنصوص الحقوق الأخرى.
  - عند الغياب التامّ لهذه الحقول: ضع `license_status = 'pending'` ولا
    تنشر حتى مراجعة بشريّة.
- **مؤسسة هنداوي (hindawi.org):** المحتوى تحت Creative Commons
  (غالباً CC BY-NC-ND / CC BY-SA) أو ملكيّة عامّة — سجّل
  `source_name="مؤسسة هنداوي"` و`license_name`/`license_url` من صفحة العمل.
- **مكتبة نور (noor-book):** أكثر حساسيّة — ليست كلّها ملكيّة عامّة. لا
  ترفع منها إلا ما هو ملكيّة عامّة أو إذن صريح، ووثّق الإثبات.

عمليّاً: أضِف في اللوحة خطوة قبل النشر تملأ
`license_status / source_name / license_name / license_url`، وتمنع النشر
إذا بقي `license_status` فارغاً أو `pending`. احتفظ بإثبات الترخيص للردّ
على أيّ بلاغ DMCA. (الكود في التطبيق جاهز لاستهلاك هذه الحقول فور كتابتها.)

---

## ⚠️ ملاحظات مهمة

### الأيقونات (Launcher + In-App)

- **مصدر الماستر**: `tools/app_icon_master.png` (1024×1024 RGB، 348KB).
  هذا الملفّ **خارج** `flutter.assets` فلا يُحزَم في AAB، لكنّه يبقى في
  المستودع كي يُولّد `flutter_launcher_icons` كلّ مقاسات الـ mipmap منه
  (mdpi → xxxhdpi). أيّ تحديث للشعار يُكتب فوق هذا الملفّ، ثمّ:
  ```bash
  dart run flutter_launcher_icons         # يُعيد توليد mipmaps
  python tools/compress_icon.py           # يُعيد ضغط النسخة المضمَّنة في الـ assets
  ```
  بعد إعادة توليد الـ launcher تأكّد بقاء `<inset android:inset="25%" />`
  في `mipmap-anydpi-v26/ic_launcher.xml` (الأداة تكتب فوقه).
- **النسخة المضمَّنة**: `assets/images/app_icon.png` (384×384 indexed، ≤
  80KB) — تُستعمل من واجهة المستخدم فقط (سبلاش، about، إلخ).
  السكربت idempotent: تشغيله مرّتين يعطي نفس الناتج لأنّه يقرأ دائماً
  من الماستر.
- **لا تشغّل** `dart run flutter_launcher_icons` قبل التأكّد من وجود
  `tools/app_icon_master.png` ـ وإلّا ستُكتب mipmaps من المصدر الخاطئ.

### إصدار النسخة (versionCode)

- **CI auto-increment**: في GitHub Actions أو محرّك CI الخاص بك أضف
  خطوة تزيد `versionCode` تلقائياً (`+1`، `+2`، …) قبل
  `flutter build appbundle`. Play Console يرفض رفع نفس الرقم مرّتين.
- إن سبق أن رُفع AAB بـ `versionCode = 1` (من تجربة سابقة لـ `0.1.0+1`)،
  ابدأ من `1.0.0+2` أو أعلى. عدِّل من `pubspec.yaml > version`.
