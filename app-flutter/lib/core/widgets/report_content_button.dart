import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nebras_mobile_app/core/services/content_report_service.dart';
import 'package:nebras_mobile_app/core/services/hidden_content_service.dart';
import 'package:nebras_mobile_app/core/theme/text_styles.dart';
import 'package:nebras_mobile_app/features/content/model/content_model.dart';

/// زرّ «إبلاغ» أنيق بنمط YouTube: أيقونة علَم صغيرة عند الضغط عليها تفتح
/// ورقة سفليّة بخيارات تصنيف البلاغ (ملكية فكرية، جنسيّ، أطفال، عنف،
/// إرهاب، أخرى). عند الإرسال يُكتب البلاغ في `content_reports` ليظهر
/// للمالك في لوحة الإشراف.
class ReportContentButton extends StatelessWidget {
  const ReportContentButton({super.key, required this.content});

  final Content content;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextButton.icon(
      onPressed: () => _openReportSheet(context, content),
      icon: Icon(Icons.outlined_flag_rounded,
          size: 18.r, color: scheme.onSurfaceVariant),
      label: Text(
        'report_button'.tr(),
        style: TextStyles.smallText(context)
            .copyWith(color: scheme.onSurfaceVariant),
      ),
      style: TextButton.styleFrom(
        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

Future<void> _openReportSheet(BuildContext context, Content content) async {
  final reason = await showModalBottomSheet<ReportReason>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                child: Text(
                  'report_sheet_title'.tr(),
                  style: TextStyles.heading3(ctx),
                ),
              ),
              for (final r in ReportReason.values)
                ListTile(
                  leading: Icon(_iconFor(r)),
                  title: Text(r.labelKey.tr()),
                  onTap: () => Navigator.pop(ctx, r),
                ),
              SizedBox(height: 8.h),
            ],
          ),
        ),
      );
    },
  );

  if (reason == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  try {
    await ContentReportService.instance.submit(content: content, reason: reason);
    // احترامًا لرأي المُبلِّغ: نُخفي المحتوى عنه فوراً في كلّ الشاشات،
    // سواءٌ ثبتت مخالفته (يُحذف للجميع لاحقاً) أو لم تثبت.
    await HiddenContentService.instance.hide(content.id);
    if (!context.mounted) return;
    // إشعار صريح بسياسة المراجعة خلال 24 ساعة.
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('report_submitted_title'.tr()),
        content: Text('report_submitted_body'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('ok'.tr()),
          ),
        ],
      ),
    );
    // نغادر شاشة التفاصيل لأنّ المحتوى لم يَعُد يُعرَض لهذا المستخدم.
    navigator.maybePop();
  } catch (_) {
    messenger.showSnackBar(
      SnackBar(content: Text('report_failed'.tr())),
    );
  }
}

IconData _iconFor(ReportReason r) {
  switch (r) {
    case ReportReason.copyright:
      return Icons.copyright_rounded;
    case ReportReason.sexual:
      return Icons.no_adult_content_rounded;
    case ReportReason.childSafety:
      return Icons.child_care_rounded;
    case ReportReason.violence:
      return Icons.report_gmailerrorred_rounded;
    case ReportReason.terrorism:
      return Icons.dangerous_rounded;
    case ReportReason.other:
      return Icons.more_horiz_rounded;
  }
}
