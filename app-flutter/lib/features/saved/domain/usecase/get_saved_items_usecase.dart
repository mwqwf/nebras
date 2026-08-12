import 'package:nebras_mobile_app/features/saved/domain/repo/saved_repository.dart';
import 'package:nebras_mobile_app/features/saved/model/saved_item_model.dart';

class GetSavedItemsUseCase {
  final SavedRepository repository;

  GetSavedItemsUseCase(this.repository);

  Future<List<SavedItemModel>> call() {
    return repository.getAllSaved();
  }
}
