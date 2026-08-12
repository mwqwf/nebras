import 'package:shared_preferences/shared_preferences.dart';

/// Video Playback Progress Data Source
/// Handles persistence of video playback position using SharedPreferences
/// NO UI logic, NO Provider, NO Flutter widgets
class VideoPlaybackProgressDatasource {
  static const String _keyPrefix = 'video_position_';
  static const String _durationPrefix = 'video_duration_';

  // ─── Save Last Position ──────────────────
  Future<void> saveLastPosition(
    String videoId,
    Duration position,
    Duration duration,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_keyPrefix$videoId', position.inMilliseconds);
    await prefs.setInt('$_durationPrefix$videoId', duration.inMilliseconds);
  }

  // ─── Get Last Position ───────────────────
  Future<Duration?> getLastPosition(String videoId) async {
    final prefs = await SharedPreferences.getInstance();
    final milliseconds = prefs.getInt('$_keyPrefix$videoId');
    
    if (milliseconds == null) return null;
    return Duration(milliseconds: milliseconds);
  }

  // ─── Clear Progress ──────────────────────
  Future<void> clearProgress(String videoId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_keyPrefix$videoId');
    await prefs.remove('$_durationPrefix$videoId');
  }
}
