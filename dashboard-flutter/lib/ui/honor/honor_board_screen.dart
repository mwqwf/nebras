import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/admin_stats.dart';

/// لوحة الشرف 🏆 — ترتيب المشرفين حسب مساهماتهم (إجمالي وأسبوعي) مع شارات.
class HonorBoardScreen extends StatelessWidget {
  const HonorBoardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final weekKey = AdminStats.weekKey();
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: AdminStats.boardStream(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Text('تعذّر التحميل: ${snap.error}',
                style: const TextStyle(color: NebrasColors.rose)),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snap.data!;
        if (rows.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.emoji_events_outlined,
                      size: 52, color: NebrasColors.amber),
                  SizedBox(height: 14),
                  Text('لوحة الشرف فارغة بعد',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text('كلّ رفع تقوم به يُحسب لك هنا — ابدأ الآن! ⚡',
                      style: TextStyle(
                          color: NebrasColors.textMuted, fontSize: 12.5)),
                ],
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: rows.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) => _tile(rows[i], i, weekKey, myUid),
        );
      },
    );
  }

  Widget _tile(Map<String, dynamic> r, int rank, String weekKey, String myUid) {
    final uid = '${r['uid'] ?? ''}';
    final name = '${r['name'] ?? 'مشرف'}';
    final photo = '${r['photo'] ?? ''}';
    final uploads = (r['uploads'] is num) ? (r['uploads'] as num).toInt() : 0;
    final edits = (r['edits'] is num) ? (r['edits'] as num).toInt() : 0;
    final weekly = (r['weekly'] is Map)
        ? (((r['weekly'] as Map)[weekKey]) is num
            ? (((r['weekly'] as Map)[weekKey]) as num).toInt()
            : 0)
        : 0;

    final medal = switch (rank) {
      0 => '🥇',
      1 => '🥈',
      2 => '🥉',
      _ => '${rank + 1}',
    };
    final badges = <String>[
      if (uploads >= 100) '🏅 مئويّ',
      if (weekly >= 10) '⚡ نشيط هذا الأسبوع',
      if (uploads < 10) '🌱 بداية الطريق',
    ];

    final isMe = uid == myUid;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
            color: isMe ? NebrasColors.emerald : NebrasColors.border,
            width: isMe ? 1.4 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: Text(medal,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: rank < 3 ? 22 : 15,
                      fontWeight: FontWeight.w800,
                      color: NebrasColors.textMuted)),
            ),
            CircleAvatar(
              radius: 20,
              backgroundColor: NebrasColors.emeraldDark,
              backgroundImage:
                  photo.isNotEmpty ? CachedNetworkImageProvider(photo) : null,
              child: photo.isEmpty
                  ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white))
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$name${isMe ? ' (أنا)' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  if (badges.isNotEmpty)
                    Text(badges.join(' • '),
                        style: const TextStyle(
                            fontSize: 10.5, color: NebrasColors.amber)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('$uploads',
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: NebrasColors.emerald)),
                Text(
                    'رفعاً${weekly > 0 ? ' • $weekly هذا الأسبوع' : ''}${edits > 0 ? ' • $edits تعديلاً' : ''}',
                    style: const TextStyle(
                        fontSize: 9.5, color: NebrasColors.textMuted)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
