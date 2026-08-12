import 'package:flutter/foundation.dart';
import 'package:nebras_mobile_app/core/services/search_hit.dart';
import 'package:nebras_mobile_app/core/utils/text_normalizer.dart';
import 'package:nebras_mobile_app/features/content/model/content_model.dart';
import 'package:nebras_mobile_app/features/home/data/home_section_model.dart';
import 'package:nebras_mobile_app/features/search/domain/usecase/search_content_usecase.dart';

class GlobalSearchEngine {
  final SearchContentUseCase _firebase;

  static const double _minRelevance = 0.35;

  GlobalSearchEngine({
    required SearchContentUseCase firebaseUseCase,
  }) : _firebase = firebaseUseCase;

  Future<GlobalSearchResult> search({
    required String query,
    required List<HomeSection> sections,
    ContentType? type,
    String? section,
    String? subSection,
    int maxSections = 10,
    int maxContentPerSource = 20,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return const GlobalSearchResult._(
        sectionHits: [],
        firebase: [],
      );
    }

    final sectionHits = _rankSections(
      sections: sections,
      query: trimmed,
      limit: maxSections,
    );

    final results = await Future.wait<List<Content>>([
      _safeFirebase(
        query: trimmed,
        type: type,
        section: section,
        subSection: subSection,
      ),
    ]);

    return GlobalSearchResult._(
      sectionHits: sectionHits,
      firebase: results[0],
      query: trimmed,
    );
  }

  Future<List<Content>> searchContentOnly({
    required String query,
    ContentType? type,
    String? section,
    String? subSection,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final results = await Future.wait<List<Content>>([
      _safeFirebase(
        query: trimmed,
        type: type,
        section: section,
        subSection: subSection,
      ),
    ]);
    return results[0];
  }

  static List<SearchHit> _rankSections({
    required List<HomeSection> sections,
    required String query,
    required int limit,
  }) {
    final hits = <SearchHit>[];
    for (final s in sections) {
      final title = s.title.trim();
      if (title.isEmpty) continue;
      final score = relevanceScore(query, title);
      if (score < _minRelevance) continue;
      hits.add(SearchHit.fromSection(s, score: score));
    }
    hits.sort((a, b) => b.rankingScore.compareTo(a.rankingScore));
    return hits.take(limit).toList(growable: false);
  }

  Future<List<Content>> _safeFirebase({
    required String query,
    ContentType? type,
    String? section,
    String? subSection,
  }) async {
    try {
      return await _firebase(
        query: query,
        type: type,
        section: section,
        subSection: subSection,
      );
    } catch (e) {
      debugPrint('[GlobalSearchEngine] firebase error: $e');
      return const [];
    }
  }
}

class GlobalSearchResult {
  final List<SearchHit> sectionHits;
  final List<Content> firebase;
  final String query;

  const GlobalSearchResult._({
    required this.sectionHits,
    required this.firebase,
    this.query = '',
  });

  bool get isEmpty => sectionHits.isEmpty && firebase.isEmpty;
  bool get isNotEmpty => !isEmpty;
  int get totalCount => sectionHits.length + firebase.length;

  List<SearchHit> get mergedHits {
    final seen = <String>{};
    final out = <SearchHit>[];

    for (final hit in sectionHits) {
      if (seen.add(hit.dedupKey)) out.add(hit);
    }

    final contentHits = <SearchHit>[];
    for (final c in firebase) {
      if (c.id.trim().isEmpty) continue;
      final score = relevanceScore(query, c.title);
      final adjusted = score < GlobalSearchEngine._minRelevance
          ? GlobalSearchEngine._minRelevance
          : score;
      contentHits.add(
        SearchHit.fromContent(c, score: adjusted, sourcePriority: 2),
      );
    }

    contentHits.sort((a, b) => b.rankingScore.compareTo(a.rankingScore));
    for (final h in contentHits) {
      if (seen.add(h.dedupKey)) out.add(h);
    }
    return out;
  }

  List<Content> get mergedContent {
    final seen = <String>{};
    final out = <Content>[];
    for (final c in firebase) {
      if (c.id.trim().isEmpty) continue;
      if (seen.add(c.id)) out.add(c);
    }
    return out;
  }
}
