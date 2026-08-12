import 'package:nebras_mobile_app/features/reader/domain/repos/book_repos.dart';

class CheckBookDownloadedUsecase {
  final BookRepos repo;
  CheckBookDownloadedUsecase(this.repo);

  Future<bool> call(String fileName) {
    return repo.isBookDownloaded(fileName);
  }
}
