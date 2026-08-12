import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../services/server_api.dart';
import '../widgets/common.dart';

const _sourceMeta = {
  'internet_archive': ('الأرشيف (Internet Archive)', Color(0xFF2563EB), '🏛️'),
  'noor-library': ('مكتبة نور', Color(0xFF16A34A), '📗'),
  'hindawi': ('مؤسسة هنداوي', Color(0xFF9333EA), '📘'),
  'manual': ('رفع يدويّ', Color(0xFFD97706), '✍️'),
};
const _typeLabel = {'document': 'كتب', 'audio': 'صوت', 'video': 'فيديو'};

(String, Color, String) _meta(String key) =>
    _sourceMeta[key] ?? (key, const Color(0xFF64748B), '📦');

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  late Future<_Stats> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_Stats> _load() async {
    final results = await Future.wait([
      ServerApi.instance.aggregatesBySource(),
      ServerApi.instance.aggregatesOverview().catchError((_) => null),
    ]);
    final bySource = results[0];
    final overview = results[1];
    return _Stats(
      bySource is Map ? Map<String, dynamic>.from(bySource) : {},
      overview is Map ? Map<String, dynamic>.from(overview) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => setState(() => _future = _load()),
      child: AsyncView<_Stats>(
        future: _future,
        builder: (context, stats) {
          final bs = stats.bySource;
          final totals = (bs['totals'] as Map?) ?? {};
          final sources = (bs['sources'] as List?) ?? [];
          final topContent = (bs['topContent'] as List?) ?? [];
          final rawProviders = (bs['rawProviders'] as Map?) ?? {};
          final secs = (totals['sections'] as Map?) ?? {};
          final overviewByType = (stats.overview?['byType'] as Map?) ?? {};

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('إحصاءات المحتوى الحقيقية', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Text('أرقام محسوبة مباشرةً من قاعدة البيانات — لكلّ مصدر جلب على حدة.',
                            style: TextStyle(fontSize: 11, color: NebrasColors.textMuted)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () => setState(() => _future = _load()),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // إجماليّات
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _total('إجمالي المحتوى', '${totals['content'] ?? 0}'),
                  _total('ملفّات (كتب/صوت/فيديو)', '${totals['files'] ?? 0}'),
                  _total('الأقسام (رئيسي/فرعي/ثانوي)', '${secs['main'] ?? 0} / ${secs['sub'] ?? 0} / ${secs['secondary'] ?? 0}'),
                  if (bs['neverViewedCount'] != null)
                    _total('محتوى لم يُشاهَد بعد', '${bs['neverViewedCount']}'),
                ],
              ),
              const SizedBox(height: 18),
              // بطاقات المصادر
              ...sources.map((s) => _sourceCard(Map<String, dynamic>.from(s as Map))),
              // الأكثر مشاهدةً
              if (topContent.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('الأكثر مشاهدةً (حسب المشاهدات والتشغيل)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      for (var i = 0; i < topContent.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        _topRow(i + 1, Map<String, dynamic>.from(topContent[i] as Map)),
                      ],
                    ],
                  ),
                ),
              ],
              // الوسوم الخام
              if (rawProviders.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('توزيع الوسوم الخام (المصدر الفعليّ لكل عنصر)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: rawProviders.entries
                          .map((e) => _chip('${e.key}: ${e.value}'))
                          .toList(),
                    ),
                  ),
                ),
              ],
              // إجمالي حسب النوع
              if (overviewByType.isNotEmpty) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _total('كتب', '${overviewByType['document'] ?? 0}'),
                    _total('صوت', '${overviewByType['audio'] ?? 0}'),
                    _total('فيديو', '${overviewByType['video'] ?? 0}'),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _total(String label, String value) => Container(
        width: 165,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: NebrasColors.surface,
          border: Border.all(color: NebrasColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, color: NebrasColors.textMuted)),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          ],
        ),
      );

  Widget _sourceCard(Map<String, dynamic> s) {
    final m = _meta('${s['source']}');
    final byType = (s['byType'] as Map?) ?? {};
    final occupied = (s['sectionsOccupied'] as Map?) ?? {};
    final topMains = (s['topMainSections'] as List?) ?? [];
    final total = s['total'] ?? 0;
    return Card(
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: m.$2, width: 3)),
          borderRadius: BorderRadius.circular(4),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(m.$3, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Expanded(child: Text(m.$1, style: const TextStyle(fontWeight: FontWeight.bold))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(color: m.$2, borderRadius: BorderRadius.circular(20)),
                  child: Text('$total عنصر', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text('الأنواع', style: TextStyle(fontSize: 11, color: NebrasColors.textMuted)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in byType.entries)
                  if ((e.value as num? ?? 0) > 0) _chip('${_typeLabel[e.key] ?? e.key}: ${e.value}'),
                if (total == 0) const Text('لا محتوى بعد', style: TextStyle(fontSize: 11, color: NebrasColors.textMuted)),
              ],
            ),
            const SizedBox(height: 10),
            const Text('الأقسام الموضوع فيها', style: TextStyle(fontSize: 11, color: NebrasColors.textMuted)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 6, children: [
              _chip('رئيسي: ${occupied['main'] ?? 0}'),
              _chip('فرعي: ${occupied['sub'] ?? 0}'),
              _chip('ثانوي: ${occupied['secondary'] ?? 0}'),
            ]),
            if (topMains.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('أعلى الأقسام الرئيسيّة', style: TextStyle(fontSize: 11, color: NebrasColors.textMuted)),
              const SizedBox(height: 4),
              ...topMains.map((ms) {
                final m2 = Map<String, dynamic>.from(ms as Map);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Expanded(child: Text('${m2['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
                    Text('${m2['count']}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: m.$2)),
                  ]),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _topRow(int rank, Map<String, dynamic> c) => ListTile(
        dense: true,
        leading: CircleAvatar(radius: 13, backgroundColor: NebrasColors.surfaceAlt, child: Text('$rank', style: const TextStyle(fontSize: 11))),
        title: Text('${c['title'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
        subtitle: Text(_typeLabel['${c['type']}'] ?? '${c['type']}', style: const TextStyle(fontSize: 11)),
        trailing: Text('👁 ${c['views'] ?? 0}   ▶ ${c['plays'] ?? 0}', style: const TextStyle(fontSize: 11)),
      );

  Widget _chip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: NebrasColors.surfaceAlt, borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: const TextStyle(fontSize: 11)),
      );
}

class _Stats {
  _Stats(this.bySource, this.overview);
  final Map<String, dynamic> bySource;
  final Map<String, dynamic>? overview;
}
