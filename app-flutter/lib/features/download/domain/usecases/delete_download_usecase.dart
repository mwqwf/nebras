import 'package:nebras_mobile_app/features/download/domain/download_repository.dart';

class DeleteDownloadUseCase {
  final DownloadRepository repository;
  DeleteDownloadUseCase(this.repository);

  Future<void> call(String contentId) {
    return repository.deleteDownload(contentId);
  }
}
