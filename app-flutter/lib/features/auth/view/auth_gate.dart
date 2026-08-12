import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nebras_mobile_app/core/theme/color_manager.dart';
import 'package:nebras_mobile_app/core/widgets/home_shell.dart';
import 'package:nebras_mobile_app/features/auth/provider/auth_provider.dart';
import 'package:nebras_mobile_app/features/auth/view/welcome_screen.dart';
import 'package:provider/provider.dart';

/// البوّابة التي يُوجَّه إليها التطبيق بعد السبلاش.
///
/// تختار بين:
///   • `HomeShell`     — إذا كان هناك مستخدم مسجّل دخوله.
///   • `WelcomeScreen` — إذا لم يكن.
///   • شاشة لودر خفيفة — أثناء تحميل الجلسة من SharedPreferences/Google.
///
/// نستخدم `AnimatedSwitcher` حتى يكون التبديل بين الحالات سلسًا بدل قفزة
/// بصريّة فجّة. المنطق كلّه مُفوَّض لـ `AuthProvider.status`.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _bootstrapCalled = false;

  @override
  void initState() {
    super.initState();
    // نستدعي bootstrap في أول إطار — نحتاج context لـ Provider.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_bootstrapCalled || !mounted) return;
      _bootstrapCalled = true;
      await context.read<AuthProvider>().bootstrap();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    final child = switch (auth.status) {
      AuthStatus.unknown => const _AuthLoading(key: ValueKey('loading')),
      AuthStatus.signedIn => const HomeShell(key: ValueKey('home')),
      AuthStatus.signedOut => const WelcomeScreen(key: ValueKey('welcome')),
    };

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
      child: child,
    );
  }
}

class _AuthLoading extends StatelessWidget {
  const _AuthLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: SizedBox(
          width: 28.w,
          height: 28.w,
          child: const CircularProgressIndicator(
            strokeWidth: 2.4,
            color: ColorsManager.primary,
          ),
        ),
      ),
    );
  }
}
