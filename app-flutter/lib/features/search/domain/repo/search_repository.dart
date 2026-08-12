import 'package:nebras_mobile_app/features/content/model/content_model.dart';
import 'package:nebras_mobile_app/features/search/data/search_section_option.dart';

/// Abstract contract for Search Repository
abstract class SearchRepository {
  Future<List<Content>> search({
    required String query,
    ContentType? type,
    String? section,
    String? subSection,
  });

  Future<List<SearchSectionOption>> getSections();

  Future<List<Content>> getSectionContent(String sectionId);
}
