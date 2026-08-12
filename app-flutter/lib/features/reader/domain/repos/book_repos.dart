abstract class BookRepos {
  Future<void> downloadBook({
    required String bookId,
    required String url,
    required String fileName,
    required Function(double progress) onProgress,
  });

  Future<bool> isBookDownloaded(String fileName);

  Future<String> getBookPath({
    required String fileName,
    required String networkUrl,
    required bool isDownloaded,
  });

  Future<void> cancelDownload();

  Future<double?> getStoredProgress(String fileName);

  // Reading progress methods
  Future<void> saveLastReadPage(String bookId, int currentPage, int totalPages);
  
  Future<int?> getLastReadPage(String bookId);
  
  Future<void> clearReadingProgress(String bookId);
}
