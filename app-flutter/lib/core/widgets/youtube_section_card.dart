import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nebras_mobile_app/core/extensions/sized_boxextension.dart';
import 'package:nebras_mobile_app/core/theme/text_styles.dart';
import 'package:nebras_mobile_app/core/widgets/smart_network_image.dart';

/// بطاقة قسم موحَّدة على نمط YouTube: صورة كبيرة بنسبة 16:9 في الأعلى،
/// ثمّ عنوان عريض، ثمّ سطر فرعيّ اختياريّ (وصف/نوع القسم). تستعمل في
/// شاشات الأقسام الرئيسيّة/الفرعيّة/الثانويّة بدلاً من الـ Tile الصغير
/// والـ Grid Tile السابقَيْن — لتوحيد المظهر مع بطاقات المحتوى.
class YouTubeSectionCard extends StatelessWidget {
  const YouTubeSectionCard({
    super.key,
    required this.title,
    required this.icon,
    required this.onTap,
    this.imageUrl,
    this.subtitle,
  });

  final String title;
  final IconData icon;
  final String? imageUrl;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasSubtitle = (subtitle ?? '').trim().isNotEmpty;

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
            AspectRatio(
              aspectRatio: 16 / 9,
              child: SmartNetworkImage(
                imageUrl: imageUrl,
                title: title,
                fit: BoxFit.cover,
                iconOverride: icon,
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(14.w, 12.h, 14.w, 14.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(
                        icon,
                        size: 18.sp,
                        color: theme.colorScheme.primary,
                      ),
                      8.sbw,
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyles.bodyBold(context).copyWith(
                            fontSize: 15.sp,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (hasSubtitle) ...[
                    6.sbh,
                    Text(
                      subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyles.greysmallText(context).copyWith(
                        fontSize: 12.sp,
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
