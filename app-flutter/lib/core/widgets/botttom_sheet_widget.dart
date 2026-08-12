import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nebras_mobile_app/core/extensions/navigation_extension.dart';
import 'package:nebras_mobile_app/core/extensions/sized_boxextension.dart';
import 'package:nebras_mobile_app/core/theme/color_manager.dart';
import 'package:nebras_mobile_app/core/theme/provider/theme_provider.dart';
import 'package:nebras_mobile_app/core/theme/text_styles.dart';
import 'package:nebras_mobile_app/core/widgets/build_handel.dart';
import 'package:nebras_mobile_app/core/widgets/settings_tile.dart';
import 'package:nebras_mobile_app/core/services/personalization_reset_service.dart';
import 'package:nebras_mobile_app/features/auth/provider/auth_provider.dart';
import 'package:nebras_mobile_app/features/home/providers/home_provider.dart';
import 'package:nebras_mobile_app/features/home/view/language_screen.dart';
import 'package:nebras_mobile_app/features/home/view/about_screen.dart';
import 'package:nebras_mobile_app/features/notifications/provider/notfication_provider.dart';
import 'package:provider/provider.dart';

class SettingsBottomSheetWidget extends StatelessWidget {
  const SettingsBottomSheetWidget({super.key, this.asDrawerPanel = false});

  final bool asDrawerPanel;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: asDrawerPanel ? null : MediaQuery.of(context).size.height * 0.92,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: asDrawerPanel
            ? BorderRadius.zero
            : BorderRadius.vertical(top: Radius.circular(16.r)),
      ),
      child: Column(
        children: [
          if (!asDrawerPanel) ...[
            8.sbh,
            BuildHandelWidget(),
            8.sbh,
          ] else
            16.sbh,
          Text('Settings'.tr(), style: TextStyles.heading3(context)),
          24.sbh,
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(horizontal: 24.w),
              children: [
                SettingsTile(
                  icon: Icons.language_outlined,
                  title: "Language".tr(),
                  onTap: () {
                    context.push(const LanguageScreen());
                  },
                ),
                SettingsTile(
                  icon: Icons.dark_mode_rounded,
                  title: "Dark Mode".tr(),
                  trailing: Switch(
                    value: context.watch<ThemeProvider>().isDarkMode,
                    onChanged: (value) {
                      context.read<ThemeProvider>().toggleTheme();
                    },
                  ),
                ),
                // مفتاح التحكّم المركزيّ بإشعارات FCM. إيقافه يُلغي الاشتراك
                // من مواضيع البثّ ويحذف رمز الجهاز كي لا تصل أيّ إشعارات
                // — كما طلبنا في مواصفات إدارة الإشعارات.
                Consumer<NotificationProvider>(
                  builder: (context, notif, _) => SettingsTile(
                    icon: Icons.notifications_active_outlined,
                    title: "Push Notifications".tr(),
                    trailing: Switch(
                      value: notif.isPushEnabled,
                      onChanged: notif.isTogglingPush
                          ? null
                          : (value) => notif.setPushEnabled(value),
                    ),
                  ),
                ),
                SettingsTile(
                  icon: Icons.info_outline_rounded,
                  title: "About".tr(),
                  onTap: () {
                    context.push(const AboutScreen());
                  },
                ),
                SettingsTile(
                  icon: Icons.privacy_tip_outlined,
                  title: 'forget_interests_title'.tr(),
                  subtitle: 'forget_interests_subtitle'.tr(),
                  onTap: () => _confirmForgetInterests(context),
                ),
                // فاصل بصري ثم خيار تسجيل الخروج. نعرضه فقط حين يكون
                // المستخدم مسجّلاً (الحال الطبيعي عند وصوله لهذه الشاشة)
                // — نتركه أحمر ليُميّز طبيعته بوضوح.
                if (context.watch<AuthProvider>().isSignedIn) ...[
                  const Divider(height: 32),
                  SettingsTile(
                    icon: Icons.logout_rounded,
                    title: "Sign out".tr(),
                    onTap: () => _confirmSignOut(context),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmForgetInterests(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(
          'forget_interests_title'.tr(),
          style: TextStyles.heading3(dialogCtx),
        ),
        content: Text(
          'forget_interests_confirm'.tr(),
          style: TextStyles.body(dialogCtx),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text('Cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text('Confirm'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await PersonalizationResetService.instance.forgetAllLocalSignals();
    if (!context.mounted) return;
    await context.read<HomeProvider>().refreshHomeRails();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('forget_interests_done'.tr())),
    );
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Sign out'.tr(), style: TextStyles.heading3(dialogCtx)),
        content: Text(
          'Sign out confirm'.tr(),
          style: TextStyles.body(dialogCtx),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text('Cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: TextButton.styleFrom(foregroundColor: ColorsManager.error),
            child: Text('Confirm'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await context.read<AuthProvider>().signOut();
    // AuthGate سيلتقط تغيّر الحالة تلقائيًّا ويعيد المستخدم لشاشة الترحيب،
    // لكننا نُغلق ورقة الإعدادات لتجنّب تراكب الواجهات.
    if (context.mounted) Navigator.of(context).maybePop();
  }
}
