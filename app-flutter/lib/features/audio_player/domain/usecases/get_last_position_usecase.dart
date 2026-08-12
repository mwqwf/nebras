import 'package:nebras_mobile_app/features/audio_player/domain/repos/audio_repos.dart';

class GetLastPositionUsecase {
  final AudioRepos repo;
  GetLastPositionUsecase(this.repo);

  Future<Duration?> call(String audioId) {
    if (audioId.isEmpty) {
      throw ArgumentError('audioId cannot be empty');
    }
    
    return repo.getLastPosition(audioId);
  }
}
