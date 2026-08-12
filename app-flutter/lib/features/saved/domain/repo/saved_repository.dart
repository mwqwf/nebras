import 'package:nebras_mobile_app/features/saved/model/saved_item_model.dart';

/// Abstract contract for Saved Repository
abstract class SavedRepository {
  Future<bool> toggleSave(SavedItemModel item);
  Future<bool> isSaved(String id);
  Future<List<SavedItemModel>> getAllSaved();
  Future<void> remove(String id);
}
