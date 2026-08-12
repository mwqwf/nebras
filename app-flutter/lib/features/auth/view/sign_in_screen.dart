import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nebras_mobile_app/core/extensions/sized_boxextension.dart';
import 'package:nebras_mobile_app/core/theme/color_manager.dart';
import 'package:nebras_mobile_app/core/theme/text_styles.dart';
import 'package:nebras_mobile_app/features/auth/provider/auth_provider.dart';
import 'package:provider/provider.dart';

/// شاشة الدخول/التسجيل بحساب Google.
///
/// نستخدم **نفس الشاشة** لحالتَي "إنشاء حساب" و"تسجيل الدخول"، ونُمرّر
/// `isSignUp` فقط لتغيير النصوص. السبب:
///   • مُنتقي حسابات Google هو نفسه تقنيًا (لا فرق في الـ API).
///   • يمنح ذلك تجربة موحّدة ومتسقّة، ويقلّل التكرار.
///   • مستقبلاً، يمكن للمطوّر التفريق بين حالة "مستخدم جديد" و"عائد" عبر
///     علامة داخليّة (first-seen) بعد نجاح الدخول.
class SignInScreen extends StatelessWidget {
  final bool isSignUp;
  const SignInScreen({super.key, required this.isSignUp});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: theme.iconTheme.color),
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 28.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              16.sbh,
              Text(
                isSignUp ? 'Create your account'.tr() : 'Welcome back'.tr(),
                style: TextStyles.heading1(context),
              ),
              10.sbh,
              Text(
                isSignUp
                    ? 'Signup subtitle'.tr()
                    : 'Signin subtitle'.tr(),
                style: TextStyles.body(context).copyWith(
                  color: ColorsManager.textSecondary,
                  height: 1.6,
                ),
              ),
              const Spacer(),
              _GoogleButton(
                busy: auth.isBusy,
                label: isSignUp
                    ? 'Sign up with Google'.tr()
                    : 'Sign in with Google'.tr(),
                onPressed: auth.isBusy
                    ? null
                    : () => _handleGoogle(context),
              ),
              20.sbh,
              Text(
                'Privacy note'.tr(),
                textAlign: TextAlign.center,
                style: TextStyles.greysmallText(context).copyWith(height: 1.5),
              ),
              24.sbh,
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleGoogle(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final success = await auth.signInWithGoogle();
    if (!context.mounted) return;
    if (success) {
      // بعد نجاح الدخول: `AuthGate` غيّر حالته إلى `signedIn` وبات يعرض
      // `HomeShell` تحتنا مباشرةً، لكنّ `SignInScreen` (وأحيانًا `WelcomeScreen`
      // إن وُجدت قبلها) لا تزال مدفوعة في الـ root Navigator فوق `AuthGate`.
      // لذا نُرجِع الملاحة إلى الجذر — أيّ نُغلق كلّ شيء فوق `AuthGate` —
      // فيرى المستخدم الصفحة الرئيسية فورًا دون الحاجة للضغط على "رجوع".
      // `popUntil(isFirst)` آمن حتى لو لم تكن هناك شاشات فوقنا (لا يفعل شيئًا).
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }
    final err = auth.lastError;
    if (err != null) {
      // المفاتيح التي يُرجعها AuthProvider قابلة للترجمة مباشرة عبر .tr().
      // إن لم يُطابق المفتاح أيّ إدخال (حالة رسالة فنّية جاءت من الحزمة)،
      // يُعيد easy_localization نفس النص كما هو.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            err.tr(),
            style: TextStyles.smallText(context).copyWith(color: Colors.white),
          ),
          backgroundColor: ColorsManager.error,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(16.w),
        ),
      );
      auth.clearError();
    }
  }
}

class _GoogleButton extends StatelessWidget {
  final bool busy;
  final String label;
  final VoidCallback? onPressed;

  const _GoogleButton({
    required this.busy,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56.h,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: ColorsManager.textPrimary,
          elevation: 1.5,
          shadowColor: Colors.black.withValues(alpha: 0.08),
          side: const BorderSide(color: ColorsManager.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14.r),
          ),
        ),
        child: busy
            ? SizedBox(
                width: 22.w,
                height: 22.w,
                child: const CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: ColorsManager.primary,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const _GoogleLogo(),
                  12.sbw,
                  Text(
                    label,
                    style: TextStyles.bodyBold(context).copyWith(
                      color: ColorsManager.textPrimary,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// شعار Google مرسوم بخطّ بسيط بدلاً من أيقونة شبكيّة أو أصل إضافي.
/// نعتمد أربع ألوان العلامة الرسمية.
class _GoogleLogo extends StatelessWidget {
  const _GoogleLogo();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22.w,
      height: 22.w,
      child: CustomPaint(painter: _GooglePainter()),
    );
  }
}

class _GooglePainter extends CustomPainter {
  static const _blue = Color(0xFF4285F4);
  static const _red = Color(0xFFEA4335);
  static const _yellow = Color(0xFFFBBC05);
  static const _green = Color(0xFF34A853);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    final rect = Rect.fromCircle(center: center, radius: radius * 0.95);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.22
      ..strokeCap = StrokeCap.butt;

    // 4 أقواس لتقليد الشعار الرسمي (مبسّطة للبنية الرياضية).
    canvas.drawArc(rect, -1.05, 1.15, false, paint..color = _blue);
    canvas.drawArc(rect, 0.10, 1.30, false, paint..color = _green);
    canvas.drawArc(rect, 1.40, 1.35, false, paint..color = _yellow);
    canvas.drawArc(rect, 2.75, 1.25, false, paint..color = _red);

    // شريط G الداخلي (خطّ أزرق أفقي صغير).
    final bar = Rect.fromCenter(
      center: center.translate(size.width * 0.18, 0),
      width: size.width * 0.38,
      height: size.width * 0.18,
    );
    canvas.drawRect(
      bar,
      Paint()..color = _blue,
    );
  }

  @override
  bool shouldRepaint(covariant _GooglePainter oldDelegate) => false;
}
