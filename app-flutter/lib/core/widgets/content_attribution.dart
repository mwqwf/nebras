import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nebras_mobile_app/core/theme/text_styles.dart';
import 'package:nebras_mobile_app/features/content/model/content_model.dart';
import 'package:url_launcher/url_launcher.dart';

/// سطر إسناد المصدر والرخصة — شفافيّة الحقوق. يُعرَض فقط حين تتوفّر بيانات
/// المصدر/الرخصة من اللوحة، فلا يشغل مساحة على المحتوى القديم الذي لم
/// تُضبط له هذه الحقول بعد. وجوده يطمئن المراجع والمستخدم أنّ المحتوى
/// مُسنَد لمصدر ملكيّة عامّة/مرخّص.
class ContentAttribution extends StatelessWidget {
  const ContentAttribution({super.key, required this.content});

  final Content content;

  @override
  Widget build(BuildContext context) {
    final source = content.sourceName.trim();
    final license = content.licenseName.trim();
    final licenseUrl = content.licenseUrl.trim();
    if (source.isEmpty && license.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final style = TextStyles.smallText(context)
        .copyWith(color: scheme.onSurfaceVariant);

    final parts = <String>[];
    if (source.isNotEmpty) parts.add('${'attribution_source'.tr()}: $source');
    if (license.isNotEmpty) {
      parts.add('${'attribution_license'.tr()}: $license');
    }

    final text = Text(parts.join('  ·  '), style: style);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      child: Row(
        children: [
          Icon(Icons.verified_outlined,
              size: 16.r, color: scheme.onSurfaceVariant),
          SizedBox(width: 6.w),
          Expanded(
            child: licenseUrl.isEmpty
                ? text
                : InkWell(
                    onTap: () => _open(licenseUrl),
                    child: text,
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
