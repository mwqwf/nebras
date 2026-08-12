import 'package:nebras_mobile_app/features/download/data/download_item_model.dart';

/// Abstract contract for Download Repository
abstract class DownloadRepository {
  /// Start a new download
  Future<void> startDownload({
    required String contentId,
    required String url,
    required String contentType,
    required Function(double progress, int totalBytes) onProgress,
  });

  /// Pause an active download
  void pauseDownload(String contentId);

  /// Resume a paused download
  Future<void> resumeDownload({
    required String contentId,
    required Function(double progress, int totalBytes) onProgress,
  });

  /// Cancel and clean up a download
  Future<void> cancelDownload(String contentId);

  /// Delete a completed download
  Future<void> deleteDownload(String contentId);

  /// Get the current download item from persistence
  DownloadItemModel? getDownloadItem(String contentId);

  /// Get all persisted download items
  Map<String, DownloadItemModel> getAllDownloads();

  /// Save download item to persistence
  Future<void> saveDownloadItem(DownloadItemModel item);
}
