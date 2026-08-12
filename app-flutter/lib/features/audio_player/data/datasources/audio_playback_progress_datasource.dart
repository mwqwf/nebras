import 'package:shared_preferences/shared_preferences.dart';

/// Handles persistence of audio playback progress across app restarts
/// Separate from download progress to maintain single responsibility
class AudioPlaybackProgressDatasource {
  static const String _positionPrefix = 'audio_position_';
  static const String _durationPrefix = 'audio_duration_';

  final SharedPreferences prefs;
  AudioPlaybackProgressDatasource(this.prefs);

  /// Save current playback position for a specific audio
  Future<void> saveLastPosition(
    String audioId,
    Duration position,
    Duration duration,
  ) async {
    await prefs.setInt(
      '$_positionPrefix$audioId',
      position.inMilliseconds,
    );
    await prefs.setInt(
      '$_durationPrefix$audioId',
      duration.inMilliseconds,
    );
  }

  /// Get last saved playback position
  Future<Duration?> getLastPosition(String audioId) async {
    final milliseconds = prefs.getInt('$_positionPrefix$audioId');
    if (milliseconds != null) {
      return Duration(milliseconds: milliseconds);
    }
    return null;
  }

  /// Get saved duration (for validation)
  Future<Duration?> getSavedDuration(String audioId) async {
    final milliseconds = prefs.getInt('$_durationPrefix$audioId');
    if (milliseconds != null) {
      return Duration(milliseconds: milliseconds);
    }
    return null;
  }

  /// Clear playback progress (e.g., when audio is deleted)
  Future<void> clearProgress(String audioId) async {
    await prefs.remove('$_positionPrefix$audioId');
    await prefs.remove('$_durationPrefix$audioId');
  }

  /// Check if there's saved playback progress
  Future<bool> hasProgress(String audioId) async {
    return prefs.containsKey('$_positionPrefix$audioId');
  }
}
