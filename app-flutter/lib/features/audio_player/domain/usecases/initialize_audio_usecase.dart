import 'package:nebras_mobile_app/features/audio_player/domain/repos/audio_repos.dart';

/// Use-case لتهيئة المشغّل على مصدر جديد مع تمرير بياناته الوصفيّة
/// (العنوان/المؤلّف/الصورة) لتصل إلى MediaSession وشاشة القفل.
class InitializeAudioUsecase {
  final AudioRepos repo;
  InitializeAudioUsecase(this.repo);

  Future<void> call(
    String source, {
    required String mediaId,
    required String title,
    String? album,
    String? artist,
    String? artworkUrl,
  }) {
    if (source.isEmpty) {
      throw ArgumentError('source cannot be empty');
    }
    return repo.initializeAudio(
      source,
      mediaId: mediaId,
      title: title,
      album: album,
      artist: artist,
      artworkUrl: artworkUrl,
    );
  }
}
