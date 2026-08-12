import 'package:flutter/foundation.dart';
import 'package:nebras_mobile_app/features/reader/domain/usecases/cancel_download_usecase.dart';
import 'package:nebras_mobile_app/features/reader/domain/usecases/check_book_download_usecase.dart';
import 'package:nebras_mobile_app/features/reader/domain/usecases/download_book_usecase.dart';
import 'package:nebras_mobile_app/features/reader/domain/usecases/get_stored_progress_usecase.dart';
import 'package:nebras_mobile_app/features/reader/domain/usecases/open_book_usecase.dart';

enum DownloadStatus { idle, downloading, downloaded, error }

class DownloadProvider extends ChangeNotifier {
  final DownloadBookUsecase downloadBookUseCase;
  final CheckBookDownloadedUsecase checkDownloadedUsecase;
  final OpenBookUsecase openBookUsecase;
  final CancelDownloadUsecase cancelDownloadUsecase;
  final GetStoredProgressUsecase getStoredProgressUsecase;

  DownloadProvider(
    this.downloadBookUseCase,
    this.checkDownloadedUsecase,
    this.openBookUsecase,
    this.cancelDownloadUsecase,
    this.getStoredProgressUsecase,
  );

  DownloadStatus _status = DownloadStatus.idle;
  double _progress = 0;
  String? _errorMessage;

  DownloadStatus get status => _status;
  double get progress => _progress;
  String? get errorMessage => _errorMessage;

  /// Check if book is downloaded and restore progress if interrupted
  Future<void> checkIfDownloaded(String fileName) async {
    try {
      final exists = await checkDownloadedUsecase(fileName);
      
      if (exists) {
        _status = DownloadStatus.downloaded;
        _progress = 1.0;
      } else {
        // Check if there's stored progress from interrupted download
        final storedProgress = await getStoredProgressUsecase(fileName);
        
        if (storedProgress != null && storedProgress > 0) {
          // There's a partial download
          _status = DownloadStatus.idle;
          _progress = storedProgress;
        } else {
          _status = DownloadStatus.idle;
          _progress = 0;
        }
      }
      
      notifyListeners();
    } catch (e) {
      // If check fails, assume not downloaded
      _status = DownloadStatus.idle;
      _progress = 0;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> startDownload({
    required String bookId,
    required String url,
    required String fileName,
  }) async {
    // Prevent concurrent downloads
    if (_status == DownloadStatus.downloading) {
      return;
    }

    _status = DownloadStatus.downloading;
    _errorMessage = null;
    // Keep existing progress if resuming
    if (_progress == 0) {
      _progress = 0;
    }
    notifyListeners();

    try {
      await downloadBookUseCase(
        bookId: bookId,
        url: url,
        fileName: fileName,
        onProgress: (p) {
          _progress = p;
          notifyListeners();
        },
      );

      _status = DownloadStatus.downloaded;
      _progress = 1.0;
      notifyListeners();
    } catch (e) {
      _status = DownloadStatus.error;
      _errorMessage = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  /// Cancel ongoing download
  Future<void> cancelDownload() async {
    if (_status != DownloadStatus.downloading) {
      return;
    }

    try {
      await cancelDownloadUsecase();
      _status = DownloadStatus.idle;
      // Keep progress for potential resume
      notifyListeners();
    } catch (e) {
      // Cancellation failed, but update status anyway
      _status = DownloadStatus.error;
      _errorMessage = 'Failed to cancel download';
      notifyListeners();
    }
  }

  Future<String> getBookPathToOpen({
    required String fileName,
    required String networkUrl,
  }) async {
    // Re-verify download status to avoid stale state
    // This handles cases where file was deleted externally
    final actuallyDownloaded = await checkDownloadedUsecase(fileName);
    
    // Update status if it's out of sync
    if (actuallyDownloaded && _status != DownloadStatus.downloaded) {
      _status = DownloadStatus.downloaded;
      _progress = 1.0;
      notifyListeners();
    } else if (!actuallyDownloaded && _status == DownloadStatus.downloaded) {
      _status = DownloadStatus.idle;
      _progress = 0;
      notifyListeners();
    }

    try {
      return await openBookUsecase(
        fileName: fileName,
        networkUrl: networkUrl,
        isDownloaded: actuallyDownloaded,
      );
    } catch (e) {
      // If opening fails and was marked as downloaded, reset status
      if (actuallyDownloaded) {
        _status = DownloadStatus.idle;
        _progress = 0;
        notifyListeners();
      }
      rethrow;
    }
  }
}
