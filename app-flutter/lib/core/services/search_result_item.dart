import 'package:nebras_mobile_app/features/content/model/content_model.dart';
import 'package:nebras_mobile_app/features/home/data/home_section_model.dart';

enum SearchItemType { section, item }

enum SearchItemSource { firebase }

class SearchResultItem {
  final String id;
  final String title;
  final SearchItemType type;
  final SearchItemSource source;
  final String subtitle;
  final String? imageUrl;
  final double score;
  final bool fuzzy;
  final HomeSection? section;
  final Content? content;

  const SearchResultItem._({
    required this.id,
    required this.title,
    required this.type,
    required this.source,
    required this.subtitle,
    required this.imageUrl,
    required this.score,
    required this.fuzzy,
    this.section,
    this.content,
  });

  factory SearchResultItem.section({
    required HomeSection section,
    required SearchItemSource source,
    required double score,
    required bool fuzzy,
  }) {
    return SearchResultItem._(
      id: section.id,
      title: section.title,
      type: SearchItemType.section,
      source: source,
      subtitle: _sectionSubtitle(section, source),
      imageUrl: section.imageUrl,
      score: score,
      fuzzy: fuzzy,
      section: section,
    );
  }

  factory SearchResultItem.item({
    required Content content,
    required SearchItemSource source,
    required double score,
    required bool fuzzy,
  }) {
    return SearchResultItem._(
      id: content.id,
      title: content.title,
      type: SearchItemType.item,
      source: source,
      subtitle: _contentSubtitle(content),
      imageUrl: content.thumbnailUrl.trim().isEmpty ? null : content.thumbnailUrl,
      score: score,
      fuzzy: fuzzy,
      content: content,
    );
  }

  String get dedupKey => '${type.name}:${source.name}:$id';

  static String _sectionSubtitle(HomeSection section, SearchItemSource source) {
    return section.type;
  }

  static String _contentSubtitle(Content content) {
    final name = content.sectionName?.trim();
    if (name != null && name.isNotEmpty) return name;
    if (content.author.trim().isNotEmpty) return content.author.trim();
    return content.type.name;
  }
}
