import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nebras_mobile_app/core/extensions/sized_boxextension.dart';
import 'package:nebras_mobile_app/core/theme/text_styles.dart';
import 'package:nebras_mobile_app/core/widgets/auto_link_text.dart';
import 'package:nebras_mobile_app/core/widgets/smart_network_image.dart';
import 'package:nebras_mobile_app/features/content/model/content_model.dart';

/// بطاقة محتوى موحَّدة على نمط YouTube: صورة كبيرة بنسبة 16:9 في الأعلى،
/// ثمّ عنوان عريض، ثمّ سطر فرعيّ يجمع اسم القسم والمؤلِّف، ثمّ وصف من
/// سطرَيْن. تُستعمل لجميع عناصر المحتوى داخل الشاشة الرئيسيّة وشاشات
/// الأقسام بدون استثناء، فيلتزم تطابق بصريّ كامل عبر التطبيق.
class YouTubeContentCard extends StatelessWidget {
  const YouTubeContentCard({
    super.key,
    required this.content,
    required this.onTap,
    this.showDescription = true,
  });

  final Content content;
  final VoidCallback onTap;

  /// عرض سطرَيْ الوصف. تُطفَأ في الرفوف الأفقيّة ذات الارتفاع الثابت
  /// (نمط YouTube) حتى لا يتجاوز المحتوى ارتفاع البطاقة المحدَّد.
  final bool showDescription;

  IconData _typeIcon(ContentType type) {
    switch (type) {
      case ContentType.book:
        return Icons.menu_book_outlined;
      case ContentType.audio:
        return Icons.headphones_outlined;
      case ContentType.image:
        return Icons.image_outlined;
      case ContentType.article:
        return Icons.article_outlined;
      case ContentType.video:
      case ContentType.youtube:
        return Icons.play_circle_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final author = content.author.trim();
    final description = content.description.trim();
    final sectionLabel = (content.sectionName?.trim().isNotEmpty ?? false)
        ? content.sectionName!.trim()
        : '';
    final subtitleParts = <String>[
      if (sectionLabel.isNotEmpty) sectionLabel,
      if (author.isNotEmpty) author,
    ];

    return Material(
      color: theme.cardColor,
      borderRadius: BorderRadius.circular(16.r),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Thumbnail 16:9 ───────────────────────────────────────
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  SmartNetworkImage(
                    imageUrl: content.thumbnailUrl,
                    title: content.title,
                    fit: BoxFit.cover,
                    iconOverride: _typeIcon(content.type),
                  ),
                  // أيقونة دلاليّة للنوع في الزاوية لتمييز الصوت/الكتاب/الفيديو
                  // بصريّاً بنفس روح بطاقات YouTube مع شارة المدّة.
                  Positioned(
                    bottom: 8.h,
                    right: 8.w,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 8.w,
                        vertical: 4.h,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(6.r),
                      ),
                      child: Icon(
                        _typeIcon(content.type),
                        size: 16.sp,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // ── Body: title + meta + description ────────────────────
            Padding(
              padding: EdgeInsets.fromLTRB(14.w, 10.h, 14.w, 12.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    content.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyles.bodyBold(context).copyWith(
                      fontSize: 15.sp,
                      height: 1.35,
                    ),
                  ),
                  if (subtitleParts.isNotEmpty) ...[
                    6.sbh,
                    Text(
                      subtitleParts.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyles.greysmallText(context).copyWith(
                        fontSize: 12.sp,
                      ),
                    ),
                  ],
                  if (showDescription && description.isNotEmpty) ...[
                    8.sbh,
                    AutoLinkText(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5.sp,
                        color: onSurface.withValues(alpha: 0.65),
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
