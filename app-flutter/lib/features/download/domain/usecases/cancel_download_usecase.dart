import 'package:nebras_mobile_app/features/download/domain/download_repository.dart';

class CancelDownloadUseCase {
  final DownloadRepository repository;
  CancelDownloadUseCase(this.repository);

  Future<void> call(String contentId) {
    return repository.cancelDownload(contentId);
  }
}
