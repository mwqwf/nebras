import 'package:nebras_mobile_app/features/content/model/content_model.dart';
import 'package:nebras_mobile_app/features/search/domain/repo/search_repository.dart';

class GetSectionContentUseCase {
  final SearchRepository repository;

  GetSectionContentUseCase(this.repository);

  Future<List<Content>> call(String sectionId) {
    return repository.getSectionContent(sectionId);
  }
}
