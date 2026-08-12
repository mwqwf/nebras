import 'package:hive/hive.dart';
import 'package:nebras_mobile_app/features/download/data/download_datasource.dart';
import 'package:nebras_mobile_app/features/download/data/download_item_model.dart';
import 'package:nebras_mobile_app/features/download/domain/download_repository.dart';

/// Download Repository Implementation
/// Combines DownloadDatasource (file I/O) with Hive (persistence)
class DownloadRepositoryImpl implements DownloadRepository {
  final DownloadDatasource datasource;
  final Box<DownloadItemModel> box;

  DownloadRepositoryImpl(this.datasource, this.box);

  /// يستنتج امتداد الملف من الرابط أوّلاً (أدقّ)، ثمّ يرجع لـ contentType
  /// كاحتياطيّ. هذا يُتيح تحميل محتوى الأرشيف بامتداداته الحقيقيّة
  /// (.ogg / .m4a / .mkv …) بدل افتراض mp3/mp4 دائماً.
  static String _ext(String url, String contentType) {
    final path = url.toLowerCase().split('?').first.split('#').first;
    const audioExts = ['.mp3', '.m4a', '.aac', '.ogg', '.opus', '.flac', '.wav', '.wma'];
    const videoExts = ['.mp4', '.mkv', '.mov', '.webm', '.m4v', '.avi', '.3gp', '.ogv'];
    for (final e in audioExts) {
      if (path.endsWith(e)) return e.substring(1);
    }
    for (final e in videoExts) {
      if (path.endsWith(e)) return e.substring(1);
    }
    if (path.endsWith('.pdf')) return 'pdf';
    if (path.endsWith('.epub')) return 'epub';
    if (contentType == 'audio') return 'mp3';
    if (contentType == 'document') return 'pdf';
    return 'mp4';
  }

  @override
  Future<void> startDownload({
    required String contentId,
    required String url,
    required String contentType,
    required Function(double progress, int totalBytes) onProgress,
  }) async {
    final ext = _ext(url, contentType);
    final localPath = await datasource.getFilePath(contentId, ext);

    // Save initial state
    final item = DownloadItemModel(
      contentId: contentId,
      url: url,
      localPath: localPath,
      progress: 0.0,
      status: 'downloading',
      totalBytes: 0,
      contentType: contentType,
    );
    await box.put(contentId, item);

    await datasource.startDownload(
      url: url,
      savePath: localPath,
      startByte: 0,
      onProgress: (progress, totalBytes) {
        // Update Hive periodically (every 5%)
        final current = box.get(contentId);
        if (current != null) {
          final diff = progress - current.progress;
          if (diff >= 0.05 || progress >= 1.0) {
            box.put(
              contentId,
              current.copyWith(progress: progress, totalBytes: totalBytes),
            );
          }
        }
        onProgress(progress, totalBytes);
      },
      contentId: contentId,
    );

    // Mark completed
    final completed = box.get(contentId);
    if (completed != null) {
      await box.put(
        contentId,
        completed.copyWith(status: 'completed', progress: 1.0),
      );
    }
  }

  @override
  void pauseDownload(String contentId) {
    datasource.cancelDownload(contentId); // cancel the HTTP request
    final item = box.get(contentId);
    if (item != null) {
      box.put(contentId, item.copyWith(status: 'paused'));
    }
  }

  @override
  Future<void> resumeDownload({
    required String contentId,
    required Function(double progress, int totalBytes) onProgress,
  }) async {
    final item = box.get(contentId);
    if (item == null) return;

    final startByte = await datasource.getPartialFileSize(item.localPath);

    await box.put(contentId, item.copyWith(status: 'downloading'));

    await datasource.startDownload(
      url: item.url,
      savePath: item.localPath,
      startByte: startByte,
      onProgress: (progress, totalBytes) {
        final current = box.get(contentId);
        if (current != null) {
          final diff = progress - current.progress;
          if (diff >= 0.05 || progress >= 1.0) {
            box.put(
              contentId,
              current.copyWith(progress: progress, totalBytes: totalBytes),
            );
          }
        }
        onProgress(progress, totalBytes);
      },
      contentId: contentId,
    );

    // Mark completed
    final completed = box.get(contentId);
    if (completed != null) {
      await box.put(
        contentId,
        completed.copyWith(status: 'completed', progress: 1.0),
      );
    }
  }

  @override
  Future<void> cancelDownload(String contentId) async {
    datasource.cancelDownload(contentId);
    final item = box.get(contentId);
    if (item != null) {
      await datasource.deleteFile(item.localPath);
      await box.delete(contentId);
    }
  }

  @override
  Future<void> deleteDownload(String contentId) async {
    final item = box.get(contentId);
    if (item != null) {
      await datasource.deleteFile(item.localPath);
      await box.delete(contentId);
    }
  }

  @override
  DownloadItemModel? getDownloadItem(String contentId) {
    return box.get(contentId);
  }

  @override
  Map<String, DownloadItemModel> getAllDownloads() {
    final map = <String, DownloadItemModel>{};
    for (final key in box.keys) {
      final item = box.get(key);
      if (item != null) {
        map[key.toString()] = item;
      }
    }
    return map;
  }

  @override
  Future<void> saveDownloadItem(DownloadItemModel item) async {
    await box.put(item.contentId, item);
  }
}
