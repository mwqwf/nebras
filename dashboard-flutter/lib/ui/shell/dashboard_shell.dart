import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../auth/auth_provider.dart';
import '../../core/theme.dart';
import '../../data/chat_repository.dart';
import '../../services/notifications_service.dart';
import '../../services/share_receiver.dart';
import '../chat/profile_dialog.dart';
import '../content/quick_upload_screen.dart';
import '../honor/honor_board_screen.dart';
import '../content/content_files_screen.dart';
import '../content/upload_screen.dart';
import '../chat/chat_screen.dart';
import '../content_audit/content_audit_screen.dart';
import '../home/home_screen.dart';
import '../reports/reports_screen.dart';
import '../community/community_moderation_screen.dart';
import '../sections/sections_screen.dart';
import '../statistics/statistics_screen.dart';
import '../supervisors/supervisors_screen.dart';

/// تنقّل بسيط بين شاشات اللوحة بالاسم (يطابق روابط/تبويبات الويب).
class DashboardNav {
  static void Function(String title)? _go;
  static void goTo(String title) => _go?.call(title);
}

class _NavItem {
  const _NavItem({
    required this.title,
    required this.icon,
    required this.builder,
    this.ownerOnly = false,
  });
  final String title;
  final IconData icon;
  final WidgetBuilder builder;
  final bool ownerOnly;
}

class DashboardShell extends StatefulWidget {
  const DashboardShell({super.key});

  @override
  State<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<DashboardShell> {
  int _index = 0;
  Timer? _presenceTimer;

  @override
  void initState() {
    super.initState();
    // العضويّة التلقائيّة في دردشة الإدارة: كلّ من وصل إلى اللوحة (مصرَّح له)
    // يُضاف/يُحدَّث في `admin_chat_members` دون أيّ خطوة يدويّة، مع دوره
    // (لوسام المالك 👑) ونبضة حضور دوريّة تُظهره «متصلاً الآن» ما دامت
    // اللوحة مفتوحة.
    final isOwner = context.read<AuthProvider>().isOwner;
    ChatRepository.instance
        .upsertSelf(role: isOwner ? 'owner' : 'supervisor');
    _presenceTimer = Timer.periodic(const Duration(seconds: 60),
        (_) => ChatRepository.instance.presenceTick());
    // إعداد الملفّ الشخصي أوّل مرّة: بعد أوّل تسجيل دخول يختار العضو اسمه
    // وصورته اللذين سيظهران في المجموعة (مرّة واحدة لكلّ حساب).
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAskProfile());
    // الإشعارات (topic الدردشة + token) — كماليّة وغير معطِّلة.
    NotificationsService.init();
    // «مشاركة إلى نبراس»: ملفّ/رابط من أيّ تطبيق يفتح الرفع السريع.
    ShareReceiver.init(_handleShared);
  }

  void _handleShared(SharedPayload p) {
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => QuickUploadScreen(
        sharedFilePath: p.path,
        sharedText: p.text,
      ),
    ));
  }

  Future<void> _maybeAskProfile() async {
    final me = await ChatRepository.instance.fetchSelf();
    if (!mounted || (me?.profileSet ?? false)) return;
    await showProfileDialog(context, firstRun: true);
  }

  @override
  void dispose() {
    _presenceTimer?.cancel();
    super.dispose();
  }

  // ملاحظة: الوظائف الآليّة (Internet Archive / مكتبة نور / مؤسسة هنداوي /
  // Crawl4AI / جلب من مكتبة نور) أُزيلت كليّاً من التطبيق عمداً — تبقى حصراً
  // على نسخة الويب/الخادم. لا تُعِد إضافتها هنا.
  List<_NavItem> get _items => const [
        _NavItem(title: 'لوحة القيادة', icon: Icons.dashboard_outlined, builder: _b0),
        _NavItem(title: 'الأقسام', icon: Icons.account_tree_outlined, builder: _b1),
        _NavItem(title: 'المحتوى', icon: Icons.folder_open_outlined, builder: _b2),
        _NavItem(title: 'رفع متعدد', icon: Icons.cloud_upload_outlined, builder: _b3),
        _NavItem(title: 'الدردشة', icon: Icons.chat_bubble_outline, builder: _b4),
        _NavItem(title: 'لوحة الشرف', icon: Icons.emoji_events_outlined, builder: _b9),
        _NavItem(title: 'إدارة المشرفين', icon: Icons.group_outlined, ownerOnly: true, builder: _b5),
        _NavItem(title: 'الإحصاءات', icon: Icons.bar_chart_outlined, builder: _b6),
        _NavItem(title: 'بلاغات المحتوى', icon: Icons.flag_outlined, builder: _b7),
        _NavItem(title: 'إشراف المجتمع', icon: Icons.groups_2_outlined, builder: _b10),
        _NavItem(title: 'تدقيق المحتوى', icon: Icons.fact_check_outlined, builder: _b8),
      ];

  // ثوابت Builders (دوال علويّة لأنّ القائمة const).
  static Widget _b0(BuildContext c) => const HomeScreen();
  static Widget _b1(BuildContext c) => const SectionsScreen();
  static Widget _b2(BuildContext c) => const ContentFilesScreen();
  static Widget _b3(BuildContext c) => const UploadScreen();
  static Widget _b4(BuildContext c) => const ChatScreen();
  static Widget _b5(BuildContext c) => const SupervisorsScreen();
  static Widget _b6(BuildContext c) => const StatisticsScreen();
  static Widget _b7(BuildContext c) => const ReportsScreen();
  static Widget _b8(BuildContext c) => const ContentAuditScreen();
  static Widget _b9(BuildContext c) => const HonorBoardScreen();
  static Widget _b10(BuildContext c) => const CommunityModerationScreen();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final visible = _items.where((i) => !i.ownerOnly || auth.isOwner).toList();
    if (_index >= visible.length) _index = 0;
    final current = visible[_index];

    // تمكين التنقّل بالاسم (تبويبات الرفع/المحتوى).
    DashboardNav._go = (title) {
      final i = visible.indexWhere((e) => e.title == title);
      if (i >= 0 && mounted) setState(() => _index = i);
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(current.title),
        actions: [
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: NebrasColors.sidebarActive,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  auth.isOwner ? 'مالك' : 'مشرف',
                  style: const TextStyle(color: NebrasColors.emerald, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
      drawer: _Sidebar(
        items: visible,
        selected: _index,
        onSelect: (i) {
          setState(() => _index = i);
          Navigator.pop(context);
        },
      ),
      body: KeyedSubtree(key: ValueKey(current.title), child: current.builder(context)),
      // الرفع السريع ⚡ — متاح من أيّ شاشة.
      floatingActionButton: FloatingActionButton(
        heroTag: 'quick_upload_fab',
        backgroundColor: NebrasColors.emeraldDark,
        tooltip: 'الرفع السريع',
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const QuickUploadScreen())),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.items, required this.selected, required this.onSelect});

  final List<_NavItem> items;
  final int selected;
  final void Function(int) onSelect;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final name = (user?.displayName?.trim().isNotEmpty == true)
        ? user!.displayName!
        : (user?.email?.split('@').first ?? 'مستخدم');

    return Drawer(
      backgroundColor: NebrasColors.sidebarBg,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [NebrasColors.emeraldDark, NebrasColors.emerald]),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.auto_stories_rounded, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Text('Nebras',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: NebrasColors.emerald)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final item = items[i];
                  final active = i == selected;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Material(
                      color: active ? NebrasColors.sidebarActive : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      child: ListTile(
                        dense: true,
                        leading: Icon(item.icon,
                            size: 20, color: active ? NebrasColors.emerald : NebrasColors.textMuted),
                        title: Text(item.title,
                            style: TextStyle(
                                fontSize: 13.5,
                                color: active ? NebrasColors.emerald : NebrasColors.textMuted,
                                fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        onTap: () => onSelect(i),
                      ),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: CircleAvatar(
                radius: 18,
                backgroundColor: NebrasColors.emeraldDark,
                backgroundImage: (user?.photoURL != null) ? NetworkImage(user!.photoURL!) : null,
                child: user?.photoURL == null
                    ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: const TextStyle(color: Colors.white))
                    : null,
              ),
              title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
              subtitle: Text(user?.email ?? '',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => context.read<AuthProvider>().signOut(),
                  icon: const Icon(Icons.logout, size: 18),
                  label: const Text('تسجيل الخروج'),
                  style: OutlinedButton.styleFrom(foregroundColor: NebrasColors.rose),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
