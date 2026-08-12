import 'package:nebras_mobile_app/features/reader/domain/repos/book_repos.dart';

class GetLastPageUsecase {
  final BookRepos repo;
  GetLastPageUsecase(this.repo);

  Future<int?> call(String bookId) {
    if (bookId.isEmpty) {
      throw ArgumentError('bookId cannot be empty');
    }
    
    return repo.getLastReadPage(bookId);
  }
}
