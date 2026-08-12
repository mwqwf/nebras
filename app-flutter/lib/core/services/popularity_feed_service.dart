import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nebras_mobile_app/core/firebase/firestore_sync_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// يقرأ `aggregates_popular/top_weekly` — مستند واحد لتجنّب استعلامات باهظة.
///
/// كاش محلّي 6 ساعات. راجع [docs/CONTENT_ORDERING_AND_HOME.md].
class PopularityFeedService {
  PopularityFeedService._();

  static final PopularityFeedService instance = PopularityFeedService._();

  static const _docPath = 'aggregates_popular/top_weekly';
  static const _cacheKey = 'popular_weekly_ids_v1';
  static const _cacheAtKey = 'popular_weekly_cached_at_v1';
  static const _cacheTtl = Duration(hours: 6);

  List<String> _ids = const [];
  DateTime? _loadedAt;

  List<String> get popularIds => List.unmodifiable(_ids);

  Future<List<String>> loadPopularIds({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _loadedAt != null &&
        DateTime.now().difference(_loadedAt!) < _cacheTtl &&
        _ids.isNotEmpty) {
      return _ids;
    }

    final prefs = await SharedPreferences.getInstance();
    if (!forceRefresh) {
      final cachedAt = prefs.getInt(_cacheAtKey);
      final cachedRaw = prefs.getString(_cacheKey);
      if (cachedAt != null &&
          cachedRaw != null &&
          DateTime.now().millisecondsSinceEpoch - cachedAt <
              _cacheTtl.inMilliseconds) {
        try {
          final list = (jsonDecode(cachedRaw) as List)
              .map((e) => e.toString())
              .toList();
          _ids = list;
          _loadedAt = DateTime.now();
          return _ids;
        } catch (_) {}
      }
    }

    try {
      final snap = await FirestoreSyncConfig.instance.doc(_docPath).get();
      if (!snap.exists) {
        _ids = const [];
        _loadedAt = DateTime.now();
        return _ids;
      }
      final data = snap.data() ?? {};
      final rawIds = data['ids'];
      if (rawIds is List) {
        _ids = rawIds.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
      } else {
        _ids = const [];
      }
      _loadedAt = DateTime.now();
      await prefs.setString(_cacheKey, jsonEncode(_ids));
      await prefs.setInt(_cacheAtKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('[PopularityFeed] load failed: $e');
    }
    return _ids;
  }

  void clearMemoryCache() {
    _ids = const [];
    _loadedAt = null;
  }

  Future<void> clearDiskCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKey);
    await prefs.remove(_cacheAtKey);
    clearMemoryCache();
  }
}
