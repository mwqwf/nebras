import 'package:shared_preferences/shared_preferences.dart';

/// Handles persistence of reading progress (current page) across app restarts
/// Separate from download progress to maintain single responsibility
class BookReadingProgressDatasource {
  static const String _pagePrefix = 'reading_page_';
  static const String _totalPagesPrefix = 'reading_total_pages_';

  final SharedPreferences prefs;
  BookReadingProgressDatasource(this.prefs);

  /// Save current reading page for a specific book
  Future<void> saveLastPage(
    String bookId,
    int currentPage,
    int totalPages,
  ) async {
    await prefs.setInt('$_pagePrefix$bookId', currentPage);
    await prefs.setInt('$_totalPagesPrefix$bookId', totalPages);
  }

  /// Get last saved reading page
  Future<int?> getLastPage(String bookId) async {
    return prefs.getInt('$_pagePrefix$bookId');
  }

  /// Get total pages (for validation)
  Future<int?> getTotalPages(String bookId) async {
    return prefs.getInt('$_totalPagesPrefix$bookId');
  }

  /// Clear reading progress (e.g., when book is deleted)
  Future<void> clearProgress(String bookId) async {
    await prefs.remove('$_pagePrefix$bookId');
    await prefs.remove('$_totalPagesPrefix$bookId');
  }

  /// Check if there's saved reading progress
  Future<bool> hasProgress(String bookId) async {
    return prefs.containsKey('$_pagePrefix$bookId');
  }
}
