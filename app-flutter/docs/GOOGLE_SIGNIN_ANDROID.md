# Google Sign-In على Android — حزمة التطبيق والبصمات

مرجع سريع للمطوّرين: لماذا يختلف `applicationId` بين التطوير والمتجر، وكيف تتجنّب `ApiException: 10` (DEVELOPER_ERROR).

---

## القاعدة الذهبية

| نوع البناء | الأمر النموذجي | `applicationId` (تلقائي في Gradle) | بصمة التوقيع المطلوبة في Firebase |
|------------|----------------|-------------------------------------|-----------------------------------|
| **تطوير** | `flutter run`, `assembleDebug` | `com.example.nebras_mobile_app` | SHA-1 لـ **debug.keystore** |
| **متجر** | `flutter build appbundle`, `assembleRelease` | `com.nebras.mobile` | SHA-1/256 لـ **release keystore** + Play App Signing |

التبديل مُعرَّف في `android/app/build.gradle.kts` داخل `defaultConfig` — **لا تغيّر `applicationId` يدوياً** إلا إذا فهمت الجدول أعلاه.

---

## لماذا يوجد حزمتان؟

مشروع Firebase يحتوي في `android/app/google-services.json` على **عميلين Android**:

1. **`com.example.nebras_mobile_app`** — مرتبط ببصمة debug المحلية (`certificate_hash` في الملف).
2. **`com.nebras.mobile`** — حزمة الإنتاج/المتجر (بصمات release و/أخرى).

إذا شغّلت `flutter run` بـ `com.nebras.mobile` بينما الجهاز يوقّع التطبيق بمفتاح **debug**، Google Play Services يرفض OAuth ويُرجع:

```text
PlatformException: sign_in_failed
ApiException: 10  (DEVELOPER_ERROR)
```

الحلّ المُطبَّق في المستودع: Gradle يختار الحزمة المناسبة حسب **مهمّة Gradle** (debug مقابل release publish).

---

## ماذا تفعل عند كل سيناريو

### تطوير يومي (`flutter run`)

- لا شيء إضافي — الحزمة `com.example.nebras_mobile_app` تُختار تلقائياً.
- إن ثبّتَ سابقاً APK بـ `com.nebras.mobile` على الجهاز، قد تحتاج إزالة التطبيق القديم (تعارض توقيع):

```bash
adb uninstall com.nebras.mobile
adb uninstall com.example.nebras_mobile_app
```

### بناء نسخة المتجر (AAB/APK release)

```bash
# تأكّد من وجود android/key.properties — راجع STORE_RELEASE.md
flutter build appbundle --release
```

- Gradle يضبط `applicationId = com.nebras.mobile`.
- **يجب** أن تكون بصمة **release** (و SHA من Play App Signing بعد أوّل رفع) مضافة في Firebase لتطبيق `com.nebras.mobile`.
- بعد تحديث البصمات في Console: نزّل `google-services.json` جديداً إلى `android/app/`.

### اختبار release محلياً على جهاز

```bash
flutter run --release
```

> `flutter run --release` **لا** يُفعّل مسار `bundleRelease`/`assembleRelease` في Gradle — قد يبقى `applicationId` على حزمة التطوير. لاختبار Google Sign-In بحزمة المتجر فعلياً، ثبّت AAB من `flutter build appbundle` أو استخدم `flutter install --release` بعد `assembleRelease`.

---

## التحقّق من بصمة SHA-1 المحلية (debug)

```bash
cd android
./gradlew signingReport
# أو على Windows:
gradlew.bat signingReport
```

ابحث عن `Variant: debug` → `SHA1`. قارِنها مع `certificate_hash` داخل `google-services.json` لتطبيق `com.example.nebras_mobile_app`.

بصمة debug الافتراضية على هذا الجهاز/المستودع (مرجع):

```text
SHA1: 9B:28:7E:35:00:DA:BE:F7:71:E7:23:F4:D1:91:B3:D2:F5:19:BD:19
```

(تختلف إن استخدمت keystore debug مخصّص.)

---

## أخطاء شائعة

| العرض | السبب المحتمل | الإجراء |
|-------|----------------|---------|
| `ApiException: 10` عند `flutter run` | حزمة أو SHA غير مطابقة | لا تُجبِر `com.nebras.mobile` في debug؛ أعد `flutter run` بعد `git pull` |
| `INSTALL_FAILED_UPDATE_INCOMPATIBLE` | تثبيت فوق APK بتوقيع مختلف | `adb uninstall` للحزمتين (انظر أعلاه) |
| نجاح الدخول في debug وفشل في المتجر | بصمة release غير مضافة لـ `com.nebras.mobile` | Firebase Console → التطبيق → Add fingerprint → حدّث `google-services.json` |
| `google_fonts` / `fonts.gstatic.com` | لا شبكة عند أوّل إطار | `main.dart` يحمّل الخطوط مسبقاً مع `try/catch` — تحذير فقط |

---

## توحيد الحزمة (اختياري — للفريق المتقدّم)

إن أردتم **حزمة واحدة** `com.nebras.mobile` حتى في التطوير:

1. في Firebase Console أضيفوا SHA-1 **debug** لتطبيق `com.nebras.mobile`.
2. نزّلوا `google-services.json` محدَّثاً.
3. احذفوا كتلة `applicationId` الشرطية من `build.gradle.kts` وثبّتوا `applicationId = "com.nebras.mobile"` دائماً.

---

## ملفّات ذات صلة

| ملف | دور |
|-----|-----|
| `android/app/build.gradle.kts` | اختيار `applicationId` حسب نوع البناء |
| `android/app/google-services.json` | عملاء OAuth وبصمات Firebase |
| `lib/features/auth/service/auth_service.dart` | `serverClientId` (Web client type 3) |
| `lib/features/auth/provider/auth_provider.dart` | رسائل الخطأ للمطوّر في السجل |
| `STORE_RELEASE.md` | keystore، Play، App Check |
