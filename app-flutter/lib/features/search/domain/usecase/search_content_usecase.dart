import 'package:nebras_mobile_app/features/content/model/content_model.dart';
import 'package:nebras_mobile_app/features/search/domain/repo/search_repository.dart';

class SearchContentUseCase {
  final SearchRepository repository;

  SearchContentUseCase(this.repository);

  Future<List<Content>> call({
    required String query,
    ContentType? type,
    String? section,
    String? subSection,
  }) {
    return repository.search(
      query: query,
      type: type,
      section: section,
      subSection: subSection,
    );
  }
}
