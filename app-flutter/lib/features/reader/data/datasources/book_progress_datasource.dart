import 'package:shared_preferences/shared_preferences.dart';

/// Handles persistence of download progress across app restarts
class BookProgressDatasource {
  static const String _progressPrefix = 'download_progress_';
  static const String _totalPrefix = 'download_total_';

  final SharedPreferences prefs;
  BookProgressDatasource(this.prefs);

  /// Save download progress for a specific file
  Future<void> saveProgress(String fileName, int downloaded, int total) async {
    await prefs.setInt('$_progressPrefix$fileName', downloaded);
    await prefs.setInt('$_totalPrefix$fileName', total);
  }

  /// Get saved download progress
  Future<Map<String, int>?> getProgress(String fileName) async {
    final downloaded = prefs.getInt('$_progressPrefix$fileName');
    final total = prefs.getInt('$_totalPrefix$fileName');

    if (downloaded != null && total != null) {
      return {'downloaded': downloaded, 'total': total};
    }
    return null;
  }

  /// Clear progress after successful download
  Future<void> clearProgress(String fileName) async {
    await prefs.remove('$_progressPrefix$fileName');
    await prefs.remove('$_totalPrefix$fileName');
  }

  /// Check if there's saved progress for a file
  Future<bool> hasProgress(String fileName) async {
    return prefs.containsKey('$_progressPrefix$fileName');
  }
}
