import 'package:video_player/video_player.dart';

/// Video Repository Contract
/// Defines operations for video playback and progress persistence
abstract class VideoRepos {
  /// Initialize video player with source
  Future<void> initializeVideo(String source);

  /// Play video
  Future<void> play();

  /// Pause video
  Future<void> pause();

  /// Seek to position
  Future<void> seek(Duration position);

  /// Set playback speed
  Future<void> setSpeed(double speed);

  /// Get position stream
  Stream<Duration> getPositionStream();

  /// Get duration stream
  Stream<Duration?> getDurationStream();

  /// Get playing state stream
  Stream<bool> getPlayingStateStream();

  /// Get buffered ranges stream
  Stream<List<DurationRange>> getBufferedStream();

  /// Check if playing
  bool isPlaying();

  /// Get current position
  Duration getCurrentPosition();

  /// Get duration
  Duration? getDuration();

  /// Get aspect ratio
  double getAspectRatio();

  /// Check if initialized
  bool isInitialized();

  /// Get the underlying VideoPlayerController for rendering
  VideoPlayerController? getController();

  /// Save last playback position
  Future<void> saveLastPosition(
    String videoId,
    Duration position,
    Duration duration,
  );

  /// Get last playback position
  Future<Duration?> getLastPosition(String videoId);

  /// Clear playback progress
  Future<void> clearProgress(String videoId);

  /// Dispose resources
  Future<void> dispose();
}
