import 'package:nebras_mobile_app/features/download/data/download_item_model.dart';
import 'package:nebras_mobile_app/features/download/domain/download_repository.dart';

class GetDownloadStatusUseCase {
  final DownloadRepository repository;
  GetDownloadStatusUseCase(this.repository);

  DownloadItemModel? call(String contentId) {
    return repository.getDownloadItem(contentId);
  }
}
