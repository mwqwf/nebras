import 'package:nebras_mobile_app/features/audio_player/domain/repos/audio_repos.dart';

class SaveLastPositionUsecase {
  final AudioRepos repo;
  SaveLastPositionUsecase(this.repo);

  Future<void> call({
    required String audioId,
    required Duration position,
    required Duration duration,
  }) {
    // Validate inputs
    if (audioId.isEmpty) {
      throw ArgumentError('audioId cannot be empty');
    }
    if (position.isNegative) {
      throw ArgumentError('position cannot be negative');
    }
    if (duration.inMilliseconds <= 0) {
      throw ArgumentError('duration must be positive');
    }
    if (position > duration) {
      throw ArgumentError('position cannot exceed duration');
    }

    return repo.saveLastPosition(audioId, position, duration);
  }
}
