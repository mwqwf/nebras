import 'package:nebras_mobile_app/features/reader/domain/repos/book_repos.dart';

class GetStoredProgressUsecase {
  final BookRepos repo;
  GetStoredProgressUsecase(this.repo);

  Future<double?> call(String fileName) {
    return repo.getStoredProgress(fileName);
  }
}
