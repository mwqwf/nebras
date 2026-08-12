import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nebras_mobile_app/core/di/setup_locator.dart';
import 'package:nebras_mobile_app/core/extensions/navigation_extension.dart';
import 'package:nebras_mobile_app/core/extensions/sized_boxextension.dart';
import 'package:nebras_mobile_app/core/media/content_context.dart';
import 'package:nebras_mobile_app/core/services/guest_account_prompt_service.dart';
import 'package:nebras_mobile_app/core/services/interest_profile_service.dart';
import 'package:nebras_mobile_app/core/services/user_behavior_tracker.dart';
import 'package:nebras_mobile_app/core/theme/color_manager.dart';
import 'package:nebras_mobile_app/core/theme/text_styles.dart';
import 'package:nebras_mobile_app/core/widgets/empty_state_widget.dart';
import 'package:nebras_mobile_app/core/widgets/section_lifecycle_tracker.dart';
import 'package:nebras_mobile_app/core/widgets/skeleton_loader.dart';
import 'package:nebras_mobile_app/core/widgets/youtube_content_card.dart';
import 'package:nebras_mobile_app/core/widgets/youtube_section_card.dart';
import 'package:nebras_mobile_app/core/data/content_ordering.dart';
import 'package:nebras_mobile_app/features/content/model/content_model.dart';
import 'package:nebras_mobile_app/features/auth/provider/auth_provider.dart';
import 'package:nebras_mobile_app/features/content/view/content_router.dart.dart';
import 'package:nebras_mobile_app/features/home/data/home_section_model.dart';
import 'package:nebras_mobile_app/features/home/providers/home_provider.dart';
import 'package:nebras_mobile_app/features/home/view/widgets/home_rails_sliver.dart';
import 'package:nebras_mobile_app/features/notifications/data/firebase_notification_datasource.dart';
import 'package:nebras_mobile_app/features/notifications/model/notification_model.dart';
import 'package:nebras_mobile_app/features/notifications/provider/notfication_provider.dart';
import 'package:nebras_mobile_app/features/notifications/view/notification_screen.dart';
import 'package:nebras_mobile_app/features/search/view/search_screen.dart';
import 'package:provider/provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  VoidCallback? _authReadyListener;

  /// اشتراك على ستريم الإشعارات الواردة من FCM. حزام أمان: عند وصول
  /// إشعار "content_added" أو "section_created" نُجبر HomeProvider على
  /// إعادة الاشتراك لضمان ظهور التغيير حتى لو تأخّر push من Firebase.
  StreamSubscription<NotificationModel>? _fcmSub;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<HomeProvider>();
      // اشتراك مباشر مع Firebase — أيّ محتوى جديد من لوحة التحكّم يصل
      // فوراً بدون الحاجة للمسح أو إعادة تشغيل التطبيق.
      // ننتظر حتى تصبح حالة المصادقة signedIn قبل الاستماع للـ Firebase.
      final auth = context.read<AuthProvider>();

      // التخصيص مفعَّل لأصحاب الحسابات فقط (user != null). الضيف يرى
      // الأحدث/الأكثر مشاهدة دون أيّ رفوف شخصيّة.
      provider.setPersonalizationEnabled(auth.user != null);

      if (auth.isSignedIn) {
        provider.startWatching();
      }
      // مستمع دائم: يحافظ على تزامن التخصيص مع حالة الحساب (دخول الضيف
      // بحساب حقيقيّ لاحقاً يُفعّل الرفوف الشخصيّة فوراً)، ويبدأ الاشتراك
      // عند توفّر الجلسة.
      _authReadyListener = () {
        if (!mounted) return;
        provider.setPersonalizationEnabled(auth.user != null);
        if (auth.isSignedIn) provider.startWatching();
      };
      auth.addListener(_authReadyListener!);

      // رسالة دعوة الضيف لإنشاء حساب (مقنَّنة 2–3 مرّات يوميّاً).
      _maybeShowGuestPrompt(auth);

      // حزام أمان FCM.
      // ننتظر اكتمال تهيئة FirebaseNotificationDatasource (يحدث في
      // `_warmUpDeferredServices` بشكل غير متزامن مع بناء الواجهة) قبل
      // الاشتراك حتى لا نضيع إشعاراً يصل خلال نافذة الإقلاع الأولى.
      _attachFcmListenerWhenReady();

      // Idle Auto-Suggest: نُطلق المؤقّت بعد إطار البناء الأوّل ليبدأ
      // العدّ من لحظة جاهزيّة الشاشة، لا من لحظة بناء الـ Provider.
      provider.resetIdleTimer();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // عند عودة التطبيق إلى المقدّمة بعد فترة طويلة، نُعيد الاشتراك لضمان
    // تزامن فوريّ — listeners Firebase تعمل في الأغلب، لكن الاشتراك الجديد
    // يرسل snapshot كامل دفعة واحدة.
    if (state == AppLifecycleState.resumed && mounted) {
      final auth = context.read<AuthProvider>();
      if (auth.isSignedIn) {
        context.read<HomeProvider>().startWatching();
      }
    }
  }

  @override
  void dispose() {
    final listener = _authReadyListener;
    if (listener != null) {
      context.read<AuthProvider>().removeListener(listener);
      _authReadyListener = null;
    }
    _fcmSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    // Trigger pagination slightly before reaching the end for smoother UX.
    if (position.pixels >= position.maxScrollExtent - 250) {
      context.read<HomeProvider>().loadMore();
    }
    // أيّ تمرير يُعدّ تفاعلًا — يُلغي عرض الاقتراحات إن كانت ظاهرة
    // ويُعيد عدّ مؤقّت الخمول من الصفر.
    context.read<HomeProvider>().resetIdleTimer();
  }

  /// يعرض رسالة لطيفة تدعو الضيف لإنشاء حساب ليحصل على تجربة مخصّصة
  /// (توصيات، تابع التصفّح، مزامنة). مقنَّنة عبر [GuestAccountPromptService]
  /// لتظهر مرّتين إلى ثلاث مرّات يوميّاً فقط. لأصحاب الحسابات لا تظهر أبداً.
  Future<void> _maybeShowGuestPrompt(AuthProvider auth) async {
    if (auth.user != null) return; // مستخدم حقيقيّ — لا رسالة.
    final shouldShow = await GuestAccountPromptService.instance.shouldShow();
    if (!shouldShow || !mounted) return;
    await GuestAccountPromptService.instance.recordShown();
    if (!mounted) return;
    // نستعمل MaterialBanner (أعلى الشاشة) بدل SnackBar العائم: الأخير كان
    // يطفو فوق شريط التنقّل السفليّ فيحجب أزراره. الـ Banner يدفع المحتوى
    // للأسفل ولا يغطّي أيّ زرّ، ويبقى حتى يتفاعل المستخدم.
    final messenger = ScaffoldMessenger.of(context);
    final scheme = Theme.of(context).colorScheme;
    messenger.clearMaterialBanners();
    messenger.showMaterialBanner(
      MaterialBanner(
        backgroundColor: ColorsManager.primary.withValues(alpha: 0.12),
        leading: Icon(Icons.person_add_alt_1_rounded, color: scheme.primary),
        content: Text(
          'guest_prompt_message'.tr(),
          style: TextStyles.body(context),
        ),
        actions: [
          TextButton(
            onPressed: () => messenger.hideCurrentMaterialBanner(),
            child: Text('guest_prompt_dismiss'.tr()),
          ),
          FilledButton(
            onPressed: () {
              messenger.hideCurrentMaterialBanner();
              unawaited(context.read<AuthProvider>().signInWithGoogle());
            },
            child: Text('guest_prompt_action'.tr()),
          ),
        ],
      ),
    );
  }

  /// نشتركّ على ستريم الإشعارات بعد ما يكتمل `initialize()` في
  /// FirebaseNotificationDatasource. إذا فشل التهيئة (مثلاً Google Play
  /// Services مفقود على المُحاكي) فإنّ الـ Future سيرمي خطأ نلتقطه ولا
  /// نُسقط الشاشة.
  Future<void> _attachFcmListenerWhenReady() async {
    final notifDs = locator<FirebaseNotificationDatasource>();
    try {
      await notifDs.ready;
    } catch (e) {
      debugPrint('[HomeScreen] FCM datasource init failed: $e');
      return;
    }
    if (!mounted) return;
    _fcmSub = notifDs.notificationStream.listen((n) {
      if (!mounted) return;
      final type = n.type.toLowerCase();
      if (type == 'content_added' || type == 'section_created') {
        context.read<HomeProvider>().refresh();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SafeArea(
      // RefreshIndicator كحزام أمان — حتى عند انقطاع مؤقّت في الشبكة،
      // بإمكان المستخدم السحب للأسفل لإجبار إعادة الاشتراك فوراً.
      child: RefreshIndicator(
        onRefresh: () => context.read<HomeProvider>().refresh(),
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(8.w, 8.h, 8.w, 0),
              sliver: const SliverToBoxAdapter(child: _HomeTopBar()),
            ),
            // GreetingSection removed

            // ── Content area (state-dependent) ────────────────
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: 24.w),
              sliver: Consumer<HomeProvider>(
                builder: (context, provider, _) {
                  // Loading
                  if (provider.isLoading && provider.sections.isEmpty) {
                    return const SliverToBoxAdapter(
                      child: HomeSkeletonLoader(),
                    );
                  }

                  // Error
                  if (provider.errorMessage != null &&
                      provider.sections.isEmpty) {
                    final rawError = provider.errorMessage ?? '';
                    final isPermissionDenied = rawError.contains(
                      'Permission denied',
                    );
                    final userMessage = isPermissionDenied
                        ? 'تعذر الوصول إلى المحتوى. تأكد من تسجيل الدخول.'
                              .tr()
                        : rawError;
                    return SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.wifi_off_rounded,
                              size: 64.w,
                              color: ColorsManager.primary.withValues(
                                alpha: 0.5,
                              ),
                            ),
                            16.sbh,
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 24.w),
                              child: Text(
                                userMessage.trim().isEmpty
                                    ? 'عذراً، حدث خطأ في الاتصال بالشبكة.'
                                          .tr()
                                    : userMessage,
                                textAlign: TextAlign.center,
                                style: TextStyles.bodyBold(context).copyWith(
                                  color: Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: 0.8),
                                  height: 1.5,
                                ),
                              ),
                            ),
                            24.sbh,
                            ElevatedButton.icon(
                              onPressed: () => provider.retry(),
                              icon: const Icon(Icons.refresh),
                              label: Text(
                                'إعادة المحاولة'.tr(),
                                style: TextStyles.bodyBold(
                                  context,
                                ).copyWith(color: Colors.white),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: ColorsManager.primary,
                                padding: EdgeInsets.symmetric(
                                  horizontal: 24.w,
                                  vertical: 12.h,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12.r),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  // رفوف الصفحة الرئيسيّة — الأقدم أولاً داخل كلّ قسم فقط
                  // (content_ordering.dart). الرفوف هنا للاكتشاف (أحدث/شعبي/لك).
                  if (!provider.isLoading &&
                      provider.sections.isNotEmpty &&
                      provider.homeRails.isEmpty) {
                    return const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    );
                  }

                  if (provider.sections.isEmpty && !provider.isLoading) {
                    return SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.all(24.w),
                          child: Text(
                            'لا يوجد محتوى بعد. اسحب للأسفل للتحديث.'.tr(),
                            textAlign: TextAlign.center,
                            style: TextStyles.body(context),
                          ),
                        ),
                      ),
                    );
                  }

                  return SliverMainAxisGroup(
                    slivers: [
                      // شريط "غير متصل" — يظهر فقط حين يفشل البثّ الحيّ
                      // بينما يوجد محتوى محفوظ سابقاً (نعرضه بدل شاشة خطأ).
                      if (provider.errorMessage != null)
                        const SliverToBoxAdapter(child: _OfflineBanner()),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.only(top: 12.h, bottom: 8.h),
                          child: Text(
                            'الرئيسية'.tr(),
                            style: TextStyles.heading3(context),
                          ),
                        ),
                      ),
                      const HomeRailsSliver(),
                      SliverToBoxAdapter(
                        child: Column(
                          children: [
                            28.sbh,
                            if (provider.isFetchingMore)
                              const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

}

/// شريط تنبيه خفيف يُعرض أعلى المحتوى عند انقطاع الاتصال بينما توجد نسخة
/// محفوظة من الأقسام (من ذاكرة Firestore المحليّة). يطمئن المستخدم أنّ ما
/// يراه محتوى محفوظ، بدل إظهار شاشة خطأ فارغة.
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: EdgeInsets.only(top: 8.h),
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: scheme.outline),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 18.sp, color: scheme.onSurfaceVariant),
          12.sbw,
          Expanded(
            child: Text(
              'Offline banner'.tr(),
              style: TextStyles.smallText(context).copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// الشريط العلويّ للرئيسية على طراز YouTube:
///   • زرّ القائمة (Drawer) — يحوي الإعدادات وما إليها.
///   • اسم التطبيق في الوسط.
///   • جرس الإشعارات (مع عدّاد غير المقروء) — نُقل إلى هنا من القائمة.
///   • أيقونة بحث صغيرة — تفتح [SearchScreen] المخصّصة بكامل وظائف البحث.
///
/// الأيقونتان بنفس الحجم تماماً (لا شريط بحث عريض) كما في الشريط العلويّ
/// لـ YouTube. اتجاه الصفّ يتبع لغة الواجهة تلقائياً (RTL/LTR).
class _HomeTopBar extends StatelessWidget {
  const _HomeTopBar();

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.menu_rounded),
          tooltip: 'Menu'.tr(),
          color: onSurface,
          onPressed: () => Scaffold.of(context).openDrawer(),
        ),
        Expanded(
          child: Text(
            'Nebras'.tr(),
            style: TextStyles.heading2(context),
          ),
        ),
        // جرس الإشعارات مع عدّاد غير المقروء.
        Consumer<NotificationProvider>(
          builder: (context, notif, _) {
            final count = notif.unreadCount;
            final bell = IconButton(
              icon: const Icon(Icons.notifications_none_rounded),
              tooltip: 'Notifications'.tr(),
              color: onSurface,
              onPressed: () => context.push(const NotificationScreen()),
            );
            if (count <= 0) return bell;
            return Badge.count(count: count, child: bell);
          },
        ),
        // أيقونة البحث — بنفس حجم جرس الإشعارات تماماً.
        IconButton(
          icon: const Icon(Icons.search_rounded),
          tooltip: 'Search content...'.tr(),
          color: onSurface,
          onPressed: () => context.push(const SearchScreen()),
        ),
      ],
    );
  }
}

// _PersonalizedHomeBlock removed as it's now the main body of HomeScreen.
// _HomeRecommendationCard / _ContentTile / _SectionTile / _SectionTileChooser
// / _SectionAvatar / _SectionsSliver: جميعها استُبدِلت ببطاقتَي
// YouTubeContentCard / YouTubeSectionCard المشتركتَيْن في core/widgets،
// بالإضافة إلى [_YouTubeSectionsSliver] أدناه لتغليف القائمة بـ Sliver
// مرتّب مع padding موحَّد.

/// Sliver خفيف يلفّ قائمة YouTubeSectionCard / YouTubeContentCard بطريقة
/// منسجمة مع [CustomScrollView] داخل شاشات الأقسام/المحتوى. يحلّ محلّ
/// `_SectionsSliver` السابق الذي كان يدعم وضع الـ Grid؛ بعد توحيد العرض
/// لم تعد هناك حاجة لخيارَيْن.
class _YouTubeSectionsSliver extends StatelessWidget {
  const _YouTubeSectionsSliver({
    required this.itemCount,
    required this.itemBuilder,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: EdgeInsets.all(16.w),
      sliver: SliverList.separated(
        itemCount: itemCount,
        separatorBuilder: (_, _) => 16.sbh,
        itemBuilder: itemBuilder,
      ),
    );
  }
}

/// شاشة الأقسام الفرعية — تقرأ من HomeProvider بالـ id حتى تبقى متزامنة
/// مع الـ live stream (مثلاً يظهر قسم فرعي جديد فور إنشائه من اللوحة).
///
/// مُعلَنَة بشكل عامّ (public) حتى يستطيع مُوجِّه الإشعارات فتحها مباشرة
/// عند الضغط على إشعار "قسم جديد".
class SubSectionsScreen extends StatelessWidget {
  final String mainSectionId;

  const SubSectionsScreen({super.key, required this.mainSectionId});

  @override
  Widget build(BuildContext context) {
    return Consumer<HomeProvider>(
      builder: (context, provider, _) {
        final mainSection = provider.sections.firstWhere(
          (s) => s.id == mainSectionId,
          orElse: () => HomeSection(
            id: mainSectionId,
            title: '',
            type: 'main_section',
            items: const [],
          ),
        );
        final subSections = provider.sections
            .where(
              (s) => s.type == 'sub_section' && s.parentId == mainSectionId,
            )
            .toList();

        return SectionLifecycleTracker(
          sectionId: mainSectionId,
          sectionTitle: mainSection.title,
          child: Scaffold(
            appBar: AppBar(title: Text(mainSection.title)),
            body: _SectionsBodyWithArchiveTail(
              hasLocalContent: subSections.isNotEmpty,
              parentTitle: mainSection.title,
              emptyMessageKey: 'No subsections available',
              localSliver: subSections.isEmpty
                  ? null
                  : _YouTubeSectionsSliver(
                      itemCount: subSections.length,
                      itemBuilder: (context, index) {
                        final subSection = subSections[index];
                        return YouTubeSectionCard(
                          icon: Icons.account_tree_outlined,
                          title: subSection.title,
                          imageUrl: subSection.imageUrl,
                          onTap: () {
                            unawaited(
                              UserBehaviorTracker.instance.recordSectionBrowsed(
                                mainSectionId,
                                mainSection.title,
                              ),
                            );
                            context.push(
                              SecondarySectionsScreen(
                                subSectionId: subSection.id,
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          ),
        );
      },
    );
  }
}

class SecondarySectionsScreen extends StatelessWidget {
  final String subSectionId;

  const SecondarySectionsScreen({super.key, required this.subSectionId});

  @override
  Widget build(BuildContext context) {
    return Consumer<HomeProvider>(
      builder: (context, provider, _) {
        final subSection = provider.sections.firstWhere(
          (s) => s.id == subSectionId,
          orElse: () => HomeSection(
            id: subSectionId,
            title: '',
            type: 'sub_section',
            items: const [],
          ),
        );
        final secondarySections = provider.sections
            .where(
              (s) =>
                  (s.type == 'secondary_section' ||
                      s.type == 'secondary_sub_section') &&
                  s.parentId == subSectionId,
            )
            .toList();

        return SectionLifecycleTracker(
          sectionId: subSectionId,
          sectionTitle: subSection.title,
          child: Scaffold(
            appBar: AppBar(title: Text(subSection.title)),
            body: _SectionsBodyWithArchiveTail(
              hasLocalContent: secondarySections.isNotEmpty,
              parentTitle: subSection.title,
              emptyMessageKey: 'No secondary sections available',
              localSliver: secondarySections.isEmpty
                  ? null
                  : _YouTubeSectionsSliver(
                      itemCount: secondarySections.length,
                      itemBuilder: (context, index) {
                        final secondary = secondarySections[index];
                        return YouTubeSectionCard(
                          icon: Icons.device_hub_outlined,
                          title: secondary.title,
                          imageUrl: secondary.imageUrl,
                          onTap: () {
                            unawaited(
                              UserBehaviorTracker.instance.recordSectionBrowsed(
                                subSectionId,
                                subSection.title,
                              ),
                            );
                            unawaited(
                              InterestProfileService.instance.onSectionView(
                                secondary.id,
                                secondary.title,
                              ),
                            );
                            context.push(
                              ContentListScreen(sectionId: secondary.id),
                            );
                          },
                        );
                      },
                    ),
            ),
          ),
        );
      },
    );
  }
}

/// قائمة المحتوى داخل قسم معيّن — تقرأ من HomeProvider بالـ id حتى تبقى
/// متزامنة مع الـ live stream. عند رفع ملفّ جديد من لوحة التحكّم يظهر
/// فوراً داخل هذه الشاشة أيضاً دون الرجوع للخلف.
///
/// مُعلَنَة بشكل عامّ (public) حتى يستطيع مُوجِّه الإشعارات فتحها مباشرة.
///
/// ملاحظة: هذه الشاشة مخصّصة لأقسام Firebase فقط.
class ContentListScreen extends StatelessWidget {
  final String sectionId;

  const ContentListScreen({super.key, required this.sectionId});

  @override
  Widget build(BuildContext context) {
    return Consumer<HomeProvider>(
      builder: (context, provider, _) {
        final section = provider.sections.firstWhere(
          (s) => s.id == sectionId,
          orElse: () => HomeSection(
            id: sectionId,
            title: '',
            type: 'fallback',
            items: const [],
          ),
        );
        // ─────────────────────────────────────────────────────────────
        // ملاحظة للمطوّر — منطق الترتيب المزدوج (Dual Sorting Logic):
        //
        //   • الأقسام (main/sub/secondary): تُرتَّب **ديناميكياً**
        //     حسب سلوك المستخدم (زيارات + تصفّح + كلمات بحث) عبر
        //     `RecommendationEngine` المُطبَّق في `HomeProvider`.
        //     القسم الأكثر تفضيلاً للمستخدم يظهر في الأعلى، ولا
        //     علاقة لذلك بتاريخ الإنشاء.
        //
        //   • المحتوى داخل الأقسام (Items/Books/Videos/Audios):
        //     يُرتَّب **زمنياً** من الأقدم إلى الأحدث دائماً
        //     الأقدم أولاً عبر [compareContentOldestFirst] (createdAt ثم
        //     selectionOrder عند التعادل). انظر content_ordering.dart.
        //
        // لا تُعدّل هذا الاختلاف دون مراجعة؛ هو اختيار تصميميّ مقصود.
        // ─────────────────────────────────────────────────────────────
        final sortedItems = List<Content>.of(section.items)
          ..sort(compareContentOldestFirst);

        return SectionLifecycleTracker(
          sectionId: sectionId,
          sectionTitle: section.title,
          child: Scaffold(
            appBar: AppBar(title: Text(section.title)),
            body: _SectionsBodyWithArchiveTail(
              hasLocalContent: sortedItems.isNotEmpty,
              parentTitle: section.title,
              emptyMessageKey: 'No content in this section',
              localSliver: sortedItems.isEmpty
                  ? null
                  : SliverPadding(
                      padding: EdgeInsets.all(16.w),
                      sliver: SliverList.separated(
                        itemCount: sortedItems.length,
                        separatorBuilder: (_, _) => 16.sbh,
                        itemBuilder: (context, index) {
                          final item = sortedItems[index];
                          return YouTubeContentCard(
                            content: item,
                            onTap: () {
                              unawaited(
                                InterestProfileService.instance
                                    .onContentConsumed(item),
                              );
                              ContentRouter.open(
                                context,
                                item,
                                contentContext: ContentContext.section,
                              );
                            },
                          );
                        },
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }
}

/// غلاف جسم شاشة (SubSections / Secondary / ContentList) يجمع:
///   1) المحتوى المحلّي (Firebase) كـ Sliver — إن وُجد.
class _SectionsBodyWithArchiveTail extends StatelessWidget {
  final Widget? localSliver;
  final bool hasLocalContent;
  final String parentTitle;
  final String emptyMessageKey;

  const _SectionsBodyWithArchiveTail({
    required this.localSliver,
    required this.hasLocalContent,
    required this.parentTitle,
    required this.emptyMessageKey,
  });

  @override
  Widget build(BuildContext context) {
    if (!hasLocalContent) {
      return EmptyStateWidget(message: emptyMessageKey.tr());
    }

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (localSliver != null) localSliver!,
      ],
    );
  }
}

// تمّ حذف _SectionsSliver / _SectionTileChooser / _SectionTile /
// _ContentTile / _SectionAvatar لأنّها استبدلت ببطاقات YouTube
// المشتركة (YouTubeContentCard / YouTubeSectionCard) المُعرَّفة في
// core/widgets/ والمغلَّفة هنا بـ _YouTubeSectionsSliver للسلوك السابق.
