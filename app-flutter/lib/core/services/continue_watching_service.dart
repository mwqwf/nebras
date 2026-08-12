import 'dart:convert';

import 'package:nebras_mobile_app/features/content/model/content_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// تقدّم غير مكتمل — **محليّ فقط** (لا يُرفع إلى Firebase).
///
/// يُغذّي رفّ «تابع التصفّح» في الصفحة الرئيسيّة.
/// يُخفى العنصر إذا اكتمل (>90%) أو مرّ عليه >14 يوماً.
class ContinueWatchingService {
  ContinueWatchingService._();

  static final ContinueWatchingService instance = ContinueWatchingService._();

  static const _kEntries = 'continue_watching_v1';
  static const _maxEntries = 24;
  static const _staleAfter = Duration(days: 14);

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  Future<void> saveProgress({
    required String contentId,
    required int positionMs,
    required int durationMs,
    required String title,
    required String thumbnailUrl,
    required ContentType type,
  }) async {
    if (contentId.trim().isEmpty || durationMs <= 0) return;
    await init();
    final ratio = positionMs / durationMs;
    if (ratio >= 0.9) {
      await remove(contentId);
      return;
    }
    if (ratio < 0.02) return;

    final map = await _readMap();
    map[contentId] = {
      'contentId': contentId,
      'positionMs': positionMs,
      'durationMs': durationMs,
      'title': title,
      'thumbnailUrl': thumbnailUrl,
      'type': type.name,
      'savedAt': DateTime.now().toIso8601String(),
    };
    final sorted = map.entries.toList()
      ..sort((a, b) {
        final at = DateTime.tryParse(
              '${a.value['savedAt']}',
            ) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bt = DateTime.tryParse(
              '${b.value['savedAt']}',
            ) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bt.compareTo(at);
      });
    final trimmed = <String, dynamic>{
      for (final e in sorted.take(_maxEntries)) e.key: e.value,
    };
    await _prefs!.setString(_kEntries, jsonEncode(trimmed));
  }

  Future<void> remove(String contentId) async {
    await init();
    final map = await _readMap();
    if (map.remove(contentId) != null) {
      await _prefs!.setString(_kEntries, jsonEncode(map));
    }
  }

  /// مسح كامل — تسجيل الخروج أو «نسيان اهتماماتي».
  Future<void> clearAll() async {
    await init();
    await _prefs!.remove(_kEntries);
  }

  Future<List<ContinueWatchingEntry>> activeEntries() async {
    await init();
    final map = await _readMap();
    final now = DateTime.now();
    final out = <ContinueWatchingEntry>[];
    final staleKeys = <String>[];

    map.forEach((id, raw) {
      final savedAt = DateTime.tryParse('${raw['savedAt']}');
      if (savedAt == null ||
          now.difference(savedAt) > _staleAfter) {
        staleKeys.add(id);
        return;
      }
      final durationMs = (raw['durationMs'] as num?)?.toInt() ?? 0;
      final positionMs = (raw['positionMs'] as num?)?.toInt() ?? 0;
      if (durationMs <= 0) {
        staleKeys.add(id);
        return;
      }
      final ratio = positionMs / durationMs;
      if (ratio >= 0.9) {
        staleKeys.add(id);
        return;
      }
      out.add(
        ContinueWatchingEntry(
          contentId: id,
          title: '${raw['title'] ?? ''}',
          thumbnailUrl: '${raw['thumbnailUrl'] ?? ''}',
          type: _parseType('${raw['type']}'),
          positionMs: positionMs,
          durationMs: durationMs,
          savedAt: savedAt,
        ),
      );
    });

    for (final k in staleKeys) {
      map.remove(k);
    }
    if (staleKeys.isNotEmpty) {
      await _prefs!.setString(_kEntries, jsonEncode(map));
    }

    out.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return out;
  }

  Future<Map<String, dynamic>> _readMap() async {
    final raw = _prefs?.getString(_kEntries);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map(
        (k, v) => MapEntry(k.toString(), Map<String, dynamic>.from(v as Map)),
      );
    } catch (_) {
      return {};
    }
  }

  ContentType _parseType(String name) {
    for (final t in ContentType.values) {
      if (t.name == name) return t;
    }
    return ContentType.video;
  }
}

class ContinueWatchingEntry {
  final String contentId;
  final String title;
  final String thumbnailUrl;
  final ContentType type;
  final int positionMs;
  final int durationMs;
  final DateTime savedAt;

  const ContinueWatchingEntry({
    required this.contentId,
    required this.title,
    required this.thumbnailUrl,
    required this.type,
    required this.positionMs,
    required this.durationMs,
    required this.savedAt,
  });

  double get progressRatio =>
      durationMs > 0 ? (positionMs / durationMs).clamp(0.0, 1.0) : 0.0;
}
