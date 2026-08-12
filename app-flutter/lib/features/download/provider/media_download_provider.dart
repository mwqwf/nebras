import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nebras_mobile_app/features/download/data/download_item_model.dart';
import 'package:nebras_mobile_app/features/download/domain/download_repository.dart';
import 'package:nebras_mobile_app/features/download/domain/usecases/start_download_usecase.dart';
import 'package:nebras_mobile_app/features/download/domain/usecases/pause_download_usecase.dart';
import 'package:nebras_mobile_app/features/download/domain/usecases/resume_download_usecase.dart';
import 'package:nebras_mobile_app/features/download/domain/usecases/cancel_download_usecase.dart';
import 'package:nebras_mobile_app/features/download/domain/usecases/delete_download_usecase.dart';
import 'package:nebras_mobile_app/features/download/domain/usecases/get_download_status_usecase.dart';
import 'package:nebras_mobile_app/features/saved/domain/usecase/ensuer_saved_usecase.dart';
import 'package:nebras_mobile_app/features/saved/model/saved_item_model.dart';
import 'package:nebras_mobile_app/features/saved/provider/saved_provider.dart';

class MediaDownloadProvider extends ChangeNotifier {
  final StartDownloadUseCase _startUseCase;
  final PauseDownloadUseCase _pauseUseCase;
  final ResumeDownloadUseCase _resumeUseCase;
  final CancelDownloadUseCase _cancelUseCase;
  final DeleteDownloadUseCase _deleteUseCase;
  final GetDownloadStatusUseCase _getStatusUseCase;
  final DownloadRepository _repository;
  final EnsureSavedUseCase _ensureSavedUseCase;
  final SavedProvider _savedProvider;

  MediaDownloadProvider(
    this._startUseCase,
    this._pauseUseCase,
    this._resumeUseCase,
    this._cancelUseCase,
    this._deleteUseCase,
    this._getStatusUseCase,
    this._repository,
    this._ensureSavedUseCase,
    this._savedProvider,
  );

  // ───────────────── STATE ─────────────────
  final Map<String, DownloadItemModel> _downloads = {};

  Map<String, DownloadItemModel> get downloads => Map.unmodifiable(_downloads);

  // ───────────────── RESTORE DOWNLOADS ─────────────────
  Future<void> restoreDownloads() async {
    try {
      final persisted = _repository.getAllDownloads();

      _downloads.clear();

      for (final entry in persisted.entries) {
        final item = entry.value;

        // If app closed during download → mark paused
        if (item.downloadStatus == MediaDownloadStatus.downloading) {
          final paused = item.copyWith(status: 'paused');
          _repository.saveDownloadItem(paused);
          _downloads[entry.key] = paused;
        } else {
          _downloads[entry.key] = item;
        }

        // If already completed → ensure saved
        if (item.downloadStatus == MediaDownloadStatus.completed) {
          await _ensureSavedUseCase(
            SavedItemModel(
              id: item.contentId,
              title: item.title.isNotEmpty ? item.title : item.contentId,
              imageUrl: item.imageUrl,
              contentType: item.contentType,
              savedAt: DateTime.now(),
            ),
          );
        }
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Restore downloads failed: $e');
    }
  }

  // ───────────────── STATUS HELPERS ─────────────────
  MediaDownloadStatus getStatus(String contentId) {
    return _downloads[contentId]?.downloadStatus ?? MediaDownloadStatus.idle;
  }

  double getProgress(String contentId) {
    return _downloads[contentId]?.progress ?? 0.0;
  }

  String? getLocalPath(String contentId) {
    final item = _downloads[contentId];

    if (item != null &&
        item.downloadStatus == MediaDownloadStatus.completed &&
        item.localPath.isNotEmpty) {
      final file = File(item.localPath);

      if (file.existsSync()) {
        return item.localPath;
      } else {
        debugPrint('Downloaded file missing: ${item.localPath}');
      }
    }

    return null;
  }

  // ───────────────── START DOWNLOAD ─────────────────
  Future<void> start(
    String contentId,
    String url,
    String contentType, {
    String title = '',
    String? imageUrl,
  }) async {
    final current = _downloads[contentId];

    // Prevent duplicate downloads
    if (current != null &&
        (current.downloadStatus == MediaDownloadStatus.downloading ||
            current.downloadStatus == MediaDownloadStatus.completed)) {
      return;
    }

    // Use contentId as fallback title
    final displayTitle = title.isNotEmpty ? title : contentId;

    // Optimistic UI state
    _downloads[contentId] = DownloadItemModel(
      contentId: contentId,
      url: url,
      localPath: '',
      progress: 0.0,
      status: 'downloading',
      totalBytes: 0,
      contentType: contentType,
      title: displayTitle,
      imageUrl: imageUrl,
    );

    notifyListeners();

    try {
      await _startUseCase(
        contentId: contentId,
        url: url,
        contentType: contentType,
        onProgress: (progress, totalBytes) {
          // قد يُحذف المفتاح إن ألغى المستخدم/حذف التنزيل أثناء جريانه؛
          // نتجاهل تحديث التقدّم المتأخّر بدل تفجير null-check.
          final existing = _downloads[contentId];
          if (existing == null) return;
          _downloads[contentId] = existing.copyWith(
            progress: progress,
            totalBytes: totalBytes,
            status: 'downloading',
          );

          notifyListeners();
        },
      );

      final updated = _getStatusUseCase(contentId);

      if (updated != null) {
        _downloads[contentId] = updated;

        if (updated.downloadStatus == MediaDownloadStatus.completed) {
          final savedItem = SavedItemModel(
            id: contentId,
            title: displayTitle,
            imageUrl: imageUrl,
            contentType: contentType,
            savedAt: DateTime.now(),
          );

          await _ensureSavedUseCase(savedItem);

          _savedProvider.addFromDownload(savedItem);
        }
      }

      notifyListeners();
    } catch (e) {
      final msg = e.toString();

      if (!msg.contains('cancelled')) {
        final existing = _downloads[contentId];
        if (existing != null) {
          _downloads[contentId] = existing.copyWith(status: 'failed');
          notifyListeners();
        }
      }
    }
  }

  // ───────────────── PAUSE ─────────────────
  void pause(String contentId) {
    if (getStatus(contentId) != MediaDownloadStatus.downloading) return;

    _pauseUseCase(contentId);

    _downloads[contentId] = _downloads[contentId]!.copyWith(status: 'paused');

    notifyListeners();
  }

  // ───────────────── RESUME ─────────────────
  Future<void> resume(String contentId) async {
    final current = _downloads[contentId];

    if (current == null) return;

    if (current.downloadStatus != MediaDownloadStatus.paused &&
        current.downloadStatus != MediaDownloadStatus.failed) {
      return;
    }

    _downloads[contentId] = current.copyWith(status: 'downloading');

    notifyListeners();

    try {
      await _resumeUseCase(
        contentId: contentId,
        onProgress: (progress, totalBytes) {
          final existing = _downloads[contentId];
          if (existing == null) return;
          _downloads[contentId] = existing.copyWith(
            progress: progress,
            totalBytes: totalBytes,
            status: 'downloading',
          );

          notifyListeners();
        },
      );

      final fromStatus = _getStatusUseCase(contentId);
      final existing = _downloads[contentId];
      if (fromStatus != null) {
        _downloads[contentId] = fromStatus;
        notifyListeners();
      } else if (existing != null) {
        _downloads[contentId] =
            existing.copyWith(status: 'completed', progress: 1.0);
        notifyListeners();
      }
    } catch (e) {
      final msg = e.toString();

      if (!msg.contains('cancelled')) {
        final existing = _downloads[contentId];
        if (existing != null) {
          _downloads[contentId] = existing.copyWith(status: 'failed');
          notifyListeners();
        }
      }
    }
  }

  // ───────────────── CANCEL ─────────────────
  Future<void> cancel(String contentId) async {
    await _cancelUseCase(contentId);

    _downloads.remove(contentId);

    notifyListeners();
  }

  // ───────────────── DELETE ─────────────────
  Future<void> delete(String contentId) async {
    await _deleteUseCase(contentId);

    _downloads.remove(contentId);

    notifyListeners();
  }
}
