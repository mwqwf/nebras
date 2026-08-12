import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// ──────────────────────────────────────────────────────────────────────────
// تحميل بيانات التوقيع من ملفّ key.properties محليّ (غير مُدرَج في git).
// إن لم يوجد الملف نتركها فارغة فيستخدم البناء توقيع debug تلقائياً
// (مثل أيام التطوير)، أمّا في CI/المتجر فنوفّر الملف فيُستخدم release.
// ──────────────────────────────────────────────────────────────────────────
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.nebras.mobile"
    // نُثبّت compileSdk صراحةً (36) لأنّ بعض الـ plugins الحديثة
    // (`device_info_plus`, `google_sign_in_android`, `path_provider_android`,
    // `shared_preferences_android`, `sqflite_android`,
    // `syncfusion_flutter_pdfviewer`, `url_launcher_android`,
    // `video_player_android`) تشترط أن يكون التطبيق مُجمَّعاً على Android
    // SDK 36 أو أحدث. التوافق إلى الخلف مضمون عبر `targetSdk`/`minSdk`.
    // Google Play يفرض `targetSdk = 35` كحدّ أدنى منذ 31 أغسطس 2025 للرفع
    // الجديد — `compileSdk = 36` يبقي إصدار النشر متوافقاً مع كل أجهزة 35.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        // Google Sign-In (debug): بصمة debug.keystore (SHA-1 9B:28:7E:35:…) مسجّلة في
        // google-services.json تحت com.example.nebras_mobile_app فقط. إصدارات المتجر
        // (assembleRelease / bundleRelease) تبقى com.nebras.mobile مع بصمة release.
        val taskNames = gradle.startParameter.taskNames
        val isStoreRelease = taskNames.any {
            it.contains("bundleRelease", ignoreCase = true) ||
                it.contains("assembleRelease", ignoreCase = true)
        }
        applicationId = if (isStoreRelease) {
            "com.nebras.mobile"
        } else {
            "com.example.nebras_mobile_app"
        }
        // ⚠️ minSdk = 23 (Android 6.0) — مُثبَّت صراحةً.
        // 23 أقلّ ما يدعمه `just_audio` و `cloud_firestore` 6.x. كان
        // الاعتماد على `flutter.minSdkVersion` خطِراً: على Flutter قديم
        // (< 3.27) يساوي 21 أو 19 فينهار التطبيق على Android 5.x بـ
        // NoSuchMethodError من Firestore. نُثبّت 23 كي لا يتغيّر الحدّ مع
        // تحديثات محرّك Flutter. (يطابق STORE_RELEASE.md و CLAUDE.md.)
        minSdk = 23
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            // نقرأ من key.properties إن وُجد، وإلّا نُسقطه بسلاسة.
            val storePath = keystoreProperties.getProperty("storeFile")
            if (storePath != null && storePath.isNotEmpty()) {
                storeFile = file(storePath)
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // إذا تواجد key.properties وُقِّع الإصدار بمفتاح الإنتاج،
            // وإلّا رجعنا إلى debug ليكون البناء المحلّي ممكناً للمطوّرين.
            // ── حارس صارم: عند بناء AAB للنشر (`bundleRelease`) أو APK
            //    موقَّع للنشر (`assembleRelease`) — يجب وجود `key.properties`.
            //    وإلا نوقف البناء فوراً بدلاً من إنتاج artifact موقَّع بـ debug
            //    سيرفضه Play Console بصمت بعد رفعة كاملة.
            val taskNames = gradle.startParameter.taskNames
            val isReleasePublishTask = taskNames.any {
                it.contains("bundleRelease", ignoreCase = true) ||
                    it.contains("assembleRelease", ignoreCase = true)
            }
            if (isReleasePublishTask && !keystorePropertiesFile.exists()) {
                throw GradleException(
                    "🛑 ملف android/key.properties غير موجود. \n" +
                        "لا يمكن بناء نسخة release للنشر بدون مفتاح توقيع الإنتاج.\n" +
                        "راجع STORE_RELEASE.md §2 لتوليد keystore."
                )
            }
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

dependencies {

    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}

flutter {
    source = "../.."
}
