import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:easy_localization/easy_localization.dart';
import 'package:floating/floating.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nebras_mobile_app/core/di/setup_locator.dart';
import 'package:nebras_mobile_app/core/extensions/sized_boxextension.dart';
import 'package:nebras_mobile_app/core/media/content_context.dart';
import 'package:nebras_mobile_app/core/services/recommendation_engine.dart';
import 'package:nebras_mobile_app/core/theme/color_manager.dart';
import 'package:nebras_mobile_app/core/theme/text_styles.dart';
import 'package:nebras_mobile_app/core/widgets/app_bar_widget.dart';
import 'package:nebras_mobile_app/core/widgets/content_section_breadcrumb_nav.dart';
import 'package:nebras_mobile_app/core/widgets/horizental_contentlist_widget.dart';
import 'package:nebras_mobile_app/core/widgets/related_content_list.dart';
import 'package:nebras_mobile_app/core/services/interest_profile_service.dart';
import 'package:nebras_mobile_app/core/services/user_behavior_tracker.dart';
import 'package:nebras_mobile_app/features/content/model/content_model.dart';
import 'package:nebras_mobile_app/features/content/view/content_router.dart.dart';
import 'package:nebras_mobile_app/features/download/provider/media_download_provider.dart';
import 'package:nebras_mobile_app/features/download/view/download_button_widget.dart';
import 'package:nebras_mobile_app/features/home/providers/home_provider.dart';
import 'package:nebras_mobile_app/features/reader/view/widgets/descripetion_widget.dart';
import 'package:nebras_mobile_app/features/search/domain/usecase/get_section_content_usecase.dart';
import 'package:nebras_mobile_app/features/video_player/data/datasources/video_player_datasource.dart';
import 'package:nebras_mobile_app/features/video_player/provider/video_player_provider.dart';
import 'package:nebras_mobile_app/features/video_player/view/widgets/media_player_widget.dart';
import 'package:nebras_mobile_app/features/video_player/view/widgets/video_player.widget.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

/// VideoPlayerScreen — StatelessWidget wrapper
/// Creates ChangeNotifierProvider ABOVE the stateful view
/// so the provider exists before initState runs.
class VideoPlayerScreen extends StatelessWidget {
  final String source;
  final String videoId;
  final String title;
  final String? thumbnailUrl;
  final String? section;
  final String? subSection;
  final String? description;

  /// Optional callback — called when video finishes playing
  final VoidCallback? onVideoCompleted;

  /// سياق فتح المشغّل (For You / Search / Section / …). يقود منطق
  /// Smart Auto-Play: حين لا يتبقَّ عنصر تالٍ في القائمة، نطلب مقاطع
  /// مشابهة فقط إذا كان السياق يسمح بذلك.
  final ContentContext contentContext;

  const VideoPlayerScreen({
    super.key,
    required this.source,
    required this.videoId,
    required this.title,
    this.thumbnailUrl,
    this.onVideoCompleted,
    this.section,
    this.subSection,
    this.description,
    this.contentContext = ContentContext.section,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<VideoPlayerProvider>(
      create: (_) {
        final provider = locator<VideoPlayerProvider>();
        provider.onVideoCompleted = onVideoCompleted;
        provider.setContentContext(contentContext);
        return provider;
      },
      child: _VideoPlayerView(
        source: source,
        videoId: videoId,
        title: title,
        thumbnailUrl: thumbnailUrl,
        section: section,
        subSection: subSection,
        description: description,
        contentContext: contentContext,
      ),
    );
  }
}

/// _VideoPlayerView — internal StatefulWidget
/// Provider is guaranteed to exist above this widget.
class _VideoPlayerView extends StatefulWidget {
  final String source;
  final String videoId;
  final String title;
  final String? thumbnailUrl;
  final String? section;
  final String? subSection;
  final String? description;
  final ContentContext contentContext;

  const _VideoPlayerView({
    required this.source,
    required this.videoId,
    required this.title,
    this.thumbnailUrl,
    this.section,
    this.subSection,
    this.description,
    required this.contentContext,
  });

  @override
  State<_VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<_VideoPlayerView>
    with WidgetsBindingObserver {
  List<Content> _relatedVideos = [];
  late bool _isYouTube;
  late Content _activeContent;
  VoidCallback? _providerSyncListener;

  /// Floating / PiP controller — متوفّر على Android فقط. على iOS نتركه
  /// خامداً ونعتمد على آليّة video_player الأصليّة. يُستعمل حصراً من
  /// زرّ التصغير اليدويّ في شريط التحكّم (لا توجد آليّة auto-on-back
  /// بعد الآن — ذلك كان يوقع المستخدم في فخّ التنقّل).
  final Floating _floating = Floating();

  /// يبني عنصرًا مرجعيًّا من حقول الـ widget — يُمرَّر إلى
  /// [RelatedContentList] ليُغذّي محرّك التوصيات بعنوان وقسم ونوع.
  Content get _referenceContent => Content(
    id: _activeContent.id,
    title: _activeContent.title,
    author: '',
    description: _activeContent.description,
    type: _activeContent.type,
    thumbnailUrl: _activeContent.thumbnailUrl,
    section: _activeContent.section,
    subSection: _activeContent.subSection,
    sectionName: _activeContent.sectionName,
    sourceUrl: _activeContent.sourceUrl,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
    createdBy: '',
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _activeContent = Content(
      id: widget.videoId,
      title: widget.title,
      author: '',
      description: widget.description ?? '',
      type: VideoPlayerDatasource.isYouTubeUrl(widget.source)
          ? ContentType.youtube
          : ContentType.video,
      thumbnailUrl: widget.thumbnailUrl ?? '',
      section: widget.section ?? '',
      subSection: widget.subSection,
      sectionName: widget.section,
      sourceUrl: widget.source,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      createdBy: '',
    );
    _isYouTube = _activeContent.type == ContentType.youtube;

    // ─── Smart Auto-Play wiring ───────────────────────────────────
    // نُثبّت السياق + fetcher حقيقيّ على الـ Provider. عند انتهاء آخر
    // مقطع في القائمة و allowsSmartAutoPlay يستدعيه الـ Provider.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<VideoPlayerProvider>();
      provider.setContentContext(widget.contentContext);
      provider.onSimilarContentNeeded = _fetchSimilarVideo;
      _providerSyncListener ??= _syncFromProvider;
      provider.addListener(_providerSyncListener!);
    });

    _loadRelatedContent();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if ((_activeContent.sourceUrl?.trim().isNotEmpty ?? false)) {
        final provider = context.read<VideoPlayerProvider>();

        final downloadProvider = context.read<MediaDownloadProvider>();
        final localPath = downloadProvider.getLocalPath(_activeContent.id);
        String source = _activeContent.sourceUrl ?? '';

        if (localPath != null) {
          final file = File(localPath);
          if (file.existsSync()) {
            final size = file.lengthSync();
            debugPrint("VIDEO SIZE: $size");
            if (size > 500000) {
              source = localPath;
            }
          }
        }

        // نربط زرّ PiP اليدويّ (في شريط التحكّم) بـ `_enterPipManually`
        // ليُستعمل نفس instance من `Floating`. لا نُسلّح PiP تلقائياً
        // عند مغادرة التطبيق؛ التصغير يحصل حصراً عند ضغط المستخدم على
        // الزرّ. بذلك يبقى زرّ "الرجوع" يعمل طبيعيّاً ويتصفّح المستخدم
        // التطبيق بحرّيّة تامّة.
        provider.onPipRequested = _enterPipManually;
        final initialItem = source == (_activeContent.sourceUrl ?? '')
            ? _activeContent
            : Content(
                id: _activeContent.id,
                title: _activeContent.title,
                author: _activeContent.author,
                description: _activeContent.description,
                type: _activeContent.type,
                thumbnailUrl: _activeContent.thumbnailUrl,
                section: _activeContent.section,
                subSection: _activeContent.subSection,
                sectionName: _activeContent.sectionName,
                sourceUrl: source,
                sizeInBytes: _activeContent.sizeInBytes,
                createdAt: _activeContent.createdAt,
                updatedAt: _activeContent.updatedAt,
                createdBy: _activeContent.createdBy,
              );
        await provider.loadPlaylist(playlist: [initialItem], startIndex: 0);
      }
    });

    debugPrint("VIDEO ID: ${_activeContent.id}");
    debugPrint("VIDEO SOURCE: ${_activeContent.sourceUrl}");
    debugPrint("IS YOUTUBE: $_isYouTube");
  }

  Future<void> _loadRelatedContent() async {
    if (_activeContent.section.trim().isEmpty) return;

    try {
      final useCase = locator<GetSectionContentUseCase>();
      final sectionId = _activeContent.subSection ?? _activeContent.section;
      final allContent = await useCase(sectionId);

      final related = allContent
          .where(
            (c) =>
                (c.type == ContentType.video ||
                    c.type == ContentType.youtube ||
                    c.type == ContentType.audio ||
                    c.type == ContentType.book) &&
                c.id != _activeContent.id,
          )
          .toList();

      if (mounted && related.isNotEmpty) {
        setState(() => _relatedVideos = related);

        // ── تغذية قائمة تشغيل الفيديو (Next/Previous) ──────────────
        // نحصر العناصر الفيديوهيّة المشغَّلة محلّياً فقط (بدون YouTube
        // ولا صوتيّات) ونُدرج المقطع الحاليّ في البداية ليصبح index=0
        // والبقيّة متاحة عبر زرّ "التالي".
        final videoOnly = related
            .where(
              (c) =>
                  (c.type == ContentType.video ||
                      c.type == ContentType.youtube) &&
                  (c.sourceUrl?.trim().isNotEmpty ?? false),
            )
            .toList();
        if (videoOnly.isNotEmpty && mounted) {
          context.read<VideoPlayerProvider>().setPlaylist(
            playlist: [_activeContent, ...videoOnly],
            currentIndex: 0,
          );
        }
      }
    } catch (_) {
      // optional feature — ignore errors
    }
  }

  // ─── Picture-in-Picture (Android, Manual Only) ───────────────────
  /// دخول فوريّ إلى الوضع المصغّر (PiP) — يُستعمل فقط عبر زرّ التصغير
  /// في شريط التحكّم. لم نعد نعترض زرّ الرجوع، فالمستخدم يتصفّح
  /// التطبيق بحرّيّة تامّة بعد الضغط على الرجوع.
  Future<bool> _enterPipManually() async {
    if (!Platform.isAndroid) return false;
    if (!mounted) return false;
    try {
      final available = await _floating.isPipAvailable;
      if (!available) return false;
      if (!mounted) return false;

      final mq = MediaQuery.of(context);
      final screenSize = mq.size * mq.devicePixelRatio;
      final rational = Rational.landscape();
      final height = screenSize.width ~/ rational.aspectRatio;

      await _floating.enable(
        ImmediatePiP(
          aspectRatio: rational,
          sourceRectHint: Rectangle<int>(
            0,
            (screenSize.height ~/ 2) - (height ~/ 2),
            screenSize.width.toInt(),
            height,
          ),
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// ── Smart Auto-Play: fetcher حقيقيّ للفيديو (Hybrid + Fallback) ──
  /// يُستدعى من الـ Provider عند استنزاف القائمة في سياق For You/Search.
  /// يُرشّح المخرجات على الفيديوهات فقط (Native + YouTube) مع
  /// sourceUrl فعليّ — كي لا نُدخل كتبًا/صوتيّات في قائمة فيديو.
  Future<List<Content>> _fetchSimilarVideo({
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
      bool isVideo(Content c) =>
          (c.type == ContentType.video || c.type == ContentType.youtube) &&
          (c.sourceUrl?.trim().isNotEmpty ?? false);

      final videos = ranked.where(isVideo).take(limit).toList(growable: false);
      if (videos.isNotEmpty) return videos;
      final fallback = RecommendationEngine.relatedFor(
        reference,
        pool: pool,
        limit: limit * 3,
      );
      return fallback.where(isVideo).take(limit).toList(growable: false);
    } catch (_) {
      return const <Content>[];
    }
  }

  /// يُستدعى حين يصدر `YoutubePlayerController` حالة `ended`. نعتمد
  /// نفس سياسة مسار video_player: نستدعي playNext إن وُجد تالٍ، وإلّا
  /// نترك الـ Provider يقرّر Smart Auto-Play بحسب السياق.
  Future<void> _handleYoutubeEnded() async {
    if (!mounted) return;
    final provider = context.read<VideoPlayerProvider>();
    if (provider.hasNext) {
      await provider.playNext();
      return;
    }
    if (provider.contentContext.allowsSmartAutoPlay) {
      await provider.playSimilarContent();
    }
  }

  Future<void> _onRelatedTap(Content content) async {
    unawaited(UserBehaviorTracker.instance.recordContentOpen(content));
    unawaited(InterestProfileService.instance.onContentConsumed(content));

    if (content.type != ContentType.video &&
        content.type != ContentType.youtube) {
      await ContentRouter.open(
        context,
        content,
        contentContext: widget.contentContext,
      );
      return;
    }
    final source = (content.sourceUrl ?? '').trim();
    if (source.isEmpty) {
      await ContentRouter.open(
        context,
        content,
        contentContext: widget.contentContext,
      );
      return;
    }

    final isYouTube =
        VideoPlayerDatasource.isYouTubeUrl(source) ||
        content.type == ContentType.youtube;
    setState(() {
      _activeContent = content;
      _isYouTube = isYouTube;
      _relatedVideos = [];
    });
    await context.read<VideoPlayerProvider>().loadPlaylist(
      playlist: [content],
      startIndex: 0,
    );
    await _loadRelatedContent();
  }

  void _syncFromProvider() {
    if (!mounted) return;
    final current = context.read<VideoPlayerProvider>().currentVideo;
    if (current == null) return;
    final currentSource = (current.sourceUrl ?? '').trim();
    final activeSource = (_activeContent.sourceUrl ?? '').trim();
    if (current.id == _activeContent.id && currentSource == activeSource) {
      return;
    }
    setState(() {
      _activeContent = current;
      _isYouTube =
          current.type == ContentType.youtube ||
          VideoPlayerDatasource.isYouTubeUrl(currentSource);
    });
  }

  /// على Android: لا نُوقف التشغيل عند الخلفيّة — النظام ينقلنا إلى
  /// Picture-in-Picture تلقائيّاً بفضل [OnLeavePiP] المُسلَّح سابقاً،
  /// فيتابع الفيديو عرضه في نافذة عائمة.
  /// على iOS: لا توجد نسخة آليّة لـ PiP في `video_player`، لذا نُبقي
  /// سلوك الإيقاف الحاليّ لضمان تجربة نظيفة.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (!Platform.isAndroid &&
        (state == AppLifecycleState.paused ||
            state == AppLifecycleState.inactive)) {
      try {
        context.read<VideoPlayerProvider>().pause();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    try {
      final listener = _providerSyncListener;
      final provider = context.read<VideoPlayerProvider>();
      if (listener != null) {
        provider.removeListener(listener);
      }
      provider.pause();
      provider.saveProgress(_activeContent.id);
      provider.reset();
    } catch (_) {}

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isYouTube) {
      return _buildYouTubeScaffold();
    }

    // Scaffold كامل (الوضع العادي) + نافذة PiP (وضع الصورة في الصورة).
    // في وضع PiP نعرض سطح الفيديو فقط بملء النافذة العائمة ليظلّ
    // الفيديو واضحاً بدون أيّ تحكّم أو زخرفة. زرّ الرجوع يعمل الآن
    // بشكل طبيعيّ — يُغلق الشاشة ويسمح بتصفّح التطبيق بحرّيّة بدون
    // أيّ فخّ تنقّل. التصغير يبقى متاحاً عبر زرّ PiP اليدويّ.
    return PiPSwitcher(
      childWhenDisabled: Consumer<VideoPlayerProvider>(
        builder: (context, provider, child) {
          return Scaffold(
            backgroundColor: Theme.of(context).colorScheme.surface,
            appBar: AppBarWidget(title: _activeContent.title),
            body: SafeArea(
              child: provider.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : provider.errorMessage != null
                  ? _buildErrorView(provider)
                  : _buildPlayerView(provider),
            ),
          );
        },
      ),
      childWhenEnabled: Consumer<VideoPlayerProvider>(
        builder: (context, provider, _) {
          final controller = provider.controller;
          if (controller == null || !controller.value.isInitialized) {
            return const ColoredBox(color: Colors.black);
          }
          return ColoredBox(
            color: Colors.black,
            child: Center(
              child: AspectRatio(
                aspectRatio: controller.value.aspectRatio,
                child: VideoPlayer(controller),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildYouTubeScaffold() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBarWidget(title: _activeContent.title),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // YouTube player with dark surround and subtle blur
              Stack(
                children: [
                  // Subtle background blur behind player
                  if (_activeContent.thumbnailUrl.trim().isNotEmpty)
                    Positioned.fill(
                      child: ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                        child: Image.network(
                          _activeContent.thumbnailUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox(),
                        ),
                      ),
                    ),
                  Container(
                    color: Colors.black.withValues(alpha: 0.85),
                    child: Stack(
                      children: [
                        MediaPlayerWidget(
                          source: _activeContent.sourceUrl ?? '',
                          onYoutubeEnded: _handleYoutubeEnded,
                          videoId: _activeContent.id,
                          onYoutubeProgress: (position, duration) {
                            unawaited(
                              context.read<VideoPlayerProvider>()
                                  .saveYoutubeProgress(
                                    videoId: _activeContent.id,
                                    position: position,
                                    duration: duration,
                                  ),
                            );
                          },
                        ),
                        Consumer<VideoPlayerProvider>(
                          builder: (context, provider, _) =>
                              _buildNextSuggestionOverlay(provider),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Consumer<VideoPlayerProvider>(
                builder: (context, provider, _) {
                  // إظهار الأزرار إذا وُجد سابق/تالٍ، أو كان السياق
                  // يسمح بـ Smart Auto-Play (canGoNext يتكفّل بذلك).
                  // بدون هذا الإصلاح كانت الأزرار تختفي كليًّا لأنّ
                  // ContentRouter يمرِّر playlist من عنصر واحد فقط.
                  final showPrev = provider.hasPrevious;
                  final showNext = provider.canGoNext;
                  if (!showPrev && !showNext) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          onPressed: showPrev
                              ? () => provider.playPrevious()
                              : null,
                          icon: const Icon(Icons.skip_previous_rounded),
                        ),
                        IconButton(
                          onPressed: showNext
                              ? () => provider.playNext()
                              : null,
                          icon: const Icon(Icons.skip_next_rounded),
                        ),
                      ],
                    ),
                  );
                },
              ),

              // Gradient fade from black to surface
              Container(
                height: 4.h,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black,
                      isDark
                          ? ColorsManager.darkBackground
                          : ColorsManager.background,
                    ],
                  ),
                ),
              ),

              // Info card
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOut,
                builder: (_, opacity, child) =>
                    Opacity(opacity: opacity, child: child),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 8.h),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _activeContent.title,
                        style: TextStyles.heading3(context),
                      ),
                      if (_activeContent.section.trim().isNotEmpty) ...[
                        8.sbh,
                        Text(
                          _activeContent.section,
                          style: TextStyles.greysmallText(context),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Description section
              12.sbh,
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: DescriptionSection(
                  description: _activeContent.description,
                ),
              ),

              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: ContentSectionBreadcrumbNav(content: _activeContent),
              ),

              24.sbh,
              // YouTube-style: اقتراحات شاملة (محلّي + أرشيف) أسفل المشغّل.
              RelatedContentList(
                reference: _referenceContent,
                onContentTap: _onRelatedTap,
              ),
              24.sbh,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorView(VideoPlayerProvider provider) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: ColorsManager.error, size: 48.sp),
            SizedBox(height: 16.h),

            Text(
              'Failed to load video'.tr(),
              style: TextStyles.bodyBold(context),
            ),

            SizedBox(height: 8.h),

            Text(
              provider.errorMessage ?? '',
              textAlign: TextAlign.center,
              style: TextStyles.greysmallText(context),
            ),

            SizedBox(height: 24.h),

            ElevatedButton.icon(
              onPressed: () {
                final provider = context.read<VideoPlayerProvider>();

                final downloadProvider = context.read<MediaDownloadProvider>();
                final localPath = downloadProvider.getLocalPath(
                  _activeContent.id,
                );
                final source = localPath ?? (_activeContent.sourceUrl ?? '');

                provider.initializeVideo(_activeContent.id, source);
              },
              icon: const Icon(Icons.refresh),
              label: Text('Retry'.tr()),
              style: ElevatedButton.styleFrom(
                backgroundColor: ColorsManager.primary,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
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

  Widget _buildNextSuggestionOverlay(VideoPlayerProvider provider) {
    final next = provider.nextSuggestion;
    if (!provider.showNextSuggestion || next == null) {
      return const SizedBox.shrink();
    }
    // بطاقة انتهاء الفيديو مع عداد تشغيل تلقائي؛ معزولة داخل الفيديو فقط
    // حتى لا تغيّر أي شاشة أو مشغّل آخر.
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.62),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 320.w),
            child: Container(
              margin: EdgeInsets.all(20.w),
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(18.r),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Next video in ${provider.nextSuggestionSeconds}s',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 8.h),
                  Text(
                    next.title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyles.bodyBold(
                      context,
                    ).copyWith(color: Colors.white),
                  ),
                  SizedBox(height: 12.h),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8.w,
                    runSpacing: 4.h,
                    children: [
                      TextButton(
                        onPressed: provider.cancelNextSuggestion,
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        onPressed: provider.acceptNextSuggestion,
                        child: const Text('Play now'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoStage({
    required Widget child,
    required VideoPlayerProvider provider,
  }) {
    return Stack(
      fit: StackFit.expand,
      children: [child, _buildNextSuggestionOverlay(provider)],
    );
  }

  Widget _buildMiniPlayer(VideoPlayerProvider provider) {
    return PositionedDirectional(
      end: 12.w,
      bottom: 12.h,
      child: Material(
        elevation: 10,
        borderRadius: BorderRadius.circular(12.r),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 180.w,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AspectRatio(
                aspectRatio: 16 / 9,
                child: VideoPlayerWidget(),
              ),
              ColoredBox(
                color: Colors.black,
                child: Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: EdgeInsetsDirectional.only(start: 8.w),
                        child: Text(
                          _activeContent.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11.sp,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: provider.toggleInAppMiniPlayer,
                      icon: const Icon(Icons.open_in_full, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildPlayerView(VideoPlayerProvider provider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Video player with dark surround and subtle blur
          Stack(
            children: [
              // Subtle background blur behind player
              if (_activeContent.thumbnailUrl.trim().isNotEmpty)
                Positioned.fill(
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                    child: Image.network(
                      _activeContent.thumbnailUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox(),
                    ),
                  ),
                ),
              Container(
                color: Colors.black.withValues(alpha: 0.85),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: _buildVideoStage(
                    provider: provider,
                    child: const VideoPlayerWidget(),
                  ),
                ),
              ),
            ],
          ),

          // Mini-player داخلي: لا يغادر الشاشة الحالية ولا يمس PiP النظامي؛
          // يعطي المستخدم وضعاً مصغراً يوتيوبياً فوق صفحة التفاصيل فقط.
          if (provider.isInAppMiniPlayer) _buildMiniPlayer(provider),
          // Gradient fade from black to background
          Container(
            height: 4.h,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black,
                  isDark
                      ? ColorsManager.darkBackground
                      : ColorsManager.background,
                ],
              ),
            ),
          ),

          // Info section with card style
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOut,
            builder: (_, opacity, child) =>
                Opacity(opacity: opacity, child: child),
            child: Container(
              margin: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 0),
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(16.r),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title + Download
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _activeContent.title,
                          style: TextStyles.heading3(context),
                        ),
                      ),
                      DownloadButton(
                        contentId: _activeContent.id,
                        url: _activeContent.sourceUrl ?? '',
                        contentType: 'video',
                        title: _activeContent.title,
                        imageUrl: _activeContent.thumbnailUrl,
                      ),
                    ],
                  ),
                  if (_activeContent.section.trim().isNotEmpty) ...[
                    6.sbh,
                    Text(
                      _activeContent.section,
                      style: TextStyles.greysmallText(context),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Description section with expand/collapse
          12.sbh,
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOut,
            builder: (_, opacity, child) =>
                Opacity(opacity: opacity, child: child),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: DescriptionSection(
                description: _activeContent.description,
              ),
            ),
          ),

          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            child: ContentSectionBreadcrumbNav(content: _activeContent),
          ),

          // Related videos section (same-section — سريعة ومضمونة).
          if (_relatedVideos.isNotEmpty) ...[
            24.sbh,
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 24.w),
              child: Text(
                'You may also watch'.tr(),
                style: TextStyles.heading3(context),
              ),
            ),
            12.sbh,
            HorizontalContentList(
              storageKey: 'related_videos',
              icon: Icons.play_circle_outline,
              title: 'You may also watch'.tr(),
              height: 190.h,
              itemCount: _relatedVideos.length,
              padding: EdgeInsets.symmetric(horizontal: 24.w),
              items: _relatedVideos,
              onItemTap: _onRelatedTap,
            ),
          ],

          // اقتراحات ذكيّة متنوّعة (محرّك التوصيات + الأرشيف) — YouTube-style.
          24.sbh,
          RelatedContentList(
            reference: _referenceContent,
            onContentTap: _onRelatedTap,
          ),
          24.sbh,
        ],
      ),
    );
  }
}
