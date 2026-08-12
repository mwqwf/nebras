import 'package:nebras_mobile_app/features/saved/data/saved_local_datasource.dart';
import 'package:nebras_mobile_app/features/saved/domain/repo/saved_repository.dart';
import 'package:nebras_mobile_app/features/saved/model/saved_item_model.dart';

/// Repository implementation — delegates to datasource
/// No Hive usage here, only datasource calls
class SavedRepositoryImpl implements SavedRepository {
  final SavedLocalDatasource datasource;

  SavedRepositoryImpl(this.datasource);

  @override
  Future<bool> toggleSave(SavedItemModel item) async {
    final exists = await datasource.containsItem(item.id);
    if (exists) {
      await datasource.removeItem(item.id);
      return false; // was removed
    } else {
      await datasource.addItem(item);
      return true; // was saved
    }
  }

  @override
  Future<bool> isSaved(String id) async {
    return datasource.containsItem(id);
  }

  @override
  Future<List<SavedItemModel>> getAllSaved() async {
    return datasource.getAllItems();
  }

  @override
  Future<void> remove(String id) async {
    await datasource.removeItem(id);
  }
}
