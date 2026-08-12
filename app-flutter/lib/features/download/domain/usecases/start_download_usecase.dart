import 'package:nebras_mobile_app/features/download/domain/download_repository.dart';

class StartDownloadUseCase {
  final DownloadRepository repository;
  StartDownloadUseCase(this.repository);

  Future<void> call({
    required String contentId,
    required String url,
    required String contentType,
    required Function(double progress, int totalBytes) onProgress,
  }) {
    return repository.startDownload(
      contentId: contentId,
      url: url,
      contentType: contentType,
      onProgress: onProgress,
    );
  }
}
