import 'package:nebras_mobile_app/features/saved/domain/repo/saved_repository.dart';

class IsSavedUseCase {
  final SavedRepository repository;

  IsSavedUseCase(this.repository);

  Future<bool> call(String id) {
    return repository.isSaved(id);
  }
}
