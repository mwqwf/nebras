import 'package:flutter/material.dart';
import 'package:nebras_mobile_app/core/services/hidden_content_service.dart';
import 'package:nebras_mobile_app/features/saved/domain/usecase/get_saved_items_usecase.dart';
import 'package:nebras_mobile_app/features/saved/domain/usecase/is_saved_usecase.dart';
import 'package:nebras_mobile_app/features/saved/domain/usecase/remove_saved_usecase.dart';
import 'package:nebras_mobile_app/features/saved/domain/usecase/toggle_saved_usecase.dart';
import 'package:nebras_mobile_app/features/saved/model/saved_item_model.dart';

class SavedProvider extends ChangeNotifier {
  final ToggleSavedUseCase _toggleSavedUseCase;
  final GetSavedItemsUseCase _getSavedItemsUseCase;
  final IsSavedUseCase _isSavedUseCase;
  final RemoveSavedUseCase _removeSavedUseCase;

  SavedProvider(
    this._toggleSavedUseCase,
    this._getSavedItemsUseCase,
    this._isSavedUseCase,
    this._removeSavedUseCase,
  );

  List<SavedItemModel> _savedItems = [];
  final Set<String> _savedIds = {};
  bool _isLoading = false;

  // نستبعد المحتوى الذي أبلغ عنه المستخدم احترامًا لرأيه (يبقى محفوظاً في
  // Hive لكنه لا يُعرَض). إعادة البناء عند الإبلاغ مضمونة لأنّ المستهلكين
  // يراقبون [HiddenContentService] أيضاً.
  List<SavedItemModel> get savedItems => _savedItems
      .where((item) => !HiddenContentService.instance.isHidden(item.id))
      .toList(growable: false);
  Set<String> get savedIds => _savedIds;
  bool get isLoading => _isLoading;

  List<SavedItemModel> getFiltered(SavedContentType? type) {
    return savedItems.where((item) {
      if (type != null && item.type != type) return false;
      return true;
    }).toList();
  }

  Future<void> loadSaved() async {
    _isLoading = true;
    notifyListeners();

    try {
      _savedItems = await _getSavedItemsUseCase();

      _savedIds
        ..clear()
        ..addAll(_savedItems.map((e) => e.id));
    } catch (e) {
      debugPrint('Failed to load saved items: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  bool isSaved(String id) {
    return _savedIds.contains(id);
  }

  Future<bool> checkIsSaved(String id) async {
    return _isSavedUseCase(id);
  }

  /// 🔥 NEW — called when download completes
  void addFromDownload(SavedItemModel item) {
    if (_savedIds.contains(item.id)) return;

    _savedIds.add(item.id);
    _savedItems.insert(0, item);

    notifyListeners();
  }

  /// إعادة عنصر محذوف (زرّ "تراجع" بعد السحب). يُعيد كتابته في Hive
  /// عبر use case الحفظ حتى لا تتباعد الذاكرة عن التخزين.
  Future<void> restoreSaved(SavedItemModel item) async {
    if (_savedIds.contains(item.id)) return;
    _savedIds.add(item.id);
    _savedItems.insert(0, item);
    notifyListeners();
    try {
      await _toggleSavedUseCase(item);
    } catch (e) {
      _savedIds.remove(item.id);
      _savedItems.removeWhere((e2) => e2.id == item.id);
      notifyListeners();
    }
  }

  Future<void> toggle(SavedItemModel item) async {
    final wasSaved = _savedIds.contains(item.id);

    if (wasSaved) {
      _savedIds.remove(item.id);
      _savedItems.removeWhere((e) => e.id == item.id);
    } else {
      _savedIds.add(item.id);
      _savedItems.insert(0, item);
    }

    notifyListeners();

    try {
      await _toggleSavedUseCase(item);
    } catch (e) {
      if (wasSaved) {
        _savedIds.add(item.id);
        _savedItems.insert(0, item);
      } else {
        _savedIds.remove(item.id);
        _savedItems.removeWhere((e) => e.id == item.id);
      }

      notifyListeners();
    }
  }

  /// يمسح كلّ المفضّلة المحليّة — يُستعمل عند حذف الحساب لإزالة كامل
  /// بيانات المستخدم من الجهاز.
  Future<void> clearAll() async {
    final ids = _savedItems.map((e) => e.id).toList(growable: false);
    _savedItems = [];
    _savedIds.clear();
    notifyListeners();
    for (final id in ids) {
      try {
        await _removeSavedUseCase(id);
      } catch (_) {}
    }
  }

  Future<void> remove(String id) async {
    final removedItem = _savedItems.firstWhere(
      (e) => e.id == id,
      orElse: () => SavedItemModel(
        id: id,
        title: '',
        contentType: '',
        savedAt: DateTime.now(),
      ),
    );

    final removedIndex = _savedItems.indexOf(removedItem);

    _savedIds.remove(id);
    _savedItems.removeWhere((e) => e.id == id);

    notifyListeners();

    try {
      await _removeSavedUseCase(id);
    } catch (e) {
      _savedIds.add(id);

      if (removedIndex >= 0 && removedIndex <= _savedItems.length) {
        _savedItems.insert(removedIndex, removedItem);
      } else {
        _savedItems.add(removedItem);
      }

      notifyListeners();
    }
  }
}
