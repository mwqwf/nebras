import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'auth/auth_provider.dart';
import 'core/theme.dart';
import 'ui/login/login_screen.dart';
import 'ui/shell/dashboard_shell.dart';

class NebrasDashboardApp extends StatelessWidget {
  const NebrasDashboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'لوحة تحكّم نبراس',
      debugShowCheckedModeBanner: false,
      theme: buildNebrasTheme(),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const _AuthGate(),
    );
  }
}

/// يوجّه بين شاشة الدخول واللوحة وفق حالة المصادقة.
class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    // أثناء أيّ فحص جارٍ لا نعرض شاشة الدخول (كانت تُعرض لموقَّعٍ تنتظر
    // صلاحيّته فحص الخادم عند كلّ إقلاع — مصدر إزعاج "طلب الدخول كلّ مرّة").
    if (auth.isLoading && !auth.authorized) {
      return const _SplashLoading();
    }
    if (!auth.isSignedIn || !auth.authorized) {
      return const LoginScreen();
    }
    return const DashboardShell();
  }
}

class _SplashLoading extends StatelessWidget {
  const _SplashLoading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_stories_rounded, size: 56, color: NebrasColors.emerald),
            SizedBox(height: 16),
            Text('نبراس', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            SizedBox(height: 24),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
