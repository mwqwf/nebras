import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/firestore_refs.dart';
import '../../data/content_repository.dart';
import '../../data/unified_firestore.dart';
import '../../services/server_api.dart';
import '../../core/theme.dart';
import '../widgets/common.dart';

// ألوان توزيع المحتوى — مطابقة للوحة الويب.
const _cVideo = Color(0xFF10B981);
const _cAudio = Color(0xFF3B82F6);
const _cDoc = Color(0xFFF59E0B);

const _kOverviewCacheKey = 'nebras_home_overview_v1';
const _kChartCacheKey = 'nebras_home_chart_v1';

/// لوحة القيادة (الإحصاءات) — نمط «اعرض الكاش فوراً ثم حدّث بالخلفيّة»:
/// آخر أرقام محمَّلة تُخزَّن محليّاً وتظهر لحظيّاً عند الفتح، ويجري التحديث
/// الشبكي بصمت ثم تُحدَّث الواجهة والكاش. لا شاشة تحميل بعد أوّل استخدام.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  _Overview? _overview;
  List<_DayBar>? _bars;
  bool _refreshing = false;
  String? _error; // يظهر فقط حين لا يوجد كاش إطلاقاً.
  DateTime? _cachedAt;

  // إعادة محاولة تلقائية متدرجة (3ث/6ث/12ث) عند فشل أوّل تحميل بلا كاش —
  // دفقات Firestore اللحظية (resource-exhausted) تزول وحدها خلال ثوانٍ.
  int _autoRetries = 0;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  Future<void> _boot() async {
    await _loadCache();
    await _refresh();
  }

  // ─── الكاش المحلّي ───────────────────────────────────────

  Future<void> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ovRaw = prefs.getString(_kOverviewCacheKey);
      if (ovRaw != null) {
        final m = (jsonDecode(ovRaw) as Map).cast<String, dynamic>();
        int n(String k) => (m[k] as num?)?.toInt() ?? 0;
        _overview = _Overview(
          sections: n('s'),
          content: n('c'),
          documents: n('d'),
          audio: n('a'),
          video: n('v'),
        );
        final at = (m['at'] as num?)?.toInt();
        if (at != null) {
          _cachedAt = DateTime.fromMillisecondsSinceEpoch(at);
        }
      }
      final chRaw = prefs.getString(_kChartCacheKey);
      if (chRaw != null) {
        final list = (jsonDecode(chRaw) as List).cast<Map>();
        _bars = [
          for (final e in list)
            _DayBar(DateTime.parse('${e['d']}'))
              ..video = (e['v'] as num?)?.toInt() ?? 0
              ..audio = (e['a'] as num?)?.toInt() ?? 0
              ..document = (e['doc'] as num?)?.toInt() ?? 0,
        ];
      }
      if (mounted && (_overview != null || _bars != null)) setState(() {});
    } catch (_) {
      // كاش تالف — يُتجاهل ويُعاد بناؤه من الشبكة.
    }
  }

  Future<void> _saveCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ov = _overview;
      if (ov != null) {
        await prefs.setString(
            _kOverviewCacheKey,
            jsonEncode({
              's': ov.sections,
              'c': ov.content,
              'd': ov.documents,
              'a': ov.audio,
              'v': ov.video,
              'at': DateTime.now().millisecondsSinceEpoch,
            }));
      }
      final bars = _bars;
      if (bars != null) {
        await prefs.setString(
            _kChartCacheKey,
            jsonEncode([
              for (final b in bars)
                {
                  'd': DateFormat('yyyy-MM-dd').format(b.date),
                  'v': b.video,
                  'a': b.audio,
                  'doc': b.document,
                }
            ]));
      }
    } catch (_) {}
  }

  // ─── التحديث الشبكي (بالخلفيّة) ──────────────────────────

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      _error = null;
    });
    // الجزءان مستقلّان: سقوط رسم النشاط (يقرأ وثائق كثيرة) لا يجوز أن
    // يحجب أرقام اللوحة، والعكس صحيح.
    Object? firstError;
    _Overview? ov;
    List<_DayBar>? bars;
    Future<void> loadNumbers() async {
      try {
        ov = await _loadOverview();
      } catch (e) {
        firstError ??= e;
      }
    }

    Future<void> loadActivity() async {
      try {
        bars = await _loadChart();
      } catch (e) {
        firstError ??= e;
      }
    }

    await Future.wait<void>([loadNumbers(), loadActivity()]);
    if (ov != null) _overview = ov;
    if (bars != null) _bars = bars;
    if (ov != null || bars != null) {
      _cachedAt = DateTime.now();
      await _saveCache();
    }
    if (ov != null) {
      _autoRetries = 0;
      _retryTimer?.cancel();
    } else if (_overview == null) {
      // لا كاش ولا شبكة: رسالة لطيفة + إعادة محاولة تلقائية متدرجة.
      _error = _friendlyError(firstError);
      _scheduleAutoRetry();
    }
    if (mounted) setState(() => _refreshing = false);
  }

  void _scheduleAutoRetry() {
    if (_autoRetries >= 3) return;
    final delay = Duration(seconds: 3 << _autoRetries); // 3، 6، 12 ثانية
    _autoRetries++;
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      if (mounted && _overview == null) _refresh();
    });
  }

  static String _friendlyError(Object? e) {
    final s = '$e';
    if (s.contains('resource-exhausted')) {
      return 'قاعدة البيانات مشغولة مؤقتاً (ضغط لحظي).\nسنعيد المحاولة تلقائياً خلال ثوانٍ…';
    }
    if (s.contains('unavailable') ||
        s.contains('network') ||
        s.contains('SocketException')) {
      return 'تعذّر الاتصال بالخادم — تحقق من الشبكة.\nسنعيد المحاولة تلقائياً…';
    }
    if (s.contains('permission-denied')) {
      return 'صلاحيات غير كافية لقراءة الأرقام — سجّل الخروج والدخول مجدداً.';
    }
    return 'تعذّر تحميل أرقام اللوحة.\nسنعيد المحاولة تلقائياً…';
  }

  Future<_Overview> _loadOverview() async {
    try {
      final res = await ServerApi.instance.aggregatesOverview();
      if (res is Map && res['ok'] == true) {
        final s = (res['sections'] as Map?) ?? {};
        final c = (res['content'] as Map?) ?? {};
        final t = (res['byType'] as Map?) ?? {};
        int n(dynamic v) => (v as num?)?.toInt() ?? 0;
        return _Overview(
          sections: n(s['main']) + n(s['sub']) + n(s['secondary']),
          content: n(c['total']),
          documents: n(t['document']),
          audio: n(t['audio']),
          video: n(t['video']),
        );
      }
    } catch (_) {}
    return _localFallback();
  }

  Future<_Overview> _localFallback() async {
    final fs = UnifiedFirestore.instance;
    final mains = await fs.readSectionsLevel('main');
    final subs = await fs.readSectionsLevel('sub');
    final secs = await fs.readSectionsLevel('secondary');
    int total = 0;
    try {
      final agg =
          await nebrasFirestore().collection(FsPaths.contentFiles).count().get();
      total = agg.count ?? 0;
    } catch (_) {}
    return _Overview(
      sections: mains.length + subs.length + secs.length,
      content: total,
      documents: 0,
      audio: 0,
      video: 0,
    );
  }

  /// نشاط الرفع آخر ٣٠ يوماً — يُحسب من وثائق المحتوى (كاش المستودع).
  Future<List<_DayBar>> _loadChart() async {
    final rows = await ContentRepository.instance.listFiles();
    final now = DateTime.now();
    final start =
        DateTime(now.year, now.month, now.day).subtract(const Duration(days: 29));
    final map = <String, _DayBar>{};
    for (var i = 0; i < 30; i++) {
      final d = start.add(Duration(days: i));
      final key = DateFormat('yyyy-MM-dd').format(d);
      map[key] = _DayBar(d);
    }
    for (final r in rows) {
      final dt = _toDate(r.createdAt);
      if (dt == null) continue;
      final day = DateTime(dt.year, dt.month, dt.day);
      if (day.isBefore(start)) continue;
      final key = DateFormat('yyyy-MM-dd').format(day);
      final bar = map[key];
      if (bar == null) continue;
      switch (r.contentType) {
        case 'video':
          bar.video++;
          break;
        case 'audio':
          bar.audio++;
          break;
        default:
          bar.document++;
      }
    }
    return map.values.toList()..sort((a, b) => a.date.compareTo(b.date));
  }

  DateTime? _toDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is String) return DateTime.tryParse(v);
    if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ov = _overview;
    if (ov == null) {
      // لا كاش بعد (أوّل استخدام): تحميل أو خطأ.
      if (_error != null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline,
                    color: NebrasColors.rose, size: 40),
                const SizedBox(height: 12),
                Text(_error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: NebrasColors.rose, fontSize: 12)),
                const SizedBox(height: 12),
                FilledButton(
                    onPressed: _refresh, child: const Text('إعادة المحاولة')),
              ],
            ),
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('لوحة القيادة',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ),
              if (_refreshing)
                const Row(
                  children: [
                    SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 6),
                    Text('يُحدَّث…',
                        style: TextStyle(
                            fontSize: 11, color: NebrasColors.textMuted)),
                  ],
                )
              else if (_cachedAt != null)
                Text(
                  'آخر تحديث ${DateFormat('HH:mm').format(_cachedAt!)}',
                  style: const TextStyle(
                      fontSize: 10.5, color: NebrasColors.textMuted),
                ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'نظرة عامة على نشاطك والمحتوى المرفوع والأقسام المخصصة لك ومقاييسك الشخصية ستعرض هنا.',
            style: TextStyle(fontSize: 12, color: NebrasColors.textMuted),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                  child: StatCard(
                      label: 'إجمالي المحتوى',
                      value: '${ov.content}',
                      icon: Icons.folder_copy_outlined,
                      color: _cAudio)),
              const SizedBox(width: 12),
              Expanded(
                  child: StatCard(
                      label: 'إجمالي الأقسام',
                      value: '${ov.sections}',
                      icon: Icons.account_tree_outlined,
                      color: NebrasColors.rose)),
            ],
          ),
          const SizedBox(height: 20),
          const Text('توزيع المحتوى',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _distributionCard(ov),
          const SizedBox(height: 20),
          const Text('نشاط الرفع (٣٠ يوماً)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _activityCard(),
        ],
      ),
    );
  }

  Widget _distributionCard(_Overview ov) {
    final total = ov.documents + ov.audio + ov.video;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SizedBox(
              height: 180,
              child: total == 0
                  ? const Center(
                      child: Text('لا بيانات',
                          style: TextStyle(color: NebrasColors.textMuted)))
                  : PieChart(
                      PieChartData(
                        centerSpaceRadius: 50,
                        sectionsSpace: 2,
                        sections: [
                          if (ov.video > 0)
                            PieChartSectionData(
                                value: ov.video.toDouble(),
                                color: _cVideo,
                                title: '${ov.video}',
                                radius: 38,
                                titleStyle: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                          if (ov.audio > 0)
                            PieChartSectionData(
                                value: ov.audio.toDouble(),
                                color: _cAudio,
                                title: '${ov.audio}',
                                radius: 38,
                                titleStyle: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                          if (ov.documents > 0)
                            PieChartSectionData(
                                value: ov.documents.toDouble(),
                                color: _cDoc,
                                title: '${ov.documents}',
                                radius: 38,
                                titleStyle: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 16,
              children: [
                _legend('فيديو', _cVideo),
                _legend('صوت', _cAudio),
                _legend('مستند', _cDoc),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _legend(String label, Color color) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      );

  Widget _activityCard() {
    final bars = _bars;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
        child: SizedBox(
          height: 220,
          child: bars == null
              ? const Center(child: CircularProgressIndicator())
              : Builder(builder: (context) {
                  final maxY = bars.fold<double>(
                      0, (m, b) => b.total > m ? b.total.toDouble() : m);
                  if (maxY == 0) {
                    return const Center(
                        child: Text('لا نشاط في آخر ٣٠ يوماً',
                            style: TextStyle(color: NebrasColors.textMuted)));
                  }
                  return BarChart(
                    BarChartData(
                      maxY: (maxY * 1.2).ceilToDouble(),
                      barTouchData: BarTouchData(enabled: true),
                      gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          getDrawingHorizontalLine: (_) => const FlLine(
                              color: Color(0xFF3F3F46), strokeWidth: 0.5)),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        leftTitles: const AxisTitles(
                            sideTitles:
                                SideTitles(showTitles: true, reservedSize: 26)),
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            interval: 6,
                            getTitlesWidget: (v, meta) {
                              final i = v.toInt();
                              if (i < 0 || i >= bars.length) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                    DateFormat('M/d').format(bars[i].date),
                                    style: const TextStyle(
                                        fontSize: 9,
                                        color: NebrasColors.textMuted)),
                              );
                            },
                          ),
                        ),
                      ),
                      barGroups: [
                        for (var i = 0; i < bars.length; i++)
                          BarChartGroupData(x: i, barRods: [
                            BarChartRodData(
                              toY: bars[i].total.toDouble(),
                              width: 5,
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(2)),
                              rodStackItems: [
                                BarChartRodStackItem(
                                    0, bars[i].document.toDouble(), _cDoc),
                                BarChartRodStackItem(
                                    bars[i].document.toDouble(),
                                    (bars[i].document + bars[i].audio)
                                        .toDouble(),
                                    _cAudio),
                                BarChartRodStackItem(
                                    (bars[i].document + bars[i].audio)
                                        .toDouble(),
                                    bars[i].total.toDouble(),
                                    _cVideo),
                              ],
                            ),
                          ]),
                      ],
                    ),
                  );
                }),
        ),
      ),
    );
  }
}

class _Overview {
  _Overview({
    required this.sections,
    required this.content,
    required this.documents,
    required this.audio,
    required this.video,
  });
  final int sections, content, documents, audio, video;
}

class _DayBar {
  _DayBar(this.date);
  final DateTime date;
  int video = 0, audio = 0, document = 0;
  int get total => video + audio + document;
}
