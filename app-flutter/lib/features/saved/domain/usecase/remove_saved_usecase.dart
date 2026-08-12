import 'package:nebras_mobile_app/features/saved/domain/repo/saved_repository.dart';

class RemoveSavedUseCase {
  final SavedRepository repository;

  RemoveSavedUseCase(this.repository);

  Future<void> call(String id) {
    return repository.remove(id);
  }
}
