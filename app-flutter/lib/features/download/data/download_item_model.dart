import 'package:hive/hive.dart';

part 'download_item_model.g.dart';

/// Status of a download
enum MediaDownloadStatus { idle, downloading, paused, completed, failed }

/// Hive-persisted model for a download item
@HiveType(typeId: 1)
class DownloadItemModel {
  @HiveField(0)
  final String contentId;

  @HiveField(1)
  final String url;

  @HiveField(2)
  final String localPath;

  @HiveField(3)
  final double progress;

  @HiveField(4)
  final String status; // stored as string for Hive simplicity

  @HiveField(5)
  final int totalBytes;

  @HiveField(6)
  final String contentType; // 'video', 'audio', or 'book'

  @HiveField(7)
  final String title;

  @HiveField(8)
  final String? imageUrl;

  const DownloadItemModel({
    required this.contentId,
    required this.url,
    required this.localPath,
    this.progress = 0.0,
    this.status = 'idle',
    this.totalBytes = 0,
    required this.contentType,
    this.title = '',
    this.imageUrl,
  });

  /// Parse status string to enum
  MediaDownloadStatus get downloadStatus {
    switch (status) {
      case 'downloading':
        return MediaDownloadStatus.downloading;
      case 'paused':
        return MediaDownloadStatus.paused;
      case 'completed':
        return MediaDownloadStatus.completed;
      case 'failed':
        return MediaDownloadStatus.failed;
      default:
        return MediaDownloadStatus.idle;
    }
  }

  /// Create a copy with updated fields
  DownloadItemModel copyWith({
    String? contentId,
    String? url,
    String? localPath,
    double? progress,
    String? status,
    int? totalBytes,
    String? contentType,
    String? title,
    String? imageUrl,
  }) {
    return DownloadItemModel(
      contentId: contentId ?? this.contentId,
      url: url ?? this.url,
      localPath: localPath ?? this.localPath,
      progress: progress ?? this.progress,
      totalBytes: totalBytes ?? this.totalBytes,
      status: status ?? this.status,
      contentType: contentType ?? this.contentType,
      title: title ?? this.title,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }
}
