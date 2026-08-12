import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../auth/auth_provider.dart';
import '../../core/theme.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    Widget body;
    if (auth.isBlocked) {
      body = const _BlockedView();
    } else if (auth.isSignedIn && auth.needsOwnerCode) {
      body = const _OwnerCodeView();
    } else {
      body = const _SignInView();
    }

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.auto_stories_rounded,
                        size: 52, color: NebrasColors.emerald),
                    const SizedBox(height: 12),
                    const Text('مرحبًا بك في لوحة تحكّم نبراس',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    const Text('سجّل الدخول بحساب Google لإدارة المنصّة.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: NebrasColors.textMuted)),
                    const SizedBox(height: 28),
                    body,
                    if (auth.errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Text(auth.errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: NebrasColors.rose, fontSize: 13)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SignInView extends StatelessWidget {
  const _SignInView();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Column(
      children: [
        if (auth.isLoading)
          const Padding(
            padding: EdgeInsets.all(8),
            child: CircularProgressIndicator(),
          )
        else
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => context.read<AuthProvider>().signInWithGoogle(),
              icon: const Icon(Icons.login),
              label: const Text('المتابعة عبر Google'),
            ),
          ),
        const SizedBox(height: 12),
        const Text(
          'نقرأ فقط بياناتك الأساسيّة من Google. لا نخزّن أيّ كلمة مرور هنا.',
          textAlign: TextAlign.center,
          style: TextStyle(color: NebrasColors.textMuted, fontSize: 12),
        ),
      ],
    );
  }
}

class _OwnerCodeView extends StatefulWidget {
  const _OwnerCodeView();

  @override
  State<_OwnerCodeView> createState() => _OwnerCodeViewState();
}

class _OwnerCodeViewState extends State<_OwnerCodeView> {
  final _codeCtrl = TextEditingController();
  bool _busy = false;
  String? _info;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _request() async {
    setState(() => _busy = true);
    try {
      final msg = await context.read<AuthProvider>().requestOwnerCode();
      setState(() => _info = msg);
    } catch (e) {
      setState(() => _info = 'تعذّر إرسال الرمز: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (_codeCtrl.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await context.read<AuthProvider>().verifyOwnerCode(_codeCtrl.text);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Column(
      children: [
        Text('حسابك (${auth.user?.email ?? ''}) جديد ويحتاج اعتماد المالك.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: NebrasColors.textMuted, fontSize: 13)),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _request,
            icon: const Icon(Icons.mark_email_read_outlined),
            label: const Text('إرسال رمز جديد'),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _codeCtrl,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          decoration: const InputDecoration(
            labelText: 'رمز التحقّق',
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _busy ? null : _verify,
            child: _busy
                ? const SizedBox(
                    height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('تحقّق وتابع'),
          ),
        ),
        if (_info != null) ...[
          const SizedBox(height: 12),
          Text(_info!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: NebrasColors.emerald, fontSize: 12)),
        ],
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => context.read<AuthProvider>().signOut(),
          child: const Text('إلغاء وتسجيل الخروج'),
        ),
      ],
    );
  }
}

class _BlockedView extends StatelessWidget {
  const _BlockedView();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Icon(Icons.block, color: NebrasColors.rose, size: 40),
        const SizedBox(height: 12),
        const Text('تم تعليق وصولك من قبل الإدارة.',
            textAlign: TextAlign.center,
            style: TextStyle(color: NebrasColors.rose)),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () => context.read<AuthProvider>().signOut(),
          child: const Text('تسجيل الخروج'),
        ),
      ],
    );
  }
}
