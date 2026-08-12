import 'package:nebras_mobile_app/features/video_player/domain/repos/video_repos.dart';

/// Save Last Position Use Case
/// Pure Dart - NO Flutter imports
/// Persists video playback position
class SaveLastPositionUsecase {
  final VideoRepos repository;

  SaveLastPositionUsecase(this.repository);

  Future<void> call({
    required String videoId,
    required Duration position,
    required Duration duration,
  }) async {
    if (videoId.isEmpty) {
      throw ArgumentError('Video ID cannot be empty');
    }

    if (position.isNegative) {
      throw ArgumentError('Position cannot be negative');
    }

    if (duration.isNegative || duration == Duration.zero) {
      throw ArgumentError('Duration must be positive');
    }

    await repository.saveLastPosition(videoId, position, duration);
  }
}
