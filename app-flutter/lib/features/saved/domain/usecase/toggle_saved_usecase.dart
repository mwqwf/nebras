import 'package:nebras_mobile_app/features/saved/domain/repo/saved_repository.dart';
import 'package:nebras_mobile_app/features/saved/model/saved_item_model.dart';

class ToggleSavedUseCase {
  final SavedRepository repository;

  ToggleSavedUseCase(this.repository);

  /// Returns true if item was saved, false if removed
  Future<bool> call(SavedItemModel item) {
    return repository.toggleSave(item);
  }
}
