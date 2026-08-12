import 'dart:async';
import 'dart:ui';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nebras_mobile_app/core/di/setup_locator.dart';
import 'package:nebras_mobile_app/core/extensions/sized_boxextension.dart';
import 'package:nebras_mobile_app/core/media/content_context.dart';
import 'package:nebras_mobile_app/core/services/interest_profile_service.dart';
import 'package:nebras_mobile_app/core/services/recommendation_engine.dart';
import 'package:nebras_mobile_app/core/services/user_behavior_tracker.dart';
import 'package:nebras_mobile_app/core/theme/color_manager.dart';
import 'package:nebras_mobile_app/core/widgets/app_bar_widget.dart';
import 'package:nebras_mobile_app/core/widgets/content_section_breadcrumb_nav.dart';
import 'package:nebras_mobile_app/core/widgets/related_content_list.dart';
import 'package:nebras_mobile_app/features/audio_player/provider/audio_player_provider.dart';
import 'package:nebras_mobile_app/features/audio_player/view/widgets/audio_thumbnail_card.dart';
import 'package:nebras_mobile_app/features/audio_player/view/widgets/audioo_progressbar_widget.dart';
import 'package:nebras_mobile_app/features/content/view/content_router.dart.dart';
import 'package:nebras_mobile_app/features/content/model/content_model.dart';
import 'package:nebras_mobile_app/features/download/provider/media_download_provider.dart';
import 'package:nebras_mobile_app/features/download/view/download_button_widget.dart';
import 'package:nebras_mobile_app/features/home/providers/home_provider.dart';
import 'package:nebras_mobile_app/features/reader/view/widgets/descripetion_widget.dart';
import 'package:nebras_mobile_app/features/search/domain/usecase/get_section_content_usecase.dart';
import 'package:provider/provider.dart';

/// AudioPlayerScreen — StatelessWidget wrapper
/// Creates ChangeNotifierProvider ABOVE the stateful view
/// so the provider exists before initState runs.
class AudioPlayerScreen extends StatelessWidget {
  final List<Content> playlist;
  final int startIndex;
  final ContentContext context;

  const AudioPlayerScreen({
    super.key,
    required this.playlist,
    required this.startIndex,
    this.context = ContentContext.section,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AudioPlayerProvider>(
      create: (_) => locator<AudioPlayerProvider>(),
      child: _AudioPlayerView(
        playlist: playlist,
        startIndex: startIndex,
        contentContext: this.context,
      ),
    );
  }
}

/// _AudioPlayerView — internal StatefulWidget
/// Provider is guaranteed to exist above this widget.
class _AudioPlayerView extends StatefulWidget {
  final List<Content> playlist;
  final int startIndex;
  final ContentContext contentContext;

  const _AudioPlayerView({
    required this.playlist,
    required this.startIndex,
    required this.contentContext,
  });

  @override
  State<_AudioPlayerView> createState() => _AudioPlayerViewState();
}

class _AudioPlayerViewState extends State<_AudioPlayerView>
    with WidgetsBindingObserver {
  Content get _initialAudio => widget.playlist[widget.startIndex];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Defer initialization to after first frame to avoid !_dirty assertion
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeAudio();
    });
  }

  /// يستبدل رابط البث في أي عنصر بمسار الملف المحلّي إن كان محمَّلاً.
  /// يُتيح التشغيل الكامل بلا إنترنت تماماً كما يفعل مشغّل الفيديو.
  List<Content> _resolveLocalPaths(List<Content> playlist) {
    final downloadProvider = context.read<MediaDownloadProvider>();
    return playlist.map((c) {
      final localPath = downloadProvider.getLocalPath(c.id);
      if (localPath == null) return c;
      return Content(
        id: c.id,
        title: c.title,
        author: c.author,
        description: c.description,
        type: c.type,
        thumbnailUrl: c.thumbnailUrl,
        section: c.section,
        subSection: c.subSection,
        sectionName: c.sectionName,
        sourceUrl: localPath,
        sizeInBytes: c.sizeInBytes,
        createdAt: c.createdAt,
        updatedAt: c.updatedAt,
        createdBy: c.createdBy,
      );
    }).toList(growable: false);
  }

  Future<void> _initializeAudio() async {
    if (!mounted) return;
    final provider = context.read<AudioPlayerProvider>();

    // ─── Wire Smart Auto-Play ───────────────────────────────────────
    provider.setContentContext(widget.contentContext);
    provider.onSimilarContentNeeded = _fetchSimilarAudio;

    // نُحوّل مسارات الملفات المحمّلة محلياً قبل تسليمها للمشغّل
    // حتى يعمل الصوت بلا إنترنت (مثل مشغّل الفيديو بالضبط).
    final resolvedPlaylist = _resolveLocalPaths(widget.playlist);

    try {
      await provider.loadPlaylist(
        playlist: resolvedPlaylist,
        startIndex: widget.startIndex,
        context: widget.contentContext,
      );
      // بعد نجاح تهيئة المقطع الأوّل، نضمّ المقاطع الصوتيّة المرتبطة
      // من نفس القسم إلى قائمة التشغيل. هذا ما يُفعِّل أزرار
      // (التالي/السابق) والتشغيل التلقائيّ للمقطع التالي — بدون هذه
      // الخطوة كانت القائمة تحتوي عنصراً واحداً فقط فتبقى الأزرار
      // معطّلة ولا يعمل auto-play.
      if (mounted) {
        unawaited(_loadRelatedAudios());
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load audio'.tr())));
      }
    }
  }

  /// يجلب مقاطع الصوت المرتبطة من نفس القسم/القسم الفرعيّ ويُحقن
  /// نتائجها في قائمة تشغيل الـ provider. لا نُعيد تهيئة المشغّل،
  /// فقط نوسّع القائمة عبر `setPlaylist`.
  Future<void> _loadRelatedAudios() async {
    final initial = _initialAudio;
    if (initial.section.trim().isEmpty) return;
    try {
      final useCase = locator<GetSectionContentUseCase>();
      final sectionId = initial.subSection ?? initial.section;
      final all = await useCase(sectionId);

      final relatedAudios = all
          .where(
            (c) =>
                c.type == ContentType.audio &&
                c.id != initial.id &&
                (c.sourceUrl?.trim().isNotEmpty ?? false),
          )
          .toList();

      if (!mounted || relatedAudios.isEmpty) return;

      context.read<AudioPlayerProvider>().setPlaylist(
        playlist: [initial, ...relatedAudios],
        currentIndex: 0,
      );
    } catch (_) {
      // optional enhancement — silent on failure
    }
  }

  /// ── Smart Auto-Play: fetcher حقيقيّ (RecommendationEngine + HomeProvider) ──
  /// يُستدعى من الـ Provider عند انتهاء آخر مقطع في القائمة حين
  /// يكون السياق "لك / بحث / رئيسية". يبني مخرجات مرتّبة هجينة من
  /// نفس القسم + مواضيع مشابهة، ثمّ يُفلتر على النوع الصوتيّ فقط.
  Future<List<Content>> _fetchSimilarAudio({
    required Content reference,
    required int limit,
  }) async {
    try {
      final pool = context.read<HomeProvider>().sections;
      final ranked = RecommendationEngine.hybridRelatedFor(
        reference,
        pool: pool,
        limit: limit * 3,
      );
      final audios = ranked
          .where(
            (c) =>
                c.type == ContentType.audio &&
                (c.sourceUrl?.trim().isNotEmpty ?? false),
          )
          .take(limit)
          .toList(growable: false);

      // Fallback: إن لم نجد صوتيّات عبر التوصية الهجينة، نلجأ لتوصية
      // بسيطة قائمة على `relatedFor` (وهي تستخدم كلّ المرشّحين من
      // الأقسام بدون نصفين) — يضمن ألّا نُعيد قائمة فارغة إلّا عند
      // عدم وجود أيّ محتوى صوتيّ مماثل على الإطلاق.
      if (audios.isNotEmpty) return audios;
      final fallback = RecommendationEngine.relatedFor(
        reference,
        pool: pool,
        limit: limit * 3,
      );
      return fallback
          .where(
            (c) =>
                c.type == ContentType.audio &&
                (c.sourceUrl?.trim().isNotEmpty ?? false),
          )
          .take(limit)
          .toList(growable: false);
    } catch (_) {
      return const <Content>[];
    }
  }

  Future<void> _onRelatedTap(Content content) async {
    unawaited(UserBehaviorTracker.instance.recordContentOpen(content));
    unawaited(InterestProfileService.instance.onContentConsumed(content));
    if (content.type == ContentType.audio &&
        (content.sourceUrl?.trim().isNotEmpty ?? false)) {
      await context.read<AudioPlayerProvider>().loadPlaylist(
        playlist: [content],
        startIndex: 0,
        context: widget.contentContext,
      );
      return;
    }
    await ContentRouter.open(
      context,
      content,
      contentContext: widget.contentContext,
    );
  }

  /// لا نُوقف المشغّل عند ذهاب التطبيق إلى الخلفيّة — هذا هو جوهر
  /// ميزة "Background Playback" التي أضفناها عبر `just_audio_background`.
  /// النظام يتكفّل بإظهار أزرار التحكّم في شاشة القفل ولوحة الإشعارات،
  /// وسيعود التطبيق إلى الواجهة فوراً عند الضغط على الإشعار.
  /// التركيز الصوتيّ (المكالمات/التنبيهات) يُدار تلقائيّاً عبر
  /// `audio_session` + `handleInterruptions: true` في `AudioPlayer`.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // لا شيء هنا عمداً — الخلفيّة مسموح بها ومطلوبة.
  }

  /// عند إغلاق شاشة المشغّل: نحفظ الموضع فقط. **لا نُوقف التشغيل ولا
  /// نُعيد ضبط المشغّل** — هذا هو جوهر التشغيل العميق في الخلفيّة
  /// الذي طلبه المستخدم: (أثناء تصفح التطبيق / عند الخروج للّوحة
  /// الرئيسيّة / حتى مع إطفاء شاشة الهاتف).
  ///
  /// الـ `AudioPlayer` مسجَّل Singleton في `setup_locator`، والـ
  /// `just_audio_background` يُبقي إشعار التحكّم نشطاً طالما الـ
  /// AudioSource فعّال. بالتالي يكفي أنّ الـ provider (factory) يتخلّص
  /// من اشتراكاته (Streams) عبر `super.dispose()` الموروث، بينما يظلّ
  /// المقطع يشتغل ويبقى التحكّم ظاهراً في شاشة القفل ولوحة الإشعارات.
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    try {
      final provider = context.read<AudioPlayerProvider>();
      if (provider.currentAudio != null) {
        provider.saveProgress(provider.currentAudio!.id);
      }
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AudioPlayerProvider>(
      builder: (context, provider, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final activeAudio = provider.currentAudio ?? _initialAudio;

        return Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surface,
          extendBodyBehindAppBar: true,
          appBar: AppBarWidget(title: activeAudio.title),
          body: Stack(
            children: [
              // Background blur from thumbnail
              if (activeAudio.thumbnailUrl.trim().isNotEmpty)
                Positioned.fill(
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
                    child: Image.network(
                      activeAudio.thumbnailUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox(),
                    ),
                  ),
                ),

              // Dark/light overlay
              Positioned.fill(
                child: Container(
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.7)
                      : Colors.white.withValues(alpha: 0.75),
                ),
              ),

              // Content
              SafeArea(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24.w),
                  child: Column(
                    children: [
                      const Spacer(flex: 1),

                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: const Duration(milliseconds: 500),
                        curve: Curves.easeOut,
                        builder: (_, opacity, child) =>
                            Opacity(opacity: opacity, child: child),
                        child: AudioThumbnailCard(
                          title: activeAudio.title,
                          thumbnailUrl: activeAudio.thumbnailUrl,
                        ),
                      ),

                      24.sbh,

                      DownloadButton(
                        contentId: activeAudio.id,
                        url: activeAudio.sourceUrl ?? '',
                        contentType: 'audio',
                        title: activeAudio.title,
                        imageUrl: activeAudio.thumbnailUrl,
                      ),

                      16.sbh,

                      // قسم الوصف — يُعرض هنا ليكون متاحاً للمستمع بدون
                      // الحاجة لفتح شاشة أخرى. يظهر فقط عند وجود وصف
                      // حقيقيّ، ويلتفّ تلقائياً عند الضغط على "عرض المزيد".
                      if (activeAudio.description.trim().isNotEmpty)
                        Flexible(
                          fit: FlexFit.loose,
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: DescriptionSection(
                              description: activeAudio.description,
                            ),
                          ),
                        )
                      else
                        const Spacer(flex: 1),

                      16.sbh,

                      const AudioProgressBar(),

                      ContentSectionBreadcrumbNav(content: activeAudio),

                      24.sbh,

                      IgnorePointer(
                        ignoring: provider.isLoading,
                        child: AnimatedOpacity(
                          opacity: provider.isLoading ? 0.65 : 1,
                          duration: const Duration(milliseconds: 180),
                          child: _buildControls(provider),
                        ),
                      ),

                      16.sbh,
                      RelatedContentList(
                        reference: activeAudio,
                        maxItems: 8,
                        height: 165,
                        onContentTap: _onRelatedTap,
                      ),

                      32.sbh,
                    ],
                  ),
                ),
              ),

              if (provider.isLoading)
                Positioned(
                  bottom: 140.h,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16.w,
                        vertical: 10.h,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 18.w,
                            height: 18.w,
                            child: const CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Colors.white,
                            ),
                          ),
                          10.sbw,
                          Text(
                            'Initializing audio...'.tr(),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildControls(AudioPlayerProvider provider) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Previous
        IconButton(
          onPressed: provider.hasPrevious
              ? () async {
                  await provider.playPrevious();
                }
              : null,
          icon: Icon(
            Icons.skip_previous_rounded,
            size: 36.sp,
            color: provider.hasPrevious
                ? Theme.of(context).colorScheme.onSurface
                : ColorsManager.disabled,
          ),
        ),

        // Rewind 10
        IconButton(
          icon: Icon(
            Icons.replay_10_rounded,
            size: 32.sp,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          onPressed: () {
            provider.seek(provider.position - const Duration(seconds: 10));
          },
        ),

        // Play / Pause — large centered button with animation
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (child, animation) =>
              ScaleTransition(scale: animation, child: child),
          child: Container(
            key: ValueKey(provider.isPlaying),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ColorsManager.primary,
              boxShadow: [
                BoxShadow(
                  color: ColorsManager.primary.withValues(alpha: 0.3),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: IconButton(
              icon: provider.isLoading
                  ? SizedBox(
                      width: 28.w,
                      height: 28.w,
                      child: const CircularProgressIndicator(
                        strokeWidth: 2.6,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      provider.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white,
                    ),
              iconSize: 48.sp,
              onPressed: provider.isLoading
                  ? null
                  : () => provider.togglePlayPause(),
            ),
          ),
        ),

        // Forward 10
        IconButton(
          icon: Icon(
            Icons.forward_10_rounded,
            size: 32.sp,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          onPressed: () {
            provider.seek(provider.position + const Duration(seconds: 10));
          },
        ),

        // Next — يعتمد canGoNext بدل hasNext وحده. في سياق
        // "لك/البحث/الرئيسية" يبقى الزرّ نشطًا حتى لو كانت القائمة
        // من عنصر واحد، ليُطلق ضغطه playSimilarContent() تلقائيًّا
        // عبر provider.playNext() (راجع المنطق في الـ Provider).
        IconButton(
          onPressed: provider.canGoNext
              ? () async {
                  await provider.playNext();
                }
              : null,
          icon: Icon(
            Icons.skip_next_rounded,
            size: 36.sp,
            color: provider.canGoNext
                ? Theme.of(context).colorScheme.onSurface
                : ColorsManager.disabled,
          ),
        ),
      ],
    );
  }
}
