import 'package:nebras_mobile_app/features/reader/domain/repos/book_repos.dart';

class DownloadBookUsecase {
  final BookRepos repo;
  DownloadBookUsecase(this.repo);
  
  Future<void> call({
    required String bookId,
    required String url,
    required String fileName,
    required Function(double progress) onProgress,
  }) {
    return repo.downloadBook(
      bookId: bookId,
      url: url,
      fileName: fileName,
      onProgress: onProgress,
    );
  }
}
