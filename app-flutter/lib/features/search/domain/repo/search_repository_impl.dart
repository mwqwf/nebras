import 'package:nebras_mobile_app/features/content/model/content_model.dart';
import 'package:nebras_mobile_app/features/search/data/search_datasource.dart';
import 'package:nebras_mobile_app/features/search/data/search_section_option.dart';
import 'package:nebras_mobile_app/features/search/domain/repo/search_repository.dart';

/// Search Repository Implementation
/// Delegates all calls to SearchDatasource — no UI logic
class SearchRepositoryImpl implements SearchRepository {
  final SearchDatasource datasource;

  SearchRepositoryImpl(this.datasource);

  @override
  Future<List<Content>> search({
    required String query,
    ContentType? type,
    String? section,
    String? subSection,
  }) {
    return datasource.search(
      query: query,
      type: type,
      section: section,
      subSection: subSection,
    );
  }

  @override
  Future<List<SearchSectionOption>> getSections() {
    return datasource.getSections();
  }

  @override
  Future<List<Content>> getSectionContent(String sectionId) {
    return datasource.getSectionContent(sectionId);
  }
}
