import 'package:nebras_mobile_app/features/video_player/data/datasources/video_playback_progress_datasource.dart';
import 'package:nebras_mobile_app/features/video_player/data/datasources/video_player_datasource.dart';
import 'package:nebras_mobile_app/features/video_player/domain/repos/video_repos.dart';
import 'package:video_player/video_player.dart';

class VideoRepoImplem implements VideoRepos {
  final VideoPlayerDatasource playerDataSource;
  final VideoPlaybackProgressDatasource progressDataSource;

  VideoRepoImplem(this.playerDataSource, this.progressDataSource);

  @override
  Future<void> initializeVideo(String source) {
    return playerDataSource.setSource(source);
  }

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
  Stream<bool> getPlayingStateStream() {
    return playerDataSource.playingStateStream;
  }

  @override
  Stream<List<DurationRange>> getBufferedStream() {
    return playerDataSource.bufferedStream;
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
  double getAspectRatio() {
    return playerDataSource.aspectRatio;
  }

  @override
  bool isInitialized() {
    return playerDataSource.isInitialized;
  }

  @override
  VideoPlayerController? getController() {
    return playerDataSource.controller;
  }

  @override
  Future<void> saveLastPosition(
    String videoId,
    Duration position,
    Duration duration,
  ) {
    return progressDataSource.saveLastPosition(videoId, position, duration);
  }

  @override
  Future<Duration?> getLastPosition(String videoId) {
    return progressDataSource.getLastPosition(videoId);
  }

  @override
  Future<void> clearProgress(String videoId) {
    return progressDataSource.clearProgress(videoId);
  }

  @override
  Future<void> dispose() {
    return playerDataSource.dispose();
  }
}
