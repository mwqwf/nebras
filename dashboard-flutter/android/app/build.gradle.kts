plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // FlutterFire — يطبّق google-services.json (يجب أن يأتي بعد android/kotlin/flutter).
    id("com.google.gms.google-services")
}

android {
    namespace = "com.nebras.nebras_dashboard"
    // نُثبّت compileSdk = 36 لتوافق إضافات google_sign_in/firebase الحديثة (مثل تطبيق نبراس).
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // معرّف مستقلّ للوحة مسجَّل في Firebase (تطبيق «لوحة نبراس»
        // 1:412379996427:android:cf1fd174dbad0af900c20e) مع بصمة debug.keystore
        // (SHA-1 9B:28:7E:35:…) — فيعمل Google Sign-In وFirebase مباشرة.
        // ⚠️ كان `com.example.nebras_mobile_app` سابقاً — نفس معرّف نسخة debug
        // من تطبيق نبراس العام، فكان تثبيت أحدهما يستبدل الآخر ويُسقط هدف
        // «مشاركة إلى نبراس» من قائمة المشاركة. لا تُعِد توحيدهما.
        applicationId = "com.nebras.dashboard"
        // minSdk = 23 إلزاميّ لـ cloud_firestore 6.x / firebase_auth 6.x.
        minSdk = flutter.minSdkVersion
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    buildTypes {
        release {
            // توقيع debug حتى يعمل `flutter run --release` دون keystore إنتاج
            // (هذه أداة إدارية داخلية لا تُرفع للمتجر).
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    // ≥2.1.4 مطلوب لـ flutter_local_notifications 19.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
