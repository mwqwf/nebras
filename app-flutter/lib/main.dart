import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/cupertino.dart' as ui show TextDirection;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:nebras_mobile_app/core/di/setup_locator.dart';
import 'package:nebras_mobile_app/core/services/continue_watching_service.dart';
import 'package:nebras_mobile_app/core/services/hidden_content_service.dart';
import 'package:nebras_mobile_app/core/services/interest_profile_service.dart';
import 'package:nebras_mobile_app/core/services/popularity_feed_service.dart';
import 'package:nebras_mobile_app/core/services/user_behavior_tracker.dart';
import 'package:nebras_mobile_app/core/config/remote_backend_config.dart';
import 'package:nebras_mobile_app/core/network/api_constants.dart';
import 'package:nebras_mobile_app/core/network/dio_client.dart';
import 'package:nebras_mobile_app/core/providers/sections_layout_provider.dart';
import 'package:nebras_mobile_app/core/routing/notification_navigator.dart';
import 'package:nebras_mobile_app/core/theme/apptheme.dart';
import 'package:nebras_mobile_app/core/theme/provider/theme_provider.dart';
import 'package:nebras_mobile_app/features/notifications/data/firebase_notification_datasource.dart';
import 'package:nebras_mobile_app/features/notifications/domain/repos/firebase_token_repo.dart';
import 'package:nebras_mobile_app/features/notifications/domain/repos/notification_repo.dart';
import 'package:nebras_mobile_app/features/notifications/domain/usecase/get_notification_usecase.dart';
import 'package:nebras_mobile_app/features/notifications/domain/usecase/mark_notification_read_usecase.dart';
import 'package:nebras_mobile_app/features/notifications/domain/usecase/mark_all_notifications_read_usecase.dart';
import 'package:nebras_mobile_app/features/notifications/domain/usecase/delete_notification_usecase.dart';
import 'package:nebras_mobile_app/features/notifications/domain/usecase/get_unread_count_usecase.dart';
import 'package:nebras_mobile_app/features/notifications/model/notification_model.dart';
import 'package:nebras_mobile_app/features/notifications/provider/notfication_provider.dart';
import 'package:nebras_mobile_app/features/reader/domain/usecases/get_last_page_usecase.dart';
import 'package:nebras_mobile_app/features/reader/domain/usecases/save_last_page_usecase.dart';
import 'package:nebras_mobile_app/features/reader/provider/reader_provider.dart';
import 'package:nebras_mobile_app/features/saved/domain/usecase/ensuer_saved_usecase.dart';
import 'package:nebras_mobile_app/features/saved/domain/usecase/get_saved_items_usecase.dart';
import 'package:nebras_mobile_app/features/saved/domain/usecase/is_saved_usecase.dart';
import 'package:nebras_mobile_app/features/saved/domain/usecase/remove_saved_usecase.dart';
import 'package:nebras_mobile_app/features/saved/domain/usecase/toggle_saved_usecase.dart';
import 'package:nebras_mobile_app/features/saved/model/saved_item_model.dart';
import 'package:nebras_mobile_app/features/saved/provider/saved_provider.dart';
import 'package:nebras_mobile_app/features/search/domain/usecase/search_content_usecase.dart';
import 'package:nebras_mobile_app/features/search/domain/usecase/get_sections_usecase.dart';
import 'package:nebras_mobile_app/features/search/domain/usecase/get_section_content_usecase.dart';
import 'package:nebras_mobile_app/features/search/provider/search_provider.dart';
import 'package:nebras_mobile_app/features/home/domain/get_home_data_usecase.dart';
import 'package:nebras_mobile_app/features/home/providers/home_provider.dart';
import 'package:nebras_mobile_app/features/download/data/download_item_model.dart';
import 'package:nebras_mobile_app/features/download/domain/download_repository.dart';
import 'package:nebras_mobile_app/features/download/domain/usecases/start_download_usecase.dart';
import 'package:nebras_mobile_app/features/download/domain/usecases/pause_download_usecase.dart';
import 'package:nebras_mobile_app/features/download/domain/usecases/resume_download_usecase.dart';
import 'package:nebras_mobile_app/features/download/domain/usecases/cancel_download_usecase.dart';
import 'package:nebras_mobile_app/features/download/domain/usecases/delete_download_usecase.dart';
import 'package:nebras_mobile_app/features/download/domain/usecases/get_download_status_usecase.dart';
import 'package:nebras_mobile_app/features/download/provider/media_download_provider.dart';
import 'package:nebras_mobile_app/features/auth/provider/auth_provider.dart';
import 'package:nebras_mobile_app/features/auth/service/auth_service.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:nebras_mobile_app/firebase_options.dart';
import 'package:provider/provider.dart';
import 'features/splash/splash_screen.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nebras_mobile_app/core/firebase/firestore_sync_config.dart';
import 'package:nebras_mobile_app/features/content/cache/content_metadata_cache.dart';

/// معالج رسائل FCM في الخلفية — يعمل في Isolate منفصل ولذلك يجب أن يكون
/// دالّة عليا وموسومة بـ [vm:entry-point] ليستطيع Flutter الوصول إليها بعد
/// tree shaking في وضع الإصدار. نعتمد على notification payload القادم من
/// الخادم (عبر firebase-admin) كي يتولّى نظام Android إظهار البانر تلقائياً،
/// فلا حاجة لعمل شيء داخلي هنا سوى تهيئة Firebase.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (_) {
    // نتجاهل — قد تكون Firebase مهيّأة مسبقاً من Isolate آخر.
  }
  debugPrint(
    '[FCM/background] ${message.messageId ?? 'no-id'} · ${message.notification?.title ?? ''}',
  );
}

/// تهيئة Hive وفتح كل الصناديق مع حماية من تلف الملف.
///
/// ─────────────────────────────────────────────────────────────────────
/// إن تعطّل فتح أحد الصناديق (مثلاً ملف تالف بعد تحديث منقطع) فبدلاً من
/// انهيار التطبيق نحذف الصندوق المعنيّ من القرص ونعيد فتحه فارغاً. هذا
/// يكلّف المستخدم فقدان كاش محلّيّ قابل لإعادة البناء، لكنّه يحفظ
/// إمكانيّة الاستخدام بدل شاشة بيضاء عند الإقلاع.
Future<void> _initHive() async {
  await Hive.initFlutter();

  Hive.registerAdapter(SavedItemModelAdapter());
  Hive.registerAdapter(DownloadItemModelAdapter());
  Hive.registerAdapter(NotificationModelAdapter());
  Hive.registerAdapter(ContentMetadataCacheEntryAdapter());

  Future<void> safeOpen<T>(String name) async {
    try {
      await Hive.openBox<T>(name);
    } catch (e, st) {
      debugPrint('[Hive] فشل فتح الصندوق "$name": $e\n$st');
      try {
        await Hive.deleteBoxFromDisk(name);
        await Hive.openBox<T>(name);
        debugPrint('[Hive] أعيد إنشاء الصندوق "$name" بعد تلفه.');
      } catch (e2) {
        // كحلٍّ أخير: تجاهل الصندوق. التطبيق سيعمل بدون كاش هذه الميزة.
        debugPrint('[Hive] تعذّر استرداد الصندوق "$name": $e2');
      }
    }
  }

  await safeOpen<ContentMetadataCacheEntry>('content_metadata_cache');
  await safeOpen<DownloadItemModel>('downloads');
  await safeOpen<SavedItemModel>('saved_items');
  await safeOpen<NotificationModel>('notifications');
  // صندوق المحتوى المُخفى عن المُبلِّغ (محلّيّ، يعمل للضيوف أيضاً).
  await safeOpen('hidden_content');
}

/// تهيئات يمكن تأجيلها إلى ما بعد `runApp` بدون تعطيل أوّل إطار.
///
/// ─────────────────────────────────────────────────────────────────────
/// AudioSession، UserBehaviorTracker، InterestProfileService، تسجيل
/// FCM token مع الخادم… كلها لا يلزم اكتمالها قبل عرض السبلاش. ندعها
/// تكتمل بالتوازي مع بناء الواجهة، فيُختصر الـ Cold Start بشكل ملموس.
Future<void> _warmUpDeferredServices() async {
  // تحميل Cairo/Poppins مسبقاً حتى لا تُرمى استثناءات غير مُعالجة عند غياب الشبكة.
  try {
    await GoogleFonts.pendingFonts([
      GoogleFonts.cairo(fontWeight: FontWeight.w600),
      GoogleFonts.poppins(fontWeight: FontWeight.w600),
    ]).timeout(const Duration(seconds: 12));
  } catch (e) {
    debugPrint('[boot] Google Fonts preload skipped: $e');
  }

  // ── إعداد تركيز الصوت (Audio Focus) — لا يحتاجه أوّل إطار ───────
  try {
    final audioSession = await AudioSession.instance;
    await audioSession.configure(const AudioSessionConfiguration.music());
  } catch (e) {
    debugPrint('[boot] AudioSession.configure failed: $e');
  }

  // متتبّع السلوك العالميّ + ملفّ الاهتمامات (محلّيان، لا شبكة).
  try {
    await UserBehaviorTracker.instance.init();
  } catch (e) {
    debugPrint('[boot] UserBehaviorTracker.init failed: $e');
  }
  try {
    await InterestProfileService.instance.init();
  } catch (e) {
    debugPrint('[boot] InterestProfileService.init failed: $e');
  }
  try {
    await ContinueWatchingService.instance.init();
  } catch (e) {
    debugPrint('[boot] ContinueWatchingService.init failed: $e');
  }

  // تسخين معرّفات الشعبيّة الأسبوعيّة مبكّراً (قراءة خفيفة لمستند واحد +
  // كاش 6 ساعات) كي تكون جاهزة في الذاكرة عند بناء رفوف الرئيسية، فلا
  // يُحجب أوّل عرض للمحتوى على قراءة شبكة.
  try {
    await PopularityFeedService.instance.loadPopularIds();
  } catch (e) {
    debugPrint('[boot] PopularityFeed warmup failed: $e');
  }

  // ── إشعارات Firebase: قنوات + معالج النقرات ─────────────────────
  // ننشئ NotificationRepo (lazySingleton) **قبل** initialize() حتى يكون
  // مستمعاً لبثّ المصدر عند إطلاق أوّل إشعار (initialMessage من حالة
  // terminated) فيُحفَظ في Hive؛ كان يُفقَد سابقاً لأنّ الـ repo كسول.
  try {
    locator<NotificationRepo>();
  } catch (e) {
    debugPrint('[boot] NotificationRepo warmup failed: $e');
  }
  try {
    await locator<FirebaseNotificationDatasource>().initialize();
  } catch (e) {
    debugPrint('[boot] FirebaseNotificationDatasource.initialize failed: $e');
  }

  // ── تسجيل الـ FCM token مع الخادم (مؤجَّل تماماً) ──────────────
  // الخادم Render Free يدخل sleep بعد 15 دقيقة، وأوّل طلب يستغرق
  // 30–60 ثانية. لو حجبنا الإقلاع عليه لظهرت شاشة سوداء طويلة.
  try {
    final token = await locator<FirebaseTokenRepo>().getDeviceToken();
    if (token != null && token.isNotEmpty) {
      if (kDebugMode) {
        debugPrint('FCM Token: $token');
      }
      if (!isLegacyRenderBackendEnabled) {
        debugPrint(
          '[boot] Skipping Render token registration (USE_RENDER_BACKEND off).',
        );
        return;
      }
      try {
        await DioClient.instance.post(
          ApiConstants.notifications,
          data: {
            'registration_id': token,
            'type': Platform.isIOS ? 'ios' : 'android',
          },
        );
        debugPrint('Token registered successfully');
      } catch (e) {
        debugPrint('Token registration failed: $e');
      }
    }
  } catch (e) {
    debugPrint('[boot] getDeviceToken failed: $e');
  }
}

void main() async {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // ── تهيئة مشغّل الوسائط في الخلفيّة (just_audio_background) ───────────
  // يجب أن تسبق أيّ إنشاء لـ AudioPlayer. تربط المشغّل تلقائيّاً بـ
  // MediaSession على Android و MPNowPlayingInfoCenter على iOS، فتظهر
  // أزرار التشغيل في لوحة الإشعارات وشاشة القفل. الاسم داخل
  // `androidNotificationChannelId` يجب أن يكون فريداً لتطبيقنا كي لا
  // يتعارض مع قنوات تطبيقات أخرى.
  //
  // ملاحظة أداء: تضيف ~150-400ms إلى Cold Start لكنها ضروريّة قبل أي
  // AudioPlayer، فلا يمكن نقلها إلى تهيئة كسولة.
  await JustAudioBackground.init(
    androidNotificationChannelId: 'app.nebras.audio.channel',
    androidNotificationChannelName: 'Nebras Audio Playback',
    androidNotificationOngoing: true,
    androidStopForegroundOnPause: true,
    preloadArtwork: true,
  );

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // نفعّل كاش Firestore قبل أي قراءة: لقطات الكاش تظهر فوراً، ولقطات
  // الخادم الحية تنظّف المحذوفات عند أول اتصال كي لا تبقى بيانات ميتة.
  await FirestoreSyncConfig.configure(FirestoreSyncConfig.instance);

  // يجب تسجيله مباشرة بعد تهيئة Firebase وقبل أيّ أسلوب آخر في FCM.
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  await EasyLocalization.ensureInitialized();

  // ── تهيئة Hive وفتح الصناديق مع حماية من تلف القاعدة ─────────────────
  // إن انقطع التحديث في منتصفه قد يصبح ملف Hive تالفاً ويتعطّل الإقلاع
  // كليّاً. هنا نلتقط الاستثناء، نحذف الصندوق التالف، ونعيد فتحه فارغاً
  // كحلّ احتياطيّ بدل تعطيل التطبيق على المستخدم.
  await _initHive();

  // تحميل قائمة المحتوى المُخفى عن المُبلِّغ إلى الذاكرة قبل بناء أي رفّ
  // محتوى، حتى لا يومض عنصر مُخفى لحظة الإقلاع.
  await HiddenContentService.instance.init();

  await setupLocator();

  // ─── تهيئات قابلة للتأجيل (Lazy / Parallel) ─────────────────────────
  // العمليّات أدناه لا تحجب أوّل إطار من Flutter: نُنفّذها بالتوازي مع
  // بناء شجرة الـ widgets فيظهر السبلاش فوراً ويختفي بمجرد جاهزيّة الـ UI،
  // بينما تكتمل بقيّة التهيئات في الخلفيّة.
  unawaited(_warmUpDeferredServices());

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('ar'), Locale('en'), Locale('fr')],
      path: 'assets/translations',
      fallbackLocale: const Locale('ar'),
      saveLocale: true,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => ThemeProvider()..loadFromPrefs(),
          ),
          // قائمة المحتوى المُخفى عن المُبلِّغ — singleton كي تُشارَك بين
          // الرفوف والشاشات وتُحدّثها فور الإبلاغ.
          ChangeNotifierProvider<HiddenContentService>.value(
            value: HiddenContentService.instance,
          ),
          // ── المصادقة (Google Sign-In) ─────────────────────────────
          // نُسجِّل `AuthProvider` مبكّرًا جدًّا حتى تتمكّن `AuthGate`
          // من قراءة الحالة عند أوّل إطار. الاستدعاء `bootstrap()` يجري
          // داخل `AuthGate` بعد بناء الشجرة (يحتاج context آمن).
          ChangeNotifierProvider(create: (_) => AuthProvider(AuthService())),
          // تفضيل المستخدم لطريقة عرض الأقسام (قائمة / شبكة 3 في صفّ).
          // يُحمَّل من SharedPreferences مبكراً حتى تظهر الواجهة بالنمط
          // الصحيح منذ أوّل إطار.
          ChangeNotifierProvider(
            create: (_) => SectionsLayoutProvider()..loadFromPrefs(),
          ),
          ChangeNotifierProvider(
            create: (_) => ReaderProvider(
              locator<GetLastPageUsecase>(),
              locator<SaveLastPageUsecase>(),
            ),
          ),
          ChangeNotifierProvider(
            create: (_) => NotificationProvider(
              locator<GetNotificationsUseCase>(),
              locator<MarkNotificationReadUseCase>(),
              locator<MarkAllNotificationsReadUseCase>(),
              locator<DeleteNotificationUseCase>(),
              locator<GetUnreadCountUseCase>(),
              locator<NotificationRepo>(),
              locator<FirebaseNotificationDatasource>(),
            ),
          ),
          ChangeNotifierProvider(
            create: (_) => SavedProvider(
              locator<ToggleSavedUseCase>(),
              locator<GetSavedItemsUseCase>(),
              locator<IsSavedUseCase>(),
              locator<RemoveSavedUseCase>(),
            ),
          ),
          ChangeNotifierProvider(
            create: (_) => SearchProvider(
              locator<SearchContentUseCase>(),
              locator<GetSectionsUseCase>(),
              locator<GetSectionContentUseCase>(),
            ),
          ),
          ChangeNotifierProvider(
            create: (_) => HomeProvider(
              locator<GetHomeDataUseCase>(),
            ),
          ),
          // ── صفحة "لك" (For You) ──────────────────────────────
          // InteractionTracker يحتفظ بميول المستخدم محلّياً (نوع المحتوى
          // والقسم) عبر SharedPreferences، وForYouProvider يستهلكها
          // لبناء خلاصة مُرجّحة. كلاهما منعزل تمامًا عن HomeProvider
          // ولا يُعدّل أيّ منطق في الصفحة الرئيسية.
            ChangeNotifierProvider(
              create: (context) => MediaDownloadProvider(
              locator<StartDownloadUseCase>(),
              locator<PauseDownloadUseCase>(),
              locator<ResumeDownloadUseCase>(),
              locator<CancelDownloadUseCase>(),
              locator<DeleteDownloadUseCase>(),
              locator<GetDownloadStatusUseCase>(),
              locator<DownloadRepository>(),
              locator<EnsureSavedUseCase>(),
              context.read<SavedProvider>(),
            )..restoreDownloads(),
          ),
        ],
        child: const MyApp(),
      ),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    _initialization();
  }

  void _initialization() async {
    // Firebase وجميع الخدمات تهيّأت قبل runApp — لا حاجة لانتظار اصطناعيّ.
    // نُزيل النسخة الأصليّة من شاشة الإطلاق فوراً حتى يُجسّد Flutter
    // SplashScreen بأسرع وقت ممكن، ثمّ تتولّى هي التحكّم في مدّة العرض.
    FlutterNativeSplash.remove();
  }

  @override
  Widget build(BuildContext context) {
    final isArabic = context.locale.languageCode == 'ar';
    final themeProvider = context.watch<ThemeProvider>();
    return ScreenUtilInit(
      designSize: const Size(375, 812),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MaterialApp(
          // مفتاح Navigator العمومي — يتيح للمُوجِّه `NotificationNavigator`
          // فتح الشاشات عند الضغط على الإشعارات حتى إن جاء الحدث من خارج
          // شجرة الـ widgets (مثلاً من FirebaseMessaging.onMessageOpenedApp).
          navigatorKey: NotificationNavigator.instance.navigatorKey,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeProvider.themeMode,
          debugShowCheckedModeBanner: false,
          locale: context.locale,
          supportedLocales: context.supportedLocales,
          localizationsDelegates: context.localizationDelegates,
          builder: (context, child) {
            // نحلّ السمة الفعليّة بحسب الوضع المختار + سطوع النظام
            // (يدعم وضع "تلقائيّ حسب النظام").
            final platformBrightness = MediaQuery.platformBrightnessOf(context);
            final theme = themeProvider.resolveIsDark(platformBrightness)
                ? AppTheme.darkTheme
                : AppTheme.lightTheme;
            return AnimatedTheme(
              data: theme,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: Directionality(
                textDirection: isArabic
                    ? ui.TextDirection.rtl
                    : ui.TextDirection.ltr,
                child: child!,
              ),
            );
          },

          home: const SplashScreen(),
        );
      },
    );
  }
}
