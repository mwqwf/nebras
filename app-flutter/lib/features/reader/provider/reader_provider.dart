import 'package:flutter/foundation.dart';
import 'package:nebras_mobile_app/features/reader/domain/usecases/get_last_page_usecase.dart';
import 'package:nebras_mobile_app/features/reader/domain/usecases/save_last_page_usecase.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provider for PDF Reader feature
/// Orchestrates reading progress persistence
/// Does NOT decide source type (local vs network) - that's already handled by OpenBookUsecase
class ReaderProvider extends ChangeNotifier {
  final GetLastPageUsecase getLastPageUsecase;
  final SaveLastPageUsecase saveLastPageUsecase;

  ReaderProvider(this.getLastPageUsecase, this.saveLastPageUsecase);

  int _currentPage = 0;
  int _totalPages = 0;
  bool _isControlsVisible = true;
  bool _isLoading = true;
  ReadingMode _readingMode = ReadingMode.vertical;

  int get currentPage => _currentPage;
  int get totalPages => _totalPages;
  bool get isControlsVisible => _isControlsVisible;
  bool get isLoading => _isLoading;
  ReadingMode get readingMode => _readingMode;

  /// Initialize reader - restore last page if exists
  Future<void> initializeReader(String bookId) async {
    await _loadReadingMode();
    _isLoading = true;
    notifyListeners();

    try {
      final lastPage = await getLastPageUsecase(bookId);

      if (lastPage != null && lastPage > 0) {
        _currentPage = lastPage;
      } else {
        _currentPage = 0;
      }
    } catch (e) {
      // If restore fails, start from page 0
      _currentPage = 0;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Update current page and persist
  Future<void> onPageChanged({
    required String bookId,
    required int newPage,
    required int totalPages,
  }) async {
    _currentPage = newPage;
    _totalPages = totalPages;
    notifyListeners();

    // Persist in background (don't await to avoid blocking UI)
    saveLastPageUsecase(
      bookId: bookId,
      currentPage: newPage,
      totalPages: totalPages,
    ).catchError((e) {
      // Log error but don't disrupt reading experience
      debugPrint('Failed to save reading progress: $e');
    });
  }

  /// Toggle reader controls visibility
  void toggleControls() {
    _isControlsVisible = !_isControlsVisible;
    notifyListeners();
  }

  /// Set total pages (called when PDF loads)
  void setTotalPages(int total) {
    _totalPages = total;
    notifyListeners();
  }

  Future<void> _loadReadingMode() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('reading_mode');
    if (saved == 'horizontal') {
      _readingMode = ReadingMode.horizontal;
    }
  }

  Future<void> toggleReadingMode() async {
    _readingMode = _readingMode == ReadingMode.vertical
        ? ReadingMode.horizontal
        : ReadingMode.vertical;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('reading_mode', _readingMode.name);
    notifyListeners();
  }

  /// Reset state (called on dispose)
  void reset() {
    _currentPage = 0;
    _totalPages = 0;
    _isControlsVisible = true;
    _isLoading = true;
  }
}

enum ReadingMode { vertical, horizontal }
