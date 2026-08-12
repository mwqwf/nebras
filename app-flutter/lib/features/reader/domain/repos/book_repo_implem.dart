import 'package:nebras_mobile_app/features/reader/data/datasources/book_local_datasource.dart';
import 'package:nebras_mobile_app/features/reader/data/datasources/book_progress_datasource.dart';
import 'package:nebras_mobile_app/features/reader/data/datasources/book_reading_progress_datasource.dart';
import 'package:nebras_mobile_app/features/reader/data/datasources/book_remote_datasource.dart';
import 'package:nebras_mobile_app/features/reader/domain/repos/book_repos.dart';

class BookRepoImplem implements BookRepos {
  final BookRemoteDataSource remote;
  final BookLocalDatasource local;
  final BookProgressDatasource progress;
  final BookReadingProgressDatasource readingProgress;

  BookRepoImplem(
    this.remote,
    this.local,
    this.progress,
    this.readingProgress,
  );

  @override
  Future<void> downloadBook({
    required String bookId,
    required String url,
    required String fileName,
    required Function(double progress) onProgress,
  }) async {
    try {
      // Check if partial download exists
      final hasPartial = await local.hasPartialDownload(fileName);
      int startByte = 0;

      if (hasPartial) {
        // Get size of partial file
        startByte = await local.getPartialFileSize(fileName);

        // Check if server supports resume
        final supportsResume = await remote.supportsResume(url);

        if (!supportsResume || startByte == 0) {
          // Server doesn't support resume or no progress, start fresh
          await local.deletePartialFile(fileName);
          await progress.clearProgress(fileName);
          startByte = 0;
        }
      }

      // Start/resume download
      await remote.downloadBook(
        url: url,
        fileName: fileName,
        onProgress: (p) {
          onProgress(p);
          // Persist progress periodically (every 5% to avoid excessive writes)
          if ((p * 100).toInt() % 5 == 0) {
            final totalSize = remote.getFileSize(url);
            totalSize.then((size) {
              if (size != null) {
                progress.saveProgress(
                  fileName,
                  (p * size).toInt(),
                  size,
                );
              }
            });
          }
        },
        startByte: startByte,
      );

      // Download complete - finalize
      await local.finalizeDownload(fileName);
      await progress.clearProgress(fileName);
    } catch (e) {
      // Keep partial file and progress for resume
      rethrow;
    }
  }

  @override
  Future<bool> isBookDownloaded(String fileName) {
    return local.isDownloaded(fileName);
  }

  @override
  Future<String> getBookPath({
    required String fileName,
    required String networkUrl,
    required bool isDownloaded,
  }) async {
    if (isDownloaded) {
      // Verify file still exists before returning path
      final exists = await local.isDownloaded(fileName);
      if (!exists) {
        throw Exception('Book file not found locally. Please re-download.');
      }
      return await local.getFilePath(fileName);
    } else {
      // Validate network URL
      if (networkUrl.isEmpty) {
        throw Exception('Network URL is empty');
      }
      return networkUrl;
    }
  }

  @override
  Future<void> cancelDownload() async {
    remote.cancelDownload();
  }

  @override
  Future<double?> getStoredProgress(String fileName) async {
    final progressData = await progress.getProgress(fileName);
    if (progressData != null) {
      final downloaded = progressData['downloaded']!;
      final total = progressData['total']!;
      return downloaded / total;
    }
    return null;
  }

  @override
  Future<void> saveLastReadPage(String bookId, int currentPage, int totalPages) {
    return readingProgress.saveLastPage(bookId, currentPage, totalPages);
  }

  @override
  Future<int?> getLastReadPage(String bookId) {
    return readingProgress.getLastPage(bookId);
  }

  @override
  Future<void> clearReadingProgress(String bookId) {
    return readingProgress.clearProgress(bookId);
  }
}
