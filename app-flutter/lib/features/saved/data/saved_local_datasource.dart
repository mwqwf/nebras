import 'package:hive/hive.dart';
import 'package:nebras_mobile_app/features/saved/model/saved_item_model.dart';

/// Saved Items Local Datasource
/// Handles all Hive box operations for saved content
/// NO UI logic, NO Provider, NO Flutter widgets
/// Hive box is NOT exposed outside this class
class SavedLocalDatasource {
  static const String _boxName = 'saved_items';
  Box<SavedItemModel>? _box;

  /// Open the Hive box (call once at startup)
  Future<void> openBox() async {
    if (_box != null && _box!.isOpen) return;
    _box = await Hive.openBox<SavedItemModel>(_boxName);
  }

  /// Ensure box is open before any operation
  Future<Box<SavedItemModel>> _getBox() async {
    if (_box == null || !_box!.isOpen) {
      await openBox();
    }
    return _box!;
  }

  /// Add or update a saved item (keyed by id to prevent duplicates)
  Future<void> addItem(SavedItemModel item) async {
    final box = await _getBox();
    await box.put(item.id, item);
  }

  /// Remove a saved item by id
  Future<void> removeItem(String id) async {
    final box = await _getBox();
    await box.delete(id);
  }

  /// Get a single item by id (returns null if not found)
  Future<SavedItemModel?> getItem(String id) async {
    final box = await _getBox();
    return box.get(id);
  }

  /// Get all saved items, sorted by savedAt descending (newest first)
  Future<List<SavedItemModel>> getAllItems() async {
    final box = await _getBox();
    final items = box.values.toList();
    items.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return items;
  }

  /// Check if an item exists by id
  Future<bool> containsItem(String id) async {
    final box = await _getBox();
    return box.containsKey(id);
  }
}
