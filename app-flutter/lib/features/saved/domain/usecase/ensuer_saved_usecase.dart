import 'package:nebras_mobile_app/features/saved/domain/repo/saved_repository.dart';
import 'package:nebras_mobile_app/features/saved/model/saved_item_model.dart';

class EnsureSavedUseCase {
  final SavedRepository repository;

  EnsureSavedUseCase(this.repository);

  Future<void> call(SavedItemModel item) async {
    final alreadySaved = await repository.isSaved(item.id);

    if (!alreadySaved) {
      await repository.toggleSave(item);
    }
  }
}
