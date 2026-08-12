import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:nebras_mobile_app/core/di/setup_locator.dart';
import 'package:nebras_mobile_app/core/extensions/navigation_extension.dart';
import 'package:nebras_mobile_app/core/media/content_context.dart';
import 'package:nebras_mobile_app/core/network/section_name_cache.dart';
import 'package:nebras_mobile_app/core/services/content_engagement_service.dart';
import 'package:nebras_mobile_app/core/services/interest_profile_service.dart';
import 'package:nebras_mobile_app/core/services/user_behavior_tracker.dart';
import 'package:nebras_mobile_app/core/theme/color_manager.dart';
import 'package:nebras_mobile_app/features/content/cache/content_metadata_cache.dart';
import 'package:nebras_mobile_app/features/audio_player/view/audio_player_screen.dart';
import 'package:nebras_mobile_app/features/content/model/content_model.dart';
import 'package:nebras_mobile_app/features/content/view/article_reader_screen.dart';
import 'package:nebras_mobile_app/features/content/view/image_viewer_screen.dart';
import 'package:nebras_mobile_app/features/reader/view/book_details_screen.dart';
import 'package:nebras_mobile_app/features/video_player/view/video_player_screen.dart';

/// Content Router
/// Centralized navigation to content detail screens
/// All content type routing goes through here — no if/else in widgets
class ContentRouter {
  static Future<void> open(
    BuildContext context,
    Content content, {
    ContentContext contentContext = ContentContext.section,
  }) async {
    if (!_isNavigable(context, content)) return;

    // نسجّل فتح المحتوى في "ملف السلوك" قبل أيّ I/O ثقيل. العمليّة
    // fire-and-forget ولا تعطّل الفتح لو فشل التخزين.
    unawaited(UserBehaviorTracker.instance.recordContentOpen(content));
    unawaited(
      ContentEngagementService.instance.recordContentOpened(content),
    );
    // محرّك التوصيات: +3 لأفنيتي قسم هذا المحتوى وكلماته (أعلى إشارة
    // سلوكيّة بعد البحث الصريح). مستقلّ تمامًا عن المتتبّع أعلاه.
    unawaited(InterestProfileService.instance.onContentConsumed(content));

    // Resolve section name from cache (no extra API call if cached)
    String? sectionName;
    if (content.section.isNotEmpty) {
      try {
        final cache = locator<SectionNameCache>();
        sectionName = await cache.resolve(content.section);
        // If resolved name equals the ID, fall back to sectionName from content
        if (sectionName == content.section) {
          sectionName = content.sectionName ?? content.section;
        }
      } catch (_) {
        sectionName = content.sectionName ?? content.section;
      }
    }

    if (!context.mounted) return;
    switch (content.type) {
      case ContentType.book:
        context.push(BookDetailsScreen(content: content));
        break;

      case ContentType.audio:
        debugPrint('====== الرابط الذي يتم تشغيله هو ======');
        debugPrint(content.sourceUrl ?? '');
        context.push(
          AudioPlayerScreen(
            playlist: [content],
            startIndex: 0,
            context: contentContext,
          ),
        );
        break;

      case ContentType.video:
      case ContentType.youtube:
        debugPrint('====== الرابط الذي يتم تشغيله هو ======');
        debugPrint(content.sourceUrl ?? '');
        context.push(
          VideoPlayerScreen(
            source: content.sourceUrl!,
            videoId: content.id,
            title: content.title,
            thumbnailUrl: content.thumbnailUrl,
            section: sectionName,
            subSection: content.subSection,
            description: content.description,
            contentContext: contentContext,
          ),
        );
        break;

      case ContentType.image:
        context.push(ImageViewerScreen(content: content));
        break;

      case ContentType.article:
        context.push(ArticleReaderScreen(content: content));
        break;
    }
  }

  /// Check whether the content can be navigated to.
  /// Shows a SnackBar for media content when sourceUrl is missing.
  static bool _isNavigable(BuildContext context, Content content) {
    if (ContentMetadataCache.isOfflinePreviewId(content.id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('هذا المحتوى غير متوفر بدون إنترنت'.tr()),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return false;
    }

    if (content.id.trim().toLowerCase() == 'metadata') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Audio unavailable'.tr()),
          backgroundColor: ColorsManager.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      debugPrint('Skipping invalid media item: ${content.id}');
      return false;
    }

    if (content.type == ContentType.video ||
        content.type == ContentType.youtube ||
        content.type == ContentType.audio) {
      if (content.sourceUrl == null || content.sourceUrl!.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              content.type == ContentType.audio
                  ? 'Audio unavailable'.tr()
                  : 'video_unavailable'.tr(),
            ),
            backgroundColor: ColorsManager.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
        debugPrint(
          'ContentRouter: missing sourceUrl for '
          '${content.type.name} id=${content.id}',
        );
        return false;
      }
    }
    return true;
  }
}
