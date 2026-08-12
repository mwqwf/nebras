import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:nebras_mobile_app/core/network/api_constants.dart';

/// Singleton cache for section name resolution.
/// Resolves subsection IDs to human-readable names via
/// /api/public/sections/sub/{id}/ and caches the result in-memory.
class SectionNameCache {
  final Dio dio;

  SectionNameCache(this.dio);

  /// In-memory cache: subsection ID → resolved name
  final Map<String, String> _cache = {};

  /// Resolve a subsection ID to its display name.
  /// Returns the cached name if available, otherwise fetches from API.
  /// Falls back to returning the raw [id] on any error.
  Future<String> resolve(String id) async {
    if (id.isEmpty) return id;

    // Return cached value
    if (_cache.containsKey(id)) return _cache[id]!;

    try {
      final response = await dio.get('${ApiConstants.subSections}$id/');
      final data = response.data;

      String? name;
      if (data is Map<String, dynamic>) {
        name = data['name'] as String?;
      }

      final resolved = (name != null && name.isNotEmpty) ? name : id;
      _cache[id] = resolved;
      return resolved;
    } catch (e) {
      debugPrint('SectionNameCache: failed to resolve "$id": $e');
      // Cache the ID itself to avoid repeated failed requests
      _cache[id] = id;
      return id;
    }
  }

  /// Resolve multiple IDs in parallel.
  /// Useful when processing a batch of grouped sections.
  Future<void> resolveAll(Iterable<String> ids) async {
    final unresolved = ids.where((id) => id.isNotEmpty && !_cache.containsKey(id)).toSet();
    if (unresolved.isEmpty) return;

    await Future.wait(unresolved.map((id) => resolve(id)));
  }

  /// Clear the cache (e.g. on logout or language change).
  void clear() => _cache.clear();
}
