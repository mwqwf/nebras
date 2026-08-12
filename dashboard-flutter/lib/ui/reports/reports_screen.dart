import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../auth/auth_provider.dart';
import '../../services/server_api.dart';
import '../widgets/common.dart';
import 'package:provider/provider.dart';

const _reasons = {
  'copyright': ('ملكية فكرية / حقوق نشر', Color(0xFFB45309)),
  'sexual': ('محتوى جنسيّ صريح', Color(0xFF9D174D)),
  'child_safety': ('يضرّ بالأطفال', Color(0xFF7F1D1D)),
  'violence': ('عنف', Color(0xFF9A3412)),
  'terrorism': ('إرهاب / تطرّف', Color(0xFF7F1D1D)),
  'other': ('أخرى', Color(0xFF6B7280)),
};

(String, Color) _reasonMeta(String code) => _reasons[code] ?? _reasons['other']!;

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final _api = ServerApi.instance;
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final res = await _api.reports();
    final items = (res is Map) ? (res['items'] ?? []) : [];
    return (items as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _act(Map<String, dynamic> r, String action) async {
    if (action == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          content: Text('هل تريد حذف هذا المحتوى نهائيّاً؟\n\n"${r['contentTitle'] ?? r['contentId']}"\n\nلا يمكن التراجع.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: NebrasColors.rose),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('حذف المحتوى'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      await _api.reportAction({
        'action': action,
        'reportId': r['id'],
        'contentId': r['contentId'],
        'contentType': r['contentType'],
      });
      if (mounted) showSnack(context, action == 'delete' ? 'حُذف المحتوى المخالف.' : 'أُغلق البلاغ.');
      _reload();
    } catch (e) {
      if (mounted) showSnack(context, 'فشل: ${e is ApiException ? e.message : e}', error: true);
    }
  }

  String _fmtDate(dynamic ms) {
    if (ms is! num) return '';
    return DateFormat('yyyy/MM/dd HH:mm').format(DateTime.fromMillisecondsSinceEpoch(ms.toInt()));
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: AsyncView<List<Map<String, dynamic>>>(
        future: _future,
        emptyCheck: (l) => l.isEmpty,
        emptyText: 'لا توجد بلاغات معلّقة. ✅',
        builder: (context, list) => ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: list.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            if (i == 0) {
              return const Text(
                'راجع كلّ بلاغ ثمّ احذف المحتوى إن كان مخالفاً فعلاً، أو تجاهل البلاغ إن كان كاذباً.',
                style: TextStyle(fontSize: 12, color: NebrasColors.textMuted),
              );
            }
            return _tile(list[i - 1]);
          },
        ),
      ),
    );
  }

  Widget _tile(Map<String, dynamic> r) {
    final meta = _reasonMeta('${r['reasonCode'] ?? 'other'}');
    final title = '${r['contentTitle'] ?? ''}';
    final note = '${r['note'] ?? ''}';
    final src = '${r['sourceUrl'] ?? ''}';
    final isOwner = context.read<AuthProvider>().isOwner;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(color: meta.$2.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
                  child: Text(meta.$1, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: meta.$2)),
                ),
                if ('${r['contentType'] ?? ''}'.isNotEmpty)
                  Text('${r['contentType']}', style: const TextStyle(fontSize: 11, color: NebrasColors.textMuted)),
                if (_fmtDate(r['createdAtMs']).isNotEmpty)
                  Text(_fmtDate(r['createdAtMs']), style: const TextStyle(fontSize: 10, color: NebrasColors.textMuted)),
              ],
            ),
            const SizedBox(height: 8),
            Text(title.isEmpty ? '(بدون عنوان)' : title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 2),
            Text('المعرّف: ${r['contentId'] ?? '—'}', style: const TextStyle(fontSize: 11, color: NebrasColors.textMuted)),
            if (src.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: InkWell(
                  onTap: () => launchUrl(Uri.parse(src), mode: LaunchMode.externalApplication),
                  child: const Text('عرض المصدر ↗', style: TextStyle(fontSize: 12, color: NebrasColors.emerald)),
                ),
              ),
            if (note.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: NebrasColors.surfaceAlt, borderRadius: BorderRadius.circular(8)),
                child: Text('ملاحظة المُبلِّغ: $note', style: const TextStyle(fontSize: 12)),
              ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(onPressed: () => _act(r, 'dismiss'), child: const Text('تجاهل البلاغ')),
                const SizedBox(width: 8),
                if (isOwner)
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: NebrasColors.rose),
                    onPressed: () => _act(r, 'delete'),
                    child: const Text('حذف المحتوى'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
