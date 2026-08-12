import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nebras_mobile_app/core/extensions/sized_boxextension.dart';
import 'package:nebras_mobile_app/core/theme/text_styles.dart';
import 'package:nebras_mobile_app/core/widgets/app_bar_widget.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// رابط سياسة الخصوصية العامّ (بدون تسجيل دخول — متوافق مع Google Play).
const String kPrivacyPolicyUrl = 'https://nibras-app-website.vercel.app/privacy';

/// About Screen
/// Shows app name, mission, and version info
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  // يُقرأ من حزمة التطبيق وقت التشغيل بدل رقم ثابت قد يتعارض مع الإصدار الفعليّ.
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = info.version);
    } catch (_) {
      /* في حال تعذّر القراءة نُبقي الحقل فارغاً فلا يظهر رقم خاطئ. */
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBarWidget(title: 'About'.tr()),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              40.sbh,
              ClipRRect(
                borderRadius: BorderRadius.circular(20.r),
                child: Image.asset(
                  'assets/images/app_icon.png',
                  width: 96.w,
                  height: 96.w,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    width: 96.w,
                    height: 96.w,
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20.r),
                    ),
                    child: Icon(
                      Icons.menu_book_rounded,
                      size: 40.sp,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
              24.sbh,
              // App name
              Text('Nebras'.tr(), style: TextStyles.heading1(context)),
              8.sbh,
              // Tagline
              Text(
                'Explore the archives of knowledge'.tr(),
                style: TextStyles.body(context),
                textAlign: TextAlign.center,
              ),
              40.sbh,
              // Mission section
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  'Our Mission'.tr(),
                  style: TextStyles.heading3(context),
                ),
              ),
              12.sbh,
              Text(
                'About Mission Text'.tr(),
                style: TextStyles.body(context),
                textAlign: TextAlign.start,
              ),
              32.sbh,
              // سياسة المحتوى — تصريح متوافق مع Google Play بأنّ التطبيق
              // لا ينشر عمداً محتوًى مخالفاً، مع الإشارة لإمكانيّة الإبلاغ.
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  'content_policy_title'.tr(),
                  style: TextStyles.heading3(context),
                ),
              ),
              12.sbh,
              Text(
                'content_policy_text'.tr(),
                style: TextStyles.body(context),
                textAlign: TextAlign.start,
              ),
              32.sbh,
              // Privacy Policy — رابط عامّ يُفتح في المتصفّح الخارجيّ.
              OutlinedButton.icon(
                onPressed: () => _openPrivacyPolicy(context),
                icon: const Icon(Icons.privacy_tip_outlined),
                label: Text('Privacy Policy'.tr()),
              ),
              24.sbh,
              // Version — يُعرض فقط بعد قراءته من الحزمة (لا رقم ثابت).
              if (_version.isNotEmpty)
                Text(
                  '${'Version'.tr()} $_version',
                  style: TextStyles.greysmallText(context),
                ),
              24.sbh,
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openPrivacyPolicy(BuildContext context) async {
    final uri = Uri.parse(kPrivacyPolicyUrl);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Privacy Policy'.tr())),
      );
    }
  }
}
