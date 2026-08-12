import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

class BookRemoteDataSource {
  final Dio dio;
  CancelToken? _cancelToken;

  BookRemoteDataSource(this.dio);

  /// Download book with resume support using HTTP Range headers
  Future<void> downloadBook({
    required String url,
    required String fileName,
    required Function(double progress) onProgress,
    int startByte = 0,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final filePath = '${dir.path}/$fileName.pdf.part';

    // Create new cancel token for this download
    _cancelToken = CancelToken();

    try {
      await dio.download(
        url,
        filePath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            // Add startByte to received for resume scenarios
            final totalReceived = startByte + received;
            final totalSize = startByte + total;
            onProgress(totalReceived / totalSize);
          }
        },
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          receiveTimeout: const Duration(minutes: 5),
          sendTimeout: const Duration(minutes: 1),
          headers: startByte > 0 ? {'Range': 'bytes=$startByte-'} : null,
        ),
        deleteOnError: false, // Keep partial file on error for resume
        cancelToken: _cancelToken,
      );
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
    } catch (e) {
      throw Exception('Unexpected error during download: $e');
    }
  }

  /// Cancel ongoing download
  void cancelDownload() {
    _cancelToken?.cancel('User cancelled download');
    _cancelToken = null;
  }

  /// Check if server supports resume (HTTP Range)
  Future<bool> supportsResume(String url) async {
    try {
      final response = await dio.head(
        url,
        options: Options(receiveTimeout: const Duration(seconds: 10)),
      );

      final acceptRanges = response.headers.value('accept-ranges');
      return acceptRanges?.toLowerCase() == 'bytes';
    } catch (e) {
      // If HEAD request fails, assume no resume support
      return false;
    }
  }

  /// Get total file size from server
  Future<int?> getFileSize(String url) async {
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
