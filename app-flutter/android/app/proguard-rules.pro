# ─────────────────────────────────────────────────────────────────────────
# Nebras Mobile — ProGuard / R8 rules for release builds.
#
# الغاية: تفعيل R8 + shrinkResources دون كسر المكتبات التي تعتمد على
# الانعكاس (reflection) أو على أسماء كلاسات محدّدة لا يجب تشويشها.
#
# مرجع كل كتلة موثّق في توثيق المكتبة الرسميّ. لا تحذف بنداً دون فهم
# تبعاته على Release.
# ─────────────────────────────────────────────────────────────────────────

# ── Flutter Embedding ───────────────────────────────────────────────────
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# ── الانعكاس لِـ @pragma('vm:entry-point') من Flutter ─────────────────
# يحتاجها معالج FCM في الخلفية و isolate المهام المخصّصة.
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod

# ── Firebase / Google Play Services ─────────────────────────────────────
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Cloud Firestore POJO mapping — يستخدم الانعكاس لقراءة الحقول.
-keepclassmembers class * {
    @com.google.firebase.firestore.PropertyName <fields>;
    @com.google.firebase.firestore.PropertyName <methods>;
}
-keep class com.google.firebase.firestore.** { *; }

# ── gRPC (طبقة الشبكة الداخلية لـ Cloud Firestore على Android) ──────────
# Firestore تستخدم gRPC لاتصالاتها بالخادم. إن حُذفت هذه الكلاسات بواسطة
# R8 تفشل جميع قراءات وكتابات Firestore صامتةً (لا استثناء مرئي)، بينما
# يستمر FCM بالعمل لأنّه يستخدم طبقة شبكة مختلفة (Firebase Messaging HTTP/2).
-keep class io.grpc.** { *; }
-dontwarn io.grpc.**
-keep class io.grpc.android.** { *; }

# ── Protobuf (تستخدمه gRPC وFirestore لتسلسل البيانات) ─────────────────
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.protobuf.**

# ── Perfmark / OpenCensus (مكتبات تتبّع تستخدمها gRPC) ──────────────────
-keep class io.perfmark.** { *; }
-dontwarn io.perfmark.**
-dontwarn io.opencensus.**

# ── Google API core (مطلوبة من Firebase Auth وFirestore) ─────────────────
-keep class com.google.api.** { *; }
-dontwarn com.google.api.**

# FCM background message handler
-keep class com.google.firebase.messaging.** { *; }
-keep class io.flutter.plugins.firebase.messaging.** { *; }

# ── Google Sign-In ──────────────────────────────────────────────────────
-keep class com.google.android.gms.auth.** { *; }
-keep class com.google.android.gms.common.** { *; }

# ── Hive — type adapters تُولَّد بالأسماء وتُستدعى عبر الانعكاس ────────
-keep class **.*Adapter { *; }
-keep class hive.** { *; }
-keepclassmembers class * extends hive.TypeAdapter {
    public <init>(...);
}

# الموديلات الخاصّة بنا التي يولّد لها build_runner Adapters.
-keep class com.nebras.mobile.** { *; }

# ── just_audio / just_audio_background / audio_service ─────────────────
-keep class com.ryanheise.just_audio.** { *; }
-keep class com.ryanheise.audioservice.** { *; }
-keep class androidx.media.** { *; }
-dontwarn com.ryanheise.audioservice.**

# ExoPlayer (محرّك just_audio على Android)
-keep class com.google.android.exoplayer2.** { *; }
-keep class androidx.media3.** { *; }
-dontwarn com.google.android.exoplayer2.**
-dontwarn androidx.media3.**

# ── flutter_local_notifications ─────────────────────────────────────────
-keep class com.dexterous.** { *; }
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class com.dexterous.flutterlocalnotifications.models.** { *; }
-keep class com.google.gson.reflect.** { *; }
-keepattributes *Annotation*
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}

# ── Gson (يُستخدم من flutter_local_notifications) ──────────────────────
-keep class com.google.gson.** { *; }
-keepclassmembers class * implements com.google.gson.JsonDeserializer { *; }
-keepclassmembers class * implements com.google.gson.JsonSerializer { *; }

# ── Syncfusion PDF Viewer ───────────────────────────────────────────────
-keep class com.syncfusion.** { *; }
-dontwarn com.syncfusion.**

# ── video_player + youtube_player_flutter (WebView) ────────────────────
-keep class io.flutter.plugins.videoplayer.** { *; }
-keep class io.flutter.plugins.webviewflutter.** { *; }
-keep class android.webkit.** { *; }
-dontwarn android.webkit.**

# ── floating (PiP) ──────────────────────────────────────────────────────
-keep class fr.g123k.floating.** { *; }

# ── go_router / provider — صفّاء reflection-safe افتراضياً ───────────
# لا قواعد إضافيّة مطلوبة.

# ── R8 optimization: keep enum values + Parcelable creators ────────────
-keepclassmembers enum * { *; }
-keep class * implements android.os.Parcelable {
  public static final ** CREATOR;
}

# ── Kotlin coroutines (تُستعملها مكتبات Firebase الحديثة) ───────────
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}
-keepclassmembers class kotlinx.coroutines.internal.MainDispatcherFactory {
    *;
}
-dontwarn kotlinx.coroutines.**

# ── العامّة: تجاهل تحذيرات JSR-305 ─────────────────────────────────────
-dontwarn javax.annotation.**
-dontwarn org.checkerframework.**
-dontwarn org.codehaus.mojo.animal_sniffer.**

# ⚠️ لم نضع `-ignorewarnings` عمداً: ابتلاع تحذيرات R8 يُخفي تجريد
# كلاسات حقيقيّة قد تُسبّب انهياراً في الإنتاج. إن ظهرت تحذيرات أثناء
# البناء، عالجها بـ `-dontwarn package.specific.**` مُحدَّدة، لا بتجاهل
# عامّ.
