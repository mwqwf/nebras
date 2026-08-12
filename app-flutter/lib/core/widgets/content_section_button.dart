import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nebras_mobile_app/core/services/section_router.dart';
import 'package:nebras_mobile_app/features/content/model/content_model.dart';
import 'package:nebras_mobile_app/features/home/providers/home_provider.dart';
import 'package:provider/provider.dart';

/// زرّ «القسم»: يعرض اسم القسم الذي ينتمي إليه المحتوى (الأكثر تحديداً)،
/// والضغط عليه يفتح شاشة القسم مع مسار صعود كامل في الهرم (محتوى القسم →
/// الأقسام الثانويّة → الفرعيّة → الرئيسيّة) عبر [SectionRouter.openContentTrail].
///
/// يُخفي نفسه تلقائيّاً إن تعذّر تحديد القسم (محتوى لم تصل شجرته بعد)، فلا
/// يظهر زرّ معطَّل. يُستعمل في جميع شاشات تفاصيل المحتوى لتوحيد التجربة.
class ContentSectionButton extends StatelessWidget {
  const ContentSectionButton({super.key, required this.content});

  final Content content;

  @override
  Widget build(BuildContext context) {
    // نراقب HomeProvider كي يظهر الزرّ تلقائيّاً فور وصول شجرة الأقسام
    // (مثلاً عند فتح المحتوى من إشعار قبل اكتمال تحميل الرئيسية).
    context.watch<HomeProvider>();
    final leaf = SectionRouter.resolveLeafSection(context, content);
    final label = (leaf?.title.trim().isNotEmpty ?? false)
        ? leaf!.title.trim()
        : (content.sectionName?.trim() ?? '');
    if (leaf == null || label.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12.r),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => SectionRouter.openContentTrail(context, content),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.folder_open_rounded,
                size: 18.r,
                color: scheme.primary,
              ),
              SizedBox(width: 8.w),
              Flexible(
                child: Text(
                  '${'content_section_label'.tr()}: $label',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(width: 4.w),
              Icon(
                Icons.open_in_new_rounded,
                size: 16.r,
                color: scheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
