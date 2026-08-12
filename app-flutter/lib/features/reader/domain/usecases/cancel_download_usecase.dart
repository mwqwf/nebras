import 'package:nebras_mobile_app/features/reader/domain/repos/book_repos.dart';

class CancelDownloadUsecase {
  final BookRepos repo;
  CancelDownloadUsecase(this.repo);

  Future<void> call() {
    return repo.cancelDownload();
  }
}
