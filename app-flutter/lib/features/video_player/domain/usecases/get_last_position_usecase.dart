import 'package:nebras_mobile_app/features/video_player/domain/repos/video_repos.dart';

/// Get Last Position Use Case
/// Pure Dart - NO Flutter imports
/// Retrieves last playback position for a video
class GetLastPositionUsecase {
  final VideoRepos repository;

  GetLastPositionUsecase(this.repository);

  Future<Duration?> call(String videoId) async {
    if (videoId.isEmpty) {
      throw ArgumentError('Video ID cannot be empty');
    }

    return await repository.getLastPosition(videoId);
  }
}
