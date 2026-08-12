import 'package:nebras_mobile_app/features/reader/domain/repos/book_repos.dart';

class SaveLastPageUsecase {
  final BookRepos repo;
  SaveLastPageUsecase(this.repo);

  Future<void> call({
    required String bookId,
    required int currentPage,
    required int totalPages,
  }) {
    // Validate inputs
    if (bookId.isEmpty) {
      throw ArgumentError('bookId cannot be empty');
    }
    if (currentPage < 0) {
      throw ArgumentError('currentPage cannot be negative');
    }
    if (totalPages <= 0) {
      throw ArgumentError('totalPages must be positive');
    }
    if (currentPage > totalPages) {
      throw ArgumentError('currentPage cannot exceed totalPages');
    }

    return repo.saveLastReadPage(bookId, currentPage, totalPages);
  }
}
