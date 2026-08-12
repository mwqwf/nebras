import 'package:nebras_mobile_app/features/audio_player/data/datasources/audio_player_datasource.dart'
    show PlaylistTrackSpec;

/// Audio Repository Contract
/// Defines operations for audio playback and progress persistence
abstract class AudioRepos {
  /// تهيئة المشغّل على مصدر جديد مع بياناته الوصفيّة.
  /// - [source]    : رابط/مسار الملف الصوتيّ.
  /// - [mediaId]   : مُعرِّف فريد ضروريّ لـ MediaSession/NowPlayingInfo.
  /// - [title]     : العنوان الذي يظهر في الإشعار وشاشة القفل.
  /// - [album]     : القسم (اختياريّ).
  /// - [artist]    : اسم المؤلّف/القارئ (اختياريّ).
  /// - [artworkUrl]: صورة مصغّرة تُعرض في لوحة التحكّم (اختياريّة).
  Future<void> initializeAudio(
    String source, {
    required String mediaId,
    required String title,
    String? album,
    String? artist,
    String? artworkUrl,
  });

  /// تهيئة المشغّل على قائمة تشغيل كاملة (ConcatenatingAudioSource).
  /// هذا ما يُفعّل أزرار Next/Prev في الإشعار وشاشة القفل لأنّ النظام
  /// يرى قائمة حقيقيّة وليس مقطعًا واحدًا مُستبدلًا في كلّ مرّة.
  Future<void> initializePlaylist({
    required List<PlaylistTrackSpec> tracks,
    required int initialIndex,
    Duration? initialPosition,
  });

  /// إضافة عناصر إلى نهاية القائمة الحاليّة بدون مقاطعة التشغيل.
  /// تُستخدم في Smart Auto-Play عند نفاد القائمة في "لك" و"البحث".
  Future<void> appendTracks(List<PlaylistTrackSpec> tracks);

  /// Native Next/Previous — يعمل فورًا على مستوى المشغّل وعلى مستوى
  /// النظام (إشعار/شاشة القفل) لأنّنا نتنقّل داخل قائمة موجودة بالفعل.
  Future<void> seekToNext();
  Future<void> seekToPrevious();

  /// يبثّ الفهرس الحاليّ — نستهلكه للكشف عن ضغط المستخدم على
  /// Next/Prev من داخل إشعار النظام (خارج واجهتنا).
  Stream<int?> currentIndexStream();
  int? currentIndex();

  /// Play audio
  Future<void> play();

  /// Pause audio
  Future<void> pause();

  /// Seek to position
  Future<void> seek(Duration position);

  /// Set playback speed
  Future<void> setSpeed(double speed);

  /// Get position stream
  Stream<Duration> getPositionStream();

  /// Get duration stream
  Stream<Duration?> getDurationStream();

  /// Get player state stream
  Stream<dynamic> getPlayerStateStream();

  /// Check if playing
  bool isPlaying();

  /// Get current position
  Duration getCurrentPosition();

  /// Get duration
  Duration? getDuration();

  /// Save last playback position
  Future<void> saveLastPosition(
    String audioId,
    Duration position,
    Duration duration,
  );

  /// Get last playback position
  Future<Duration?> getLastPosition(String audioId);

  /// Clear playback progress
  Future<void> clearProgress(String audioId);

  /// Dispose resources
  void dispose();
}
