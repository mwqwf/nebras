import 'package:nebras_mobile_app/features/reader/domain/repos/book_repos.dart';

class OpenBookUsecase {
  final BookRepos repo;
  OpenBookUsecase(this.repo);

  Future<String> call({
    required String fileName,
    required String networkUrl,
    required bool isDownloaded,
  }) {
    // Validate inputs
    if (fileName.isEmpty) {
      throw ArgumentError('fileName cannot be empty');
    }
    if (!isDownloaded && networkUrl.isEmpty) {
      throw ArgumentError('networkUrl cannot be empty when book is not downloaded');
    }

    return repo.getBookPath(
      fileName: fileName,
      networkUrl: networkUrl,
      isDownloaded: isDownloaded,
    );
  }
}
