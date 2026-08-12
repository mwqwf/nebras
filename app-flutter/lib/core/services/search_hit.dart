import 'package:nebras_mobile_app/features/content/model/content_model.dart';
import 'package:nebras_mobile_app/features/home/data/home_section_model.dart';

enum SearchHitKind { section, content }

class SearchHit {
  final SearchHitKind kind;
  final String id;
  final String title;
  final String subtitle;
  final String? imageUrl;
  final double score;
  final int sourcePriority;
  final HomeSection? section;
  final Content? content;

  const SearchHit._({
    required this.kind,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.score,
    required this.sourcePriority,
    this.section,
    this.content,
  });

  factory SearchHit.fromSection(
    HomeSection section, {
    required double score,
    String? subtitleOverride,
  }) {
    return SearchHit._(
      kind: SearchHitKind.section,
      id: section.id,
      title: section.title,
      subtitle: subtitleOverride ?? _sectionSubtitle(section),
      imageUrl: section.imageUrl,
      score: score,
      sourcePriority: _sectionPriority(section),
      section: section,
    );
  }

  factory SearchHit.fromContent(
    Content content, {
    required double score,
    int sourcePriority = 0,
  }) {
    return SearchHit._(
      kind: SearchHitKind.content,
      id: content.id,
      title: content.title,
      subtitle: _contentSubtitle(content),
      imageUrl: content.thumbnailUrl.isEmpty ? null : content.thumbnailUrl,
      score: score,
      sourcePriority: sourcePriority,
      content: content,
    );
  }

  String get dedupKey => '${kind.name}:$id';

  double get rankingScore => score * 10 + sourcePriority;

  static String _sectionSubtitle(HomeSection s) {
    switch (s.type) {
      case 'main_section':
        return 'Main section';
      case 'sub_section':
        return 'Sub section';
      case 'secondary_section':
        return 'Secondary section';
      default:
        return s.type;
    }
  }

  static String _contentSubtitle(Content c) {
    final sectionName = c.sectionName?.trim();
    if (sectionName != null && sectionName.isNotEmpty) return sectionName;
    if (c.author.trim().isNotEmpty) return c.author.trim();
    return c.type.name;
  }

  static int _sectionPriority(HomeSection s) {
    switch (s.type) {
      case 'main_section':
        return 5;
      case 'sub_section':
        return 4;
      case 'secondary_section':
        return 3;
      default:
        return 2;
    }
  }
}
