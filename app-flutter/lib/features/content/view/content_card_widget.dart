import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nebras_mobile_app/core/extensions/sized_boxextension.dart';
import 'package:nebras_mobile_app/core/theme/text_styles.dart';
import 'package:nebras_mobile_app/core/widgets/auto_link_text.dart';
import 'package:nebras_mobile_app/core/widgets/smart_network_image.dart';

class ContentCardWidget extends StatelessWidget {
  const ContentCardWidget({
    super.key,
    required this.icon,
    required this.title,
    required this.imagePath,
    required this.ontap,
    this.heroTag,
    this.description,
    this.isAvailableOffline = true,
    this.isMetadataCached = false,
  });

  final IconData icon;
  final String title;
  final String imagePath;
  final VoidCallback ontap;
  final String? heroTag;

  /// وصف اختياريّ يُعرض تحت العنوان. تمّت إضافته حتى يظهر الوصف
  /// الذي يكتبه المشرف في لوحة التحكّم داخل بطاقات المحتوى بدل بقائه
  /// مخفيّاً في شاشة التفاصيل فقط.
  final String? description;
  final bool isAvailableOffline;
  final bool isMetadataCached;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      width: 160.w,
      child: GestureDetector(
        onTap: ontap,
        child: Opacity(
          // مؤشر بصري خفيف فقط: المحتوى غير المحمّل يبقى مرئياً للمعاينة
          // النصية، لكن يخفّ قليلاً كي لا يبدو جاهزاً للتشغيل أوفلاين.
          opacity: isAvailableOffline ? 1.0 : 0.72,
          child: Container(
            padding: EdgeInsets.all(12.w),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(16.r),
              border: isDark
                  ? Border.all(
                      color: Theme.of(
                        context,
                      ).dividerColor.withValues(alpha: 0.15),
                    )
                  : null,
              boxShadow: isDark
                  ? null
                  : const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
            ),
            // ── Layout هيكليّ مُحصَّن ضدّ الـ overflow ─────────────
            // الترتيب السابق كان `Thumbnail (110.h ثابت) + نصوص بـ
            // mainAxisSize.min` ما جعل الـ Column يطلب ارتفاعاً يتجاوز
            // الـ 144 بكسل التي يعطيها `flutter_screenutil` للارتفاع
            // المنزلَق (190.h ⇒ ~144 على هواتف بنسبة شاشة أصغر) فيظهر
            // RenderFlex overflowed by N pixels على Samsung S938B
            // وغيره. الحلّ: نجعل المصغَّرة `Expanded` كي تأخذ ما يتبقّى
            // بعد النصوص الفعليّة، وننقل الـ Column إلى وضع `max` كي
            // يملأ الارتفاع المفروض من الأعلى. بصريّاً متطابق مع
            // التصميم الأصليّ في الأجهزة الكبيرة، ومنضبط في الصغيرة.
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Thumbnail — يأخذ المساحة المتبقّية تلقائيّاً.
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12.r),
                    child: SizedBox(
                      width: double.infinity,
                      child: Hero(
                        tag: heroTag ?? imagePath,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            SmartNetworkImage(
                              imageUrl: imagePath,
                              title: title,
                            ),
                            // Content type icon overlay — أيقونة نوع الوسيط
                            // (كتاب/صوت/فيديو) فوق الصورة الفعليّة أو فوق
                            // العنصر النائب الذكيّ — مقصود بصريّاً.
                            Center(
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.4),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  icon,
                                  size: 24.sp,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            if (isAvailableOffline || isMetadataCached)
                              PositionedDirectional(
                                top: 6.h,
                                end: 6.w,
                                child: Container(
                                  padding: EdgeInsets.all(4.w),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(
                                      alpha: 0.45,
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    isAvailableOffline
                                        ? Icons.download_done
                                        : Icons.cloud_queue,
                                    size: 14.sp,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                8.sbh,
                // Title
                Text(
                  title,
                  style: TextStyles.bodyBold(context).copyWith(fontSize: 14.sp),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (description != null && description!.trim().isNotEmpty) ...[
                  4.sbh,
                  AutoLinkText(
                    description!.trim(),
                    style: TextStyle(
                      fontSize: 11.sp,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.6),
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
