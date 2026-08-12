# Privacy Policy — English & French (for publishing)

> صفحة الخصوصية الحاليّة بالعربية فقط على https://nibras-app-website.vercel.app/privacy
> هذه نسخ مطابقة بالإنجليزية والفرنسية لمطابقة لغات التطبيق الثلاث.
> انشرها على نفس النطاق (مثلاً `/privacy?lang=en` و `/privacy?lang=fr`) أو بصفحات منفصلة.
> **يجب أن تبقى الصفحات عامّة بدون تسجيل دخول** (شرط Google Play).

---

## English

**Privacy Policy — Nebras**

_Last updated: 2026-05-21_

Nebras ("the app") respects your privacy. This policy explains what we collect and how we use it.

**1. Information we collect**
- If you choose to sign in with Google, we receive basic profile information: your name, email address, and profile picture. Signing in is **optional** — you can browse content as a guest.
- Your in-app activity (browsing, watching, interactions) is processed **locally on your device** to personalize your experience.

**2. Information we do NOT collect**
We do not collect your location, contacts, financial information, advertising identifiers, health data, or personal files.

**3. How we use information**
- To create your account and sync your favorites and "continue watching" state across your devices.
- To send notifications (using a Firebase Cloud Messaging token) when you enable them.
- To recommend relevant content.

**4. Third-party services**
- The app plays YouTube videos within the app; YouTube's own terms and privacy policy apply to that playback.
- We use Google Firebase (authentication, database, messaging) to operate the service.

**5. Data sharing**
We do **not** sell, trade, or transfer your information to third parties.

**6. Your choices**
You can sign out at any time, which clears your local personalization signals. You can disable notifications from the app settings.

**7. Contact**
For any privacy question, contact us at the email listed on our website.

---

## Français

**Politique de confidentialité — Nebras**

_Dernière mise à jour : 2026-05-21_

Nebras (« l'application ») respecte votre vie privée. Cette politique explique ce que nous collectons et comment nous l'utilisons.

**1. Informations que nous collectons**
- Si vous choisissez de vous connecter avec Google, nous recevons des informations de profil de base : votre nom, votre adresse e-mail et votre photo de profil. La connexion est **facultative** — vous pouvez parcourir le contenu en tant qu'invité.
- Votre activité dans l'application (navigation, visionnage, interactions) est traitée **localement sur votre appareil** pour personnaliser votre expérience.

**2. Informations que nous NE collectons PAS**
Nous ne collectons pas votre localisation, vos contacts, vos informations financières, vos identifiants publicitaires, vos données de santé ni vos fichiers personnels.

**3. Utilisation des informations**
- Pour créer votre compte et synchroniser vos favoris et l'état « continuer à regarder » entre vos appareils.
- Pour envoyer des notifications (à l'aide d'un jeton Firebase Cloud Messaging) lorsque vous les activez.
- Pour recommander du contenu pertinent.

**4. Services tiers**
- L'application lit des vidéos YouTube ; les conditions et la politique de confidentialité de YouTube s'appliquent à cette lecture.
- Nous utilisons Google Firebase (authentification, base de données, messagerie) pour faire fonctionner le service.

**5. Partage des données**
Nous ne **vendons**, n'échangeons ni ne transférons vos informations à des tiers.

**6. Vos choix**
Vous pouvez vous déconnecter à tout moment, ce qui efface vos signaux de personnalisation locaux. Vous pouvez désactiver les notifications dans les paramètres de l'application.

**7. Contact**
Pour toute question relative à la confidentialité, contactez-nous à l'adresse e-mail indiquée sur notre site web.

---

# دليل تفعيل App Check و Remote Config (يتطلّب pub get + Firebase Console)

> هذه خطوات **لا يمكن أتمتتها من الكود وحده** لأنها تحتاج تسجيل في Firebase/Google Cloud Console.
> الأكواد الجاهزة موجودة أيضاً في `STORE_RELEASE.md` (بندان 3 و 4). ملخّص للتنفيذ:

## App Check
1. أضِف للـ `pubspec.yaml`:
   ```yaml
   firebase_app_check: ^0.4.1   # تحقّق من توافقه مع firebase_core ^4.7.0
   ```
   ثم `flutter pub get`.
2. في `lib/main.dart` ضمن `_warmUpDeferredServices()` بعد `Firebase.initializeApp`:
   ```dart
   await FirebaseAppCheck.instance.activate(
     androidProvider: AndroidProvider.playIntegrity,
     appleProvider: AppleProvider.appAttestWithDeviceCheckFallback,
   );
   ```
3. في Firebase Console فعّل **Play Integrity** (Android) و**App Attest** (iOS)، وسجّل التطبيق.
4. لا تُفعّل **Enforcement** لـ Firestore/Storage إلا بعد التأكّد على نسخة اختباريّة (وإلّا ينقطع الوصول للبيانات).

## Remote Config (لتغيير baseUrl دون إصدار)
1. أضِف:
   ```yaml
   firebase_remote_config: ^6.x
   ```
   ثم `flutter pub get`.
2. في `_warmUpDeferredServices()`:
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
3. في Console → Remote Config أنشئ مفتاح `api_base_url` (اتركه فارغاً للإنتاج).

> ⚠️ لم أُضِف هاتين الحزمتين تلقائياً لتجنّب كسر البناء بنزاع تبعيات قبل التأكّد
> من توافق الإصدارات مع `firebase_core 4.7.0` ومن إعداد الـ Console. أخبرني
> لأضيفهما وأشغّل `flutter pub get` وأتحقّق من البناء.
