import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nebras_mobile_app/core/widgets/botttom_sheet_widget.dart';
import 'package:nebras_mobile_app/features/auth/provider/auth_provider.dart';
import 'package:nebras_mobile_app/features/auth/view/account_screen.dart';
import 'package:nebras_mobile_app/features/home/view/home_screen.dart';
import 'package:nebras_mobile_app/features/notifications/provider/notfication_provider.dart';
import 'package:nebras_mobile_app/features/saved/provider/saved_provider.dart';
import 'package:nebras_mobile_app/features/saved/view/saved_view.dart';
import 'package:provider/provider.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _currentIndex = 0;

  /// التبويبان الوحيدان في الأسفل: الرئيسية + التحميلات. البحث و"لك"
  /// اندمجا داخل الرئيسية، والإعدادات/الإشعارات انتقلت للـ Drawer.
  final List<Widget> _pages = const [HomeScreen(), SavedScreen()];

  @override
  void initState() {
    super.initState();
    // Safe lazy initialization — providers are already created at this point.
    // These calls are safe because they happen AFTER the widget tree is built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotificationProvider>().load();
      context.read<SavedProvider>().loadSaved();
    });
  }

  void _onNavTap(int index) {
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const _NebrasDrawer(),
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        onTap: _onNavTap,
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.home_outlined),
            activeIcon: const Icon(Icons.home),
            label: 'Home'.tr(),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.download_done_outlined),
            activeIcon: const Icon(Icons.download_done),
            label: 'Downloads'.tr(), // "التحميلات" بدل "المحفوظات"
          ),
        ],
      ),
    );
  }
}

class _NebrasDrawer extends StatelessWidget {
  const _NebrasDrawer();

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            InkWell(
              onTap: () {
                Navigator.pop(context); // أغلق الدرج
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AccountScreen()),
                );
              },
              child: Padding(
                padding: EdgeInsets.fromLTRB(20.w, 30.h, 20.w, 20.h),
                child: Row(
                  children: [
                    const Expanded(child: _DrawerAccountHeader()),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            const Divider(),
            // ملاحظة: اختصار "الإشعارات" نُقل إلى جرس في الشريط العلويّ
            // للرئيسية (طراز YouTube). الشاشة نفسها لم تتغيّر وتُفتح من الجرس.
            ExpansionTile(
              leading: const Icon(Icons.settings_outlined),
              title: Text('Settings'.tr()),
              children: const [
                // نفس Widget الإعدادات الأصلي
                SizedBox(height: 560, child: SettingsBottomSheetWidget()),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// رأس الدرج الذي يوضّح **بجلاء** هويّة الجلسة الحاليّة:
///   • مستخدم حقيقيّ (Google) → صورته (أو أوّل حرف من اسمه) + الاسم + البريد
///     مع شارة تحقّق صغيرة.
///   • ضيف → أيقونة ضيف مميّزة + كلمة "ضيف" + "تصفّح بدون حساب" + زرّ دخول
///     سريع.
/// المرجع الوحيد للهويّة هو [AuthProvider] (الضيف = signedIn مع user == null).
class _DrawerAccountHeader extends StatelessWidget {
  const _DrawerAccountHeader();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final isGuest = user == null;

    final String displayName = isGuest
        ? 'Guest'.tr()
        : (user.displayName.trim().isNotEmpty
              ? user.displayName.trim()
              : (user.email.trim().isNotEmpty ? user.email.trim() : 'Guest'.tr()));

    final String subtitle =
        isGuest ? 'Browse without account'.tr() : user.email.trim();

    return Row(
      children: [
        _AccountAvatar(
          photoUrl: isGuest ? null : user.photoUrl,
          fallbackInitial: isGuest
              ? null
              : (displayName.isNotEmpty ? displayName.characters.first : null),
          isGuest: isGuest,
        ),
        16.horizontalSpace,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (!isGuest) ...[
                    6.horizontalSpace,
                    Icon(
                      Icons.verified_rounded,
                      size: 16.r,
                      color: scheme.primary,
                    ),
                  ],
                ],
              ),
              4.verticalSpace,
              // شارة الحالة: تميّز الضيف بصرياً عن المستخدم الحقيقيّ.
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                decoration: BoxDecoration(
                  color: (isGuest ? scheme.tertiary : scheme.primary)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isGuest
                          ? Icons.no_accounts_rounded
                          : Icons.account_circle_rounded,
                      size: 13.r,
                      color: isGuest ? scheme.tertiary : scheme.primary,
                    ),
                    4.horizontalSpace,
                    Text(
                      isGuest ? 'Guest mode'.tr() : 'Signed in'.tr(),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: isGuest ? scheme.tertiary : scheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (subtitle.isNotEmpty) ...[
                4.verticalSpace,
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// أفاتار الحساب: صورة المستخدم إن وُجدت، وإلّا أوّل حرف من اسمه، وإلّا
/// أيقونة ضيف مميّزة بإطار متقطّع اللون كي يدرك المستخدم فوراً أنّه يتصفّح
/// كضيف.
class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({
    required this.photoUrl,
    required this.fallbackInitial,
    required this.isGuest,
  });

  final String? photoUrl;
  final String? fallbackInitial;
  final bool isGuest;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = isGuest ? scheme.tertiary : scheme.primary;
    final radius = 30.r;

    Widget inner;
    if (!isGuest && (photoUrl ?? '').trim().isNotEmpty) {
      inner = ClipOval(
        child: Image.network(
          photoUrl!.trim(),
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _initialOrIcon(accent, radius),
        ),
      );
    } else {
      inner = _initialOrIcon(accent, radius);
    }

    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: accent.withValues(alpha: 0.12),
        border: Border.all(color: accent.withValues(alpha: 0.5), width: 2),
      ),
      alignment: Alignment.center,
      child: inner,
    );
  }

  Widget _initialOrIcon(Color accent, double radius) {
    if (!isGuest && (fallbackInitial ?? '').trim().isNotEmpty) {
      return Text(
        fallbackInitial!.toUpperCase(),
        style: TextStyle(
          fontSize: radius * 0.8,
          fontWeight: FontWeight.bold,
          color: accent,
        ),
      );
    }
    return Icon(
      isGuest ? Icons.person_off_outlined : Icons.person,
      size: radius,
      color: accent,
    );
  }
}
