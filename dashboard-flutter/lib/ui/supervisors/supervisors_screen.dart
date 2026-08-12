import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../data/chat_repository.dart';
import '../../services/server_api.dart';
import '../widgets/common.dart';

class SupervisorsScreen extends StatefulWidget {
  const SupervisorsScreen({super.key});

  @override
  State<SupervisorsScreen> createState() => _SupervisorsScreenState();
}

class _SupervisorsScreenState extends State<SupervisorsScreen> {
  final _api = ServerApi.instance;
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final res = await _api.listSupervisors();
    final list = (res is Map)
        ? (res['supervisors'] ?? res['users'] ?? res['data'] ?? [])
        : res;
    return (list as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _act(Future<dynamic> Function() action, String label) async {
    try {
      await action();
      if (mounted) showSnack(context, '$label: تم');
      _reload();
    } catch (e) {
      if (mounted) showSnack(context, '$label فشل: ${e is ApiException ? e.message : e}', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: AsyncView<List<Map<String, dynamic>>>(
        future: _future,
        emptyCheck: (l) => l.isEmpty,
        emptyText: 'لا يوجد مشرفون.',
        builder: (context, list) => ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) => _tile(list[i]),
        ),
      ),
    );
  }

  Widget _tile(Map<String, dynamic> u) {
    final uid = '${u['uid'] ?? u['id'] ?? ''}';
    final email = '${u['email'] ?? ''}';
    final name = '${u['displayName'] ?? (email.contains('@') ? email.split('@').first : 'مستخدم')}';
    final role = '${u['role'] ?? 'supervisor'}';
    final blocked = u['isBlocked'] == true;
    final isOwner = role == 'owner';
    final isMe = uid == FirebaseAuth.instance.currentUser?.uid;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isOwner ? NebrasColors.amber : NebrasColors.emeraldDark,
          child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white)),
        ),
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          [email, role == 'owner' ? 'مالك 👑' : 'مشرف', if (blocked) 'موقوف'].join(' • '),
          style: const TextStyle(fontSize: 11),
        ),
        trailing: isOwner
            // مالك آخر (غير أنا): يمكن إنزاله إلى مشرف. أنا: وسام فقط.
            ? (isMe
                ? const Chip(label: Text('مالك 👑'), backgroundColor: NebrasColors.sidebarActive)
                : PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'demote') _confirmRole(uid, name, toOwner: false);
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'demote', child: Text('إنزال إلى مشرف')),
                    ],
                  ))
            : PopupMenuButton<String>(
                onSelected: (v) {
                  switch (v) {
                    case 'promote':
                      _confirmRole(uid, name, toOwner: true);
                      break;
                    case 'block_temp':
                      // الإيقاف يُخرِج العضو من دردشة الإدارة تلقائيّاً أيضاً.
                      _act(() async {
                        await _api.setSupervisorBlocked(uid, true, mode: 'temporary');
                        await ChatRepository.instance.removeMember(uid);
                      }, 'إيقاف مؤقّت');
                      break;
                    case 'block_perm':
                      _act(() async {
                        await _api.setSupervisorBlocked(uid, true, mode: 'permanent');
                        await ChatRepository.instance.removeMember(uid);
                      }, 'إيقاف دائم');
                      break;
                    case 'unblock':
                      _act(() => _api.setSupervisorBlocked(uid, false), 'رفع الإيقاف');
                      break;
                    case 'remove':
                      _confirmRemove(uid, name);
                      break;
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'promote', child: Text('ترقية إلى مالك 👑')),
                  if (!blocked) const PopupMenuItem(value: 'block_temp', child: Text('إيقاف مؤقّت')),
                  if (!blocked) const PopupMenuItem(value: 'block_perm', child: Text('إيقاف دائم')),
                  if (blocked) const PopupMenuItem(value: 'unblock', child: Text('رفع الإيقاف')),
                  const PopupMenuItem(value: 'remove', child: Text('إزالة نهائيّة', style: TextStyle(color: NebrasColors.rose))),
                ],
              ),
      ),
    );
  }

  /// ترقية إلى مالك 👑 (كلّ صلاحيّات المالك بلا استثناء) أو إنزال إلى مشرف.
  /// الكتابة مباشرة في RTDB `dashboard_users/{uid}/role` — قواعد RTDB تسمح
  /// بها للمالك، وauth/check يزامن الـ custom claims تلقائيّاً عند أوّل فتح
  /// للتطبيق من المعنيّ فتسري الصلاحيّات كاملة (Firestore/Storage/الواجهة).
  Future<void> _confirmRole(String uid, String name,
      {required bool toOwner}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(toOwner ? 'ترقية إلى مالك 👑' : 'إنزال إلى مشرف'),
        content: Text(toOwner
            ? 'سيحصل "$name" على كلّ صلاحيّات المالك بلا استثناء: إدارة المشرفين والإحصاءات والبلاغات والتدقيق وصلاحيّات المجموعة الكاملة. متابعة؟'
            : 'سيفقد "$name" صلاحيّات المالك ويعود مشرفاً عاديّاً. متابعة؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء')),
          FilledButton(
            style: toOwner
                ? null
                : FilledButton.styleFrom(backgroundColor: NebrasColors.rose),
            onPressed: () => Navigator.pop(context, true),
            child: Text(toOwner ? 'ترقية' : 'إنزال'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final role = toOwner ? 'owner' : 'supervisor';
    _act(() async {
      await FirebaseDatabase.instance
          .ref('dashboard_users/$uid')
          .update({'role': role});
      // وسام المجموعة يتحدّث فوراً (وupsertSelf للمعنيّ يثبّته لاحقاً).
      await ChatRepository.instance.setMemberAppRole(uid, role);
    }, toOwner ? 'ترقية $name إلى مالك 👑' : 'إنزال $name إلى مشرف');
    if (mounted) {
      showSnack(context,
          'تسري الصلاحيّات الجديدة كاملة عند أوّل فتح للتطبيق من "$name".');
    }
  }

  Future<void> _confirmRemove(String uid, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('إزالة مشرف'),
        content: Text('سيُزال "$name" من قائمة الإدارة نهائيّاً. متابعة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: NebrasColors.rose),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('إزالة'),
          ),
        ],
      ),
    );
    if (ok == true) {
      // الإزالة النهائيّة تُخرِج العضو من دردشة الإدارة تلقائيّاً أيضاً.
      _act(() async {
        await _api.removeSupervisor(uid);
        await ChatRepository.instance.removeMember(uid);
      }, 'إزالة');
    }
  }
}
