import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

/// Datasource handling file download operations
/// Uses Dio for HTTP downloads with resume support via Range headers
class DownloadDatasource {
  final Dio dio;

  /// Active cancel tokens keyed by contentId
  final Map<String, CancelToken> _cancelTokens = {};

  DownloadDatasource(this.dio);

  /// Get the local directory for media downloads
  Future<String> _getDownloadDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final downloadDir = Directory('${dir.path}/media_downloads');
    if (!await downloadDir.exists()) {
      await downloadDir.create(recursive: true);
    }
    return downloadDir.path;
  }

  /// Build a local file path for a given content
  Future<String> getFilePath(String contentId, String extension) async {
    final dir = await _getDownloadDir();
    return '$dir/$contentId.$extension';
  }

  /// Start or resume a download
  /// [savePath] — final file path (without .part)
  /// [startByte] — byte offset for resume (0 = fresh download)
  /// [onProgress] — progress callback (0.0 – 1.0)
  Future<void> startDownload({
    required String url,
    required String savePath,
    int startByte = 0,
    required Function(double progress, int totalBytes) onProgress,
    required String contentId,
  }) async {
    final partPath = '$savePath.part';
    final cancelToken = CancelToken();
    _cancelTokens[contentId] = cancelToken;

    // ملاحظة استئناف: `dio.download` يفتح الملفّ دائماً بوضع الكتابة من
    // الصفر (truncate) ولا يُلحِق. إرسال ترويسة `Range: bytes=$startByte-`
    // كان يجعل الخادم يردّ بالبايتات بدءاً من [startByte] بينما تُكتب في
    // بداية الملفّ → ملفّ نهائيّ **تالف** بحجم خاطئ. ولأنّ الحزمة لا تدعم
    // الإلحاق، نُعيد التنزيل كاملاً (نتجاهل [startByte]) لضمان سلامة الملفّ.
    // الكفاءة المفقودة (إعادة تنزيل الجزء المنزَّل) ثمنٌ مقبول مقابل عدم
    // إنتاج ملفّات تالفة.
    try {
      await dio.download(
        url,
        partPath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            onProgress(received / total, total);
          }
        },
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          receiveTimeout: const Duration(minutes: 30),
          sendTimeout: const Duration(minutes: 1),
        ),
        deleteOnError: false,
        cancelToken: cancelToken,
      );

      // Rename .part to final file on success
      final partFile = File(partPath);
      if (await partFile.exists()) {
        await partFile.rename(savePath);
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        throw Exception('Download cancelled');
      } else if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        throw Exception('Download timeout. Please check your connection.');
      } else if (e.type == DioExceptionType.connectionError) {
        throw Exception(
          'Network error. Please check your internet connection.',
        );
      } else {
        throw Exception('Download failed: ${e.message}');
      }
    } finally {
      _cancelTokens.remove(contentId);
    }
  }

  /// Cancel an active download
  void cancelDownload(String contentId) {
    _cancelTokens[contentId]?.cancel('User cancelled download');
    _cancelTokens.remove(contentId);
  }

  /// Delete the downloaded file and its .part file
  Future<void> deleteFile(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
    // Also delete .part file if it exists
    final partFile = File('$path.part');
    if (await partFile.exists()) {
      await partFile.delete();
    }
  }

  /// Check if a file exists at the given path
  Future<bool> fileExists(String path) async {
    return File(path).exists();
  }

  /// Get byte size of a partial download file
  Future<int> getPartialFileSize(String path) async {
    final partFile = File('$path.part');
    if (await partFile.exists()) {
      return partFile.length();
    }
    return 0;
  }

  /// Get total file size from server
  Future<int?> getRemoteFileSize(String url) async {
    try {
      final response = await dio.head(
        url,
        options: Options(receiveTimeout: const Duration(seconds: 10)),
      );
      final contentLength = response.headers.value('content-length');
      return contentLength != null ? int.tryParse(contentLength) : null;
    } catch (e) {
      return null;
    }
  }
}
