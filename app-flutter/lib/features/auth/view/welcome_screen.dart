import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nebras_mobile_app/core/extensions/sized_boxextension.dart';
import 'package:nebras_mobile_app/core/theme/color_manager.dart';
import 'package:nebras_mobile_app/core/theme/text_styles.dart';
import 'package:nebras_mobile_app/features/auth/provider/auth_provider.dart';
import 'package:nebras_mobile_app/features/auth/view/sign_in_screen.dart';
import 'package:provider/provider.dart';

/// شاشة الترحيب — البوّابة الأولى للتطبيق للمستخدمين غير المسجّلين.
///
/// اعتمدنا تصميمًا هادئًا ومركزيًا:
///   • شعار التطبيق (app_icon.png) في الأعلى داخل إطار دائري ناعم.
///   • عبارة ترحيب محايدة تعكس طابع المعرفة العامة.
///   • عبارة ترحيبية واضحة: "مرحباً بك في تطبيق نبراس".
///   • زرّان متميّزان: "إنشاء حساب" (بارز) و "تسجيل الدخول" (ثانوي).
///
/// الشاشة Stateless لأنّها مجرد واجهة — كلّ المنطق في `AuthProvider`.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 16.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),
              _AppBadge(isDark: isDark),
              28.sbh,
              _GreetingBlock(isDark: isDark),
              const Spacer(flex: 3),
              _PrimaryButton(
                label: 'Create account'.tr(),
                icon: Icons.person_add_alt_1_rounded,
                onPressed: () => _goToSignIn(context, isSignUp: true),
              ),
              12.sbh,
              _SecondaryButton(
                label: 'Sign in'.tr(),
                icon: Icons.login_rounded,
                onPressed: () => _goToSignIn(context, isSignUp: false),
              ),
              16.sbh,
              Text(
                'Continue with Google hint'.tr(),
                textAlign: TextAlign.center,
                style: TextStyles.greysmallText(context),
              ),
              12.sbh,
              // خيار واضح للتصفّح بدون حساب — تسجيل الدخول غير إلزاميّ،
              // ويبقى متاحاً لاحقاً لتخصيص التجربة (المحفوظات/التوصيات).
              SizedBox(
                height: 50.h,
                child: TextButton.icon(
                  onPressed: () =>
                      context.read<AuthProvider>().continueAsGuest(),
                  icon: Icon(
                    Icons.explore_outlined,
                    size: 20.sp,
                    color: ColorsManager.primary,
                  ),
                  label: Text(
                    'Continue as guest'.tr(),
                    style: TextStyles.button(context).copyWith(
                      color: ColorsManager.primary,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14.r),
                    ),
                  ),
                ),
              ),
              8.sbh,
            ],
          ),
        ),
      ),
    );
  }

  void _goToSignIn(BuildContext context, {required bool isSignUp}) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, animation, _) => FadeTransition(
          opacity: animation,
          child: SignInScreen(isSignUp: isSignUp),
        ),
        transitionDuration: const Duration(milliseconds: 260),
      ),
    );
  }
}

class _AppBadge extends StatelessWidget {
  final bool isDark;
  const _AppBadge({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 120.w,
        height: 120.w,
        padding: EdgeInsets.all(14.w),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDark
              ? ColorsManager.primary.withValues(alpha: 0.18)
              : ColorsManager.primary.withValues(alpha: 0.08),
          boxShadow: [
            BoxShadow(
              color: ColorsManager.primary.withValues(alpha: 0.15),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipOval(
          child: Image.asset(
            'assets/images/app_icon.png',
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}

class _GreetingBlock extends StatelessWidget {
  final bool isDark;
  const _GreetingBlock({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'Welcome greeting'.tr(),
          textAlign: TextAlign.center,
          style: TextStyles.heading3(context).copyWith(
            color: ColorsManager.primary,
            height: 1.6,
          ),
        ),
        12.sbh,
        Text(
          'Welcome to Nebras'.tr(),
          textAlign: TextAlign.center,
          style: TextStyles.heading1(context).copyWith(height: 1.3),
        ),
        10.sbh,
        Text(
          'Welcome subtitle'.tr(),
          textAlign: TextAlign.center,
          style: TextStyles.body(context).copyWith(
            color: isDark
                ? ColorsManager.textMuted
                : ColorsManager.textSecondary,
            height: 1.6,
          ),
        ),
      ],
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const _PrimaryButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54.h,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20.sp, color: Colors.white),
        label: Text(
          label,
          style: TextStyles.button(context).copyWith(color: Colors.white),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: ColorsManager.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14.r),
          ),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const _SecondaryButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54.h,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20.sp, color: ColorsManager.primary),
        label: Text(
          label,
          style: TextStyles.button(
            context,
          ).copyWith(color: ColorsManager.primary),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: ColorsManager.primary,
          side: BorderSide(
            color: ColorsManager.primary.withValues(alpha: 0.55),
            width: 1.4,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14.r),
          ),
        ),
      ),
    );
  }
}
