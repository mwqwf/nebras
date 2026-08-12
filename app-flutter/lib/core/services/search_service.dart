import 'package:flutter/foundation.dart';
import 'package:nebras_mobile_app/core/services/search_result_item.dart';
import 'package:nebras_mobile_app/core/services/user_behavior_tracker.dart';
import 'package:nebras_mobile_app/core/utils/text_normalizer.dart';
import 'package:nebras_mobile_app/features/content/model/content_model.dart';
import 'package:nebras_mobile_app/features/home/data/home_section_model.dart';
import 'package:nebras_mobile_app/features/search/domain/usecase/search_content_usecase.dart';

/// SearchService — **البوّابة الشاملة** للبحث الموحَّد عبر محتوى Firebase RTDB.
class SearchService {
  final SearchContentUseCase _firebaseUseCase;

  const SearchService({
    required SearchContentUseCase firebaseUseCase,
  }) : _firebaseUseCase = firebaseUseCase;

  Future<SearchServiceResult> search({
    required String query,
    required List<HomeSection> sections,
    ContentType? type,
    String? section,
    String? subSection,
    int maxSections = 30,
    int maxContentPerSource = 40,
    int maxSuggestions = 12,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const SearchServiceResult(items: []);

    final parts = await Future.wait([
      _searchSections(query: q, sections: sections, maxSections: maxSections),
      _searchContent(
        query: q,
        type: type,
        section: section,
        subSection: subSection,
        maxPerSource: maxContentPerSource,
        localSections: sections,
      ),
    ]);

    final sectionExact = parts[0]
        .where((e) => !e.fuzzy)
        .toList(growable: false);
    final sectionFuzzy = parts[0].where((e) => e.fuzzy).toList(growable: false);
    final contentExact = parts[1]
        .where((e) => !e.fuzzy)
        .toList(growable: false);
    final contentFuzzy = parts[1].where((e) => e.fuzzy).toList(growable: false);

    final hasExact = sectionExact.isNotEmpty || contentExact.isNotEmpty;
    final merged = hasExact
        ? _sortByScore(<SearchResultItem>[...sectionExact, ...contentExact])
        : _sortByScore(<SearchResultItem>[...sectionFuzzy, ...contentFuzzy]);
    final primaryItems = _dedup(merged);

    var fallbackReason = SearchFallbackReason.none;
    var finalItems = primaryItems;
    if (primaryItems.isEmpty) {
      final closest = _closestSectionFallback(q, sections);
      if (closest.isNotEmpty) {
        finalItems = closest;
        fallbackReason = SearchFallbackReason.closestSection;
      } else {
        final popular = _popularFallback(sections, maxItems: 20);
        if (popular.isNotEmpty) {
          finalItems = popular;
          fallbackReason = SearchFallbackReason.popular;
        }
      }
    }

    final suggestions = fallbackReason == SearchFallbackReason.none
        ? _buildSuggestions(
            query: q,
            primary: primaryItems,
            sections: sections,
            maxSuggestions: maxSuggestions,
          )
        : const <SearchResultItem>[];

    return SearchServiceResult(
      items: finalItems,
      suggestions: suggestions,
      fallbackReason: fallbackReason,
    );
  }

  Future<List<SearchResultItem>> _searchSections({
    required String query,
    required List<HomeSection> sections,
    required int maxSections,
  }) async {
    final out = <SearchResultItem>[];
    final seenIds = <String>{};
    for (final section in _flattenSections(sections)) {
      if (!seenIds.add(section.id)) continue;
      final hay = _sectionHaystack(section);
      if (hay.isEmpty) continue;
      final exact = substringMatches(hay, query);
      final score = relevanceScore(query, hay);
      final include = exact || score >= 0.20;
      if (!include) continue;
      out.add(
        SearchResultItem.section(
          section: section,
          source: SearchItemSource.firebase,
          score: score,
          fuzzy: !exact,
        ),
      );
    }
    final sorted = _sortByScore(out);
    return sorted.take(maxSections).toList(growable: false);
  }

  Future<List<SearchResultItem>> _searchContent({
    required String query,
    required ContentType? type,
    required String? section,
    required String? subSection,
    required int maxPerSource,
    required List<HomeSection> localSections,
  }) async {
    final firebaseItems = await _searchFirebase(
      query: query,
      type: type,
      section: section,
      subSection: subSection,
    );

    final localContent = <_SourceContent>[];
    for (final sec in _flattenSections(localSections)) {
      for (final item in sec.items) {
        localContent.add(
          _SourceContent(
            content: item,
            source: SearchItemSource.firebase,
            parentSection: sec,
          ),
        );
      }
    }

    final out = <SearchResultItem>[];
    for (final source in [...firebaseItems, ...localContent]) {
      final hay = _contentHaystack(source.content, source.parentSection);
      final exact = substringMatches(hay, query);
      final score = relevanceScore(query, hay);
      final include = exact || score >= 0.20;
      if (!include) continue;
      out.add(
        SearchResultItem.item(
          content: source.content,
          source: source.source,
          score: score,
          fuzzy: !exact,
        ),
      );
    }
    return out;
  }

  Iterable<HomeSection> _flattenSections(List<HomeSection> roots) => roots;

  String _sectionHaystack(HomeSection section) {
    final title = section.title.trim();
    final type = section.type.trim();
    if (title.isEmpty) return type;
    if (type.isEmpty) return title;
    return '$title $type';
  }

  String _contentHaystack(Content c, HomeSection? parent) {
    final parts = <String>[
      c.title,
      c.description,
      c.author,
      if (c.sectionName?.isNotEmpty ?? false) c.sectionName!,
      if (c.subSection?.isNotEmpty ?? false) c.subSection!,
      if (parent != null && parent.title.isNotEmpty) parent.title,
    ];
    return parts.where((e) => e.trim().isNotEmpty).join(' ');
  }

  List<SearchResultItem> _closestSectionFallback(
    String query,
    List<HomeSection> sections,
  ) {
    if (sections.isEmpty) return const [];
    final scored = <MapEntry<HomeSection, double>>[];
    for (final sec in _flattenSections(sections)) {
      final hay = _sectionHaystack(sec);
      if (hay.isEmpty) continue;
      final s = relevanceScore(query, hay);
      if (s <= 0.0) continue;
      scored.add(MapEntry(sec, s));
    }
    if (scored.isEmpty) return const [];
    scored.sort((a, b) => b.value.compareTo(a.value));

    final out = <SearchResultItem>[];
    final seen = <String>{};
    for (final entry in scored.take(3)) {
      final sec = entry.key;
      final source = SearchItemSource.firebase;
      out.add(
        SearchResultItem.section(
          section: sec,
          source: source,
          score: entry.value,
          fuzzy: true,
        ),
      );
      final items = List<Content>.of(sec.items)
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      for (final item in items.take(6)) {
        final key = 'item:$source:${item.id}';
        if (!seen.add(key)) continue;
        out.add(
          SearchResultItem.item(
            content: item,
            source: source,
            score: entry.value * 0.9,
            fuzzy: true,
          ),
        );
      }
    }
    return out;
  }

  List<SearchResultItem> _popularFallback(
    List<HomeSection> sections, {
    int maxItems = 20,
  }) {
    if (sections.isEmpty) return const [];
    final byId = {for (final s in sections) s.id: s};
    final out = <SearchResultItem>[];
    final seen = <String>{};

    final popularIds = UserBehaviorTracker.instance.topSectionIds(limit: 12);
    for (final id in popularIds) {
      final sec = byId[id];
      if (sec == null) continue;
      final source = SearchItemSource.firebase;
      final items = List<Content>.of(sec.items)
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      for (final item in items.take(4)) {
        final key = 'item:$source:${item.id}';
        if (!seen.add(key)) continue;
        out.add(
          SearchResultItem.item(
            content: item,
            source: source,
            score: 0.1,
            fuzzy: true,
          ),
        );
        if (out.length >= maxItems) return out;
      }
    }

    if (out.isEmpty) {
      final allItems = <Content>[];
      for (final sec in sections) {
        allItems.addAll(sec.items);
      }
      allItems.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      for (final item in allItems.take(maxItems)) {
        out.add(
          SearchResultItem.item(
            content: item,
            source: SearchItemSource.firebase,
            score: 0.05,
            fuzzy: true,
          ),
        );
      }
    }
    return out;
  }

  List<SearchResultItem> _buildSuggestions({
    required String query,
    required List<SearchResultItem> primary,
    required List<HomeSection> sections,
    required int maxSuggestions,
  }) {
    if (primary.isEmpty || sections.isEmpty || maxSuggestions <= 0) {
      return const [];
    }
    final seenKeys = {for (final p in primary) p.dedupKey};
    final out = <SearchResultItem>[];
    final byId = {for (final s in sections) s.id: s};

    final top = primary.first;
    HomeSection? anchorSection;
    if (top.type == SearchItemType.section && top.section != null) {
      anchorSection = top.section;
    } else if (top.content != null) {
      final anchorId = top.content!.section;
      anchorSection = byId[anchorId];
    }
    if (anchorSection != null) {
      final source = SearchItemSource.firebase;
      final items = List<Content>.of(anchorSection.items)
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      for (final item in items) {
        final candidate = SearchResultItem.item(
          content: item,
          source: source,
          score: 0.6,
          fuzzy: true,
        );
        if (seenKeys.add(candidate.dedupKey)) {
          out.add(candidate);
          if (out.length >= maxSuggestions) return out;
        }
      }
    }

    final similar = <MapEntry<HomeSection, double>>[];
    for (final sec in _flattenSections(sections)) {
      if (sec.id == anchorSection?.id) continue;
      if (sec.items.isEmpty) continue;
      final overlap = keywordOverlapScore(query, _sectionHaystack(sec));
      final score = overlap > 0 ? overlap : relevanceScore(query, sec.title);
      if (score <= 0.0) continue;
      similar.add(MapEntry(sec, score));
    }
    similar.sort((a, b) => b.value.compareTo(a.value));
    for (final entry in similar.take(5)) {
      final sec = entry.key;
      final source = SearchItemSource.firebase;
      final items = List<Content>.of(sec.items)
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      for (final item in items.take(3)) {
        final candidate = SearchResultItem.item(
          content: item,
          source: source,
          score: 0.4 * entry.value,
          fuzzy: true,
        );
        if (seenKeys.add(candidate.dedupKey)) {
          out.add(candidate);
          if (out.length >= maxSuggestions) return out;
        }
      }
    }

    if (out.length < maxSuggestions) {
      final popular = _popularFallback(
        sections,
        maxItems: maxSuggestions - out.length,
      );
      for (final p in popular) {
        if (seenKeys.add(p.dedupKey)) {
          out.add(p);
          if (out.length >= maxSuggestions) break;
        }
      }
    }

    return out;
  }

  Future<List<_SourceContent>> _searchFirebase({
    required String query,
    required ContentType? type,
    required String? section,
    required String? subSection,
  }) async {
    try {
      final items = await _firebaseUseCase(
        query: query,
        type: type,
        section: section,
        subSection: subSection,
      );
      return items
          .map(
            (e) =>
                _SourceContent(content: e, source: SearchItemSource.firebase),
          )
          .toList(growable: false);
    } catch (e) {
      debugPrint('[SearchService] firebase error: $e');
      return const [];
    }
  }

  List<SearchResultItem> _sortByScore(List<SearchResultItem> input) {
    final sorted = input.toList()
      ..sort((a, b) {
        final cmp = b.score.compareTo(a.score);
        if (cmp != 0) return cmp;
        if (a.type != b.type) {
          return a.type == SearchItemType.section ? -1 : 1;
        }
        return a.title.compareTo(b.title);
      });
    return sorted;
  }

  List<SearchResultItem> _dedup(List<SearchResultItem> input) {
    final out = <SearchResultItem>[];
    final seen = <String>{};
    for (final item in input) {
      if (seen.add(item.dedupKey)) out.add(item);
    }
    return out;
  }
}

enum SearchFallbackReason { none, closestSection, popular }

class SearchServiceResult {
  final List<SearchResultItem> items;
  final List<SearchResultItem> suggestions;
  final SearchFallbackReason fallbackReason;

  const SearchServiceResult({
    required this.items,
    this.suggestions = const [],
    this.fallbackReason = SearchFallbackReason.none,
  });

  bool get isEmpty => items.isEmpty;
  bool get isNotEmpty => !isEmpty;
  bool get usedFallback => fallbackReason != SearchFallbackReason.none;
}

class _SourceContent {
  final Content content;
  final SearchItemSource source;
  final HomeSection? parentSection;

  const _SourceContent({
    required this.content,
    required this.source,
    this.parentSection,
  });
}
