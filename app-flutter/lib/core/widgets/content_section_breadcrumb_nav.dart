import 'package:flutter/material.dart';
import 'package:nebras_mobile_app/core/widgets/content_attribution.dart';
import 'package:nebras_mobile_app/core/widgets/content_section_button.dart';
import 'package:nebras_mobile_app/core/widgets/report_content_button.dart';
import 'package:nebras_mobile_app/features/content/model/content_model.dart';

/// شريط إجراءات المحتوى المشترك في شاشات التفاصيل الخمس:
///   • زرّ «القسم» الذي ينتمي إليه المحتوى (يفتح القسم مع مسار صعود هرميّ).
///   • زرّ «إبلاغ» بنمط YouTube للإبلاغ عن مخالفات (ملكية فكرية، محتوى
///     جنسيّ، أطفال، عنف، إرهاب…).
///
/// كان هذا المكوّن سابقاً breadcrumb معطوباً (يحلّ الأقسام بلا البادئات
/// `sub:`/`secondary:`). وُحِّد الآن مع إبقاء الاسم حتى لا تحتاج الشاشات
/// الخمس إلى تعديل.
class ContentSectionBreadcrumbNav extends StatelessWidget {
  const ContentSectionBreadcrumbNav({super.key, required this.content});

  final Content content;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: ContentSectionButton(content: content),
              ),
            ),
            ReportContentButton(content: content),
          ],
        ),
        ContentAttribution(content: content),
      ],
    );
  }
}
