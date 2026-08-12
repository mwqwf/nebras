import 'package:nebras_mobile_app/features/search/domain/repo/search_repository.dart';
import 'package:nebras_mobile_app/features/search/data/search_section_option.dart';

class GetSectionsUseCase {
  final SearchRepository repository;

  GetSectionsUseCase(this.repository);

  Future<List<SearchSectionOption>> call() {
    return repository.getSections();
  }
}
