import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../auth/auth_provider.dart';
import '../../services/server_api.dart';
import '../widgets/common.dart';
import 'package:provider/provider.dart';

const _flags = {
  'terrorism': ('إصدار/تنظيم متطرّف', Color(0xFF7F1D1D)),
  'copyright': ('علامة تجاريّة/حقوق نشر', Color(0xFF92400E)),
  'sexual': ('ألفاظ جنسيّة صريحة', Color(0xFF9D174D)),
  'archive_link': ('رابط Archive.org', Color(0xFF6B7280)),
};

(String, Color) _flagMeta(String code) => _flags[code] ?? (code, const Color(0xFF6B7280));

class ContentAuditScreen extends StatefulWidget {
  const ContentAuditScreen({super.key});

  @override
  State<ContentAuditScreen> createState() => _ContentAuditScreenState();
}

class _ContentAuditScreenState extends State<ContentAuditScreen> {
  final _api = ServerApi.instance;
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final res = await _api.contentAudit();
    return (res is Map) ? Map<String, dynamic>.from(res) : {'items': []};
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _delete(Map<String, dynamic> item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف عنصر مُعلَّم'),
        content: Text('سيُحذف "${item['title'] ?? item['contentId']}" نهائيّاً. متابعة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: NebrasColors.rose),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.contentAuditDelete('${item['contentId']}', '${item['contentType'] ?? ''}');
      if (mounted) showSnack(context, 'تم الحذف.');
      _reload();
    } catch (e) {
      if (mounted) showSnack(context, 'فشل: ${e is ApiException ? e.message : e}', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: AsyncView<Map<String, dynamic>>(
        future: _future,
        builder: (context, data) {
          final items = (data['items'] as List?) ?? [];
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 8, right: 4, left: 4),
                child: Text(
                  'مراجعة المحتوى الذي يحتاج تحقّقاً من الملكية الفكرية / المصدر. احذف المخالف منه فقط.',
                  style: TextStyle(fontSize: 12, color: NebrasColors.textMuted),
                ),
              ),
              Card(
                color: NebrasColors.sidebarActive,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const Icon(Icons.fact_check, color: NebrasColors.emerald),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'فُحص ${data['scanned'] ?? 0} عنصراً — مُعلَّم: ${data['flaggedCount'] ?? items.length}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('لا توجد عناصر مُعلَّمة — المحتوى نظيف.', style: TextStyle(color: NebrasColors.textMuted))),
                )
              else
                ...items.map((e) => _tile(Map<String, dynamic>.from(e as Map))),
            ],
          );
        },
      ),
    );
  }

  Widget _tile(Map<String, dynamic> item) {
    final flags = (item['flags'] as List?) ?? [];
    final matched = (item['matched'] as List?) ?? [];
    final url = '${item['sourceUrl'] ?? ''}';
    final isOwner = context.read<AuthProvider>().isOwner;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${item['title'] ?? '(بلا عنوان)'}', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final f in flags)
                  Builder(builder: (_) {
                    final m = _flagMeta('$f');
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: m.$2.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
                      child: Text(m.$1, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: m.$2)),
                    );
                  }),
              ],
            ),
            if (matched.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('الكلمات المُطابِقة: ${matched.join('، ')}',
                    style: const TextStyle(fontSize: 11, color: NebrasColors.rose)),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('المعرّف: ${item['contentId'] ?? '—'}',
                  style: const TextStyle(fontSize: 11, color: NebrasColors.textMuted)),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (url.isNotEmpty)
                  TextButton(
                    onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
                    child: const Text('فتح'),
                  ),
                const SizedBox(width: 8),
                if (isOwner)
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: NebrasColors.rose),
                    onPressed: () => _delete(item),
                    child: const Text('حذف'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
