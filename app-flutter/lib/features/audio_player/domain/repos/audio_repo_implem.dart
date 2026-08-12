import 'package:nebras_mobile_app/features/audio_player/data/datasources/audio_playback_progress_datasource.dart';
import 'package:nebras_mobile_app/features/audio_player/data/datasources/audio_player_datasource.dart'
    show AudioPlayerDatasource, PlaylistTrackSpec;
import 'package:nebras_mobile_app/features/audio_player/domain/repos/audio_repos.dart';

class AudioRepoImplem implements AudioRepos {
  final AudioPlayerDatasource playerDataSource;
  final AudioPlaybackProgressDatasource progressDataSource;

  AudioRepoImplem(
    this.playerDataSource,
    this.progressDataSource,
  );

  @override
  Future<void> initializeAudio(
    String source, {
    required String mediaId,
    required String title,
    String? album,
    String? artist,
    String? artworkUrl,
  }) {
    return playerDataSource.setSource(
      source,
      mediaId: mediaId,
      title: title,
      album: album,
      artist: artist,
      artworkUrl: artworkUrl,
    );
  }

  @override
  Future<void> initializePlaylist({
    required List<PlaylistTrackSpec> tracks,
    required int initialIndex,
    Duration? initialPosition,
  }) {
    return playerDataSource.setPlaylistSource(
      tracks: tracks,
      initialIndex: initialIndex,
      initialPosition: initialPosition,
    );
  }

  @override
  Future<void> appendTracks(List<PlaylistTrackSpec> tracks) {
    return playerDataSource.appendPlaylistSources(tracks);
  }

  @override
  Future<void> seekToNext() => playerDataSource.seekToNext();

  @override
  Future<void> seekToPrevious() => playerDataSource.seekToPrevious();

  @override
  Stream<int?> currentIndexStream() => playerDataSource.currentIndexStream;

  @override
  int? currentIndex() => playerDataSource.currentIndex;

  @override
  Future<void> play() {
    return playerDataSource.play();
  }

  @override
  Future<void> pause() {
    return playerDataSource.pause();
  }

  @override
  Future<void> seek(Duration position) {
    return playerDataSource.seek(position);
  }

  @override
  Future<void> setSpeed(double speed) {
    return playerDataSource.setSpeed(speed);
  }

  @override
  Stream<Duration> getPositionStream() {
    return playerDataSource.positionStream;
  }

  @override
  Stream<Duration?> getDurationStream() {
    return playerDataSource.durationStream;
  }

  @override
  Stream<dynamic> getPlayerStateStream() {
    return playerDataSource.playerStateStream;
  }

  @override
  bool isPlaying() {
    return playerDataSource.isPlaying;
  }

  @override
  Duration getCurrentPosition() {
    return playerDataSource.position;
  }

  @override
  Duration? getDuration() {
    return playerDataSource.duration;
  }

  @override
  Future<void> saveLastPosition(
    String audioId,
    Duration position,
    Duration duration,
  ) {
    return progressDataSource.saveLastPosition(audioId, position, duration);
  }

  @override
  Future<Duration?> getLastPosition(String audioId) {
    return progressDataSource.getLastPosition(audioId);
  }

  @override
  Future<void> clearProgress(String audioId) {
    return progressDataSource.clearProgress(audioId);
  }

  @override
  void dispose() {
    playerDataSource.dispose();
  }
}
