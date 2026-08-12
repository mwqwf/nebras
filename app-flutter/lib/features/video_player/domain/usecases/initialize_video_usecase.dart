import 'package:nebras_mobile_app/features/video_player/domain/repos/video_repos.dart';

/// Initialize Video Use Case
/// Pure Dart - NO Flutter imports
/// Initializes video player with source (local OR network)
class InitializeVideoUsecase {
  final VideoRepos repository;

  InitializeVideoUsecase(this.repository);

  Future<void> call(String source) async {
    if (source.isEmpty) {
      throw ArgumentError('Video source cannot be empty');
    }

    await repository.initializeVideo(source);
  }
}
