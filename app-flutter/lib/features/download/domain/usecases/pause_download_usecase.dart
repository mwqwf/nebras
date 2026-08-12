import 'package:nebras_mobile_app/features/download/domain/download_repository.dart';

class PauseDownloadUseCase {
  final DownloadRepository repository;
  PauseDownloadUseCase(this.repository);

  void call(String contentId) {
    repository.pauseDownload(contentId);
  }
}
