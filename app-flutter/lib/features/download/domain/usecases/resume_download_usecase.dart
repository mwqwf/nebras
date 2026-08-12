import 'package:nebras_mobile_app/features/download/domain/download_repository.dart';

class ResumeDownloadUseCase {
  final DownloadRepository repository;
  ResumeDownloadUseCase(this.repository);

  Future<void> call({
    required String contentId,
    required Function(double progress, int totalBytes) onProgress,
  }) {
    return repository.resumeDownload(
      contentId: contentId,
      onProgress: onProgress,
    );
  }
}
