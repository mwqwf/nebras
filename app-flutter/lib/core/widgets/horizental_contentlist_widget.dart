import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nebras_mobile_app/features/content/cache/content_metadata_cache.dart';
import 'package:nebras_mobile_app/features/content/model/content_model.dart';
import 'package:nebras_mobile_app/features/content/view/content_card_widget.dart';
import 'package:nebras_mobile_app/features/content/view/content_router.dart.dart';
import 'package:nebras_mobile_app/features/download/provider/media_download_provider.dart';
import 'package:nebras_mobile_app/core/di/setup_locator.dart';
import 'package:nebras_mobile_app/core/services/hidden_content_service.dart';
import 'package:provider/provider.dart';

class HorizontalContentList extends StatelessWidget {
  final String storageKey;
  final IconData icon;
  final String title;
  final double height;
  final int itemCount;
  final EdgeInsets padding;
  final List<Content>? items;
  final FutureOr<void> Function(Content content)? onItemTap;

  const HorizontalContentList({
    super.key,
    required this.storageKey,
    required this.icon,
    required this.title,
    required this.height,
    required this.itemCount,
    required this.padding,
    this.items,
    this.onItemTap,
  });

  @override
  Widget build(BuildContext context) {
    // نراقب قائمة المحتوى المُخفى كي يختفي العنصر المُبلَّغ عنه فوراً من
    // كلّ الرفوف دون انتظار لقطة Firestore جديدة.
    final hidden = context.watch<HiddenContentService>();
    final items =
        this.items?.where((c) => !hidden.isHidden(c.id)).toList();
    final displayCount = items?.length ?? itemCount;

    return SizedBox(
      height: height,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: ListView.separated(
          physics: const BouncingScrollPhysics(),
          primary: false,
          key: PageStorageKey(storageKey),
          scrollDirection: Axis.horizontal,
          padding: padding,
          itemCount: displayCount,
          itemBuilder: (context, index) {
            final content = items?[index];
            final isMedia =
                content != null &&
                (content.type == ContentType.video ||
                    content.type == ContentType.youtube ||
                    content.type == ContentType.audio);
            final cache = locator<ContentMetadataCache>();
            final downloads = context.watch<MediaDownloadProvider>();
            final hasMetadata = content == null || cache.has(content.id);
            final hasLocalFile =
                content != null && downloads.getLocalPath(content.id) != null;
            final isOfflinePreview =
                content != null &&
                (cache.isOfflinePreview(content.id) ||
                    ContentMetadataCache.isOfflinePreviewId(content.id));
            // المحتوى القادم من الشبكة يبقى قابلاً للتشغيل عبر URL عادي؛
            // المنع يطبّق فقط على نسخة Hive الأوفلاين التي لا تضمن وجود ملف.
            final canOpenContent =
                content == null ||
                !isMedia ||
                !isOfflinePreview ||
                hasLocalFile;
            return ContentCardWidget(
              key: ValueKey('$storageKey-$index'),
              icon: icon,
              title: content?.title ?? title,
              description: content?.description,
              imagePath: content?.thumbnailUrl ?? '$storageKey-$index',
              heroTag: content != null ? 'content_${content.id}' : null,
              isAvailableOffline: !isOfflinePreview || hasLocalFile,
              isMetadataCached: content != null && hasMetadata,
              ontap: () {
                if (content != null) {
                  if (isMedia && !canOpenContent) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('هذا المحتوى غير متوفر بدون إنترنت'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    return;
                  }
                  final tapHandler = onItemTap;
                  if (tapHandler != null) {
                    final response = tapHandler(content);
                    if (response is Future<void>) {
                      unawaited(response);
                    }
                  } else {
                    ContentRouter.open(context, content);
                  }
                }
              },
            );
          },
          separatorBuilder: (BuildContext context, int index) {
            return SizedBox(width: 16.w);
          },
        ),
      ),
    );
  }
}
