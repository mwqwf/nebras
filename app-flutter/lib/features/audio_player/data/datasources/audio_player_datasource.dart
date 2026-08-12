import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path_provider/path_provider.dart';

/// مواصفات مقطع واحد يُمرَّر لـ [AudioPlayerDatasource.setPlaylistSource].
/// طبقة البيانات لا تعرف `Content` (طبقة features)، لذا نُعرّف هنا
/// بنية خفيفة تحمل الحقول التي تحتاجها `MediaItem` والـ AudioSource.
class PlaylistTrackSpec {
  final String mediaId;
  final String source;
  final String title;
  final String? album;
  final String? artist;
  final String? artworkUrl;

  const PlaylistTrackSpec({
    required this.mediaId,
    required this.source,
    required this.title,
    this.album,
    this.artist,
    this.artworkUrl,
  });
}

/// Audio Player Data Source
/// يغلِّف [AudioPlayer] من `just_audio` ويُهيِّئ كلّ مصدر كـ
/// [AudioSource] يحمل [MediaItem] (العنوان/المؤلّف/الصورة)، وهو ما يسمح
/// لـ `just_audio_background` بعرض الإشعار الدائم وأزرار التحكّم على
/// شاشة القفل ولوحة الإشعارات وعلى نحو رسميّ تماماً كما في تطبيقات
/// الموسيقى الكبرى. يُدير أيضاً التنزيل الاحتياطيّ عند فشل البثّ.
class AudioPlayerDatasource {
  /// مشغّل واحد يُستخدم طوال عمر التطبيق (مسجَّل Singleton في
  /// `setup_locator.dart`). استبدال المصدر عبر [setSource] يُغلق
  /// المصدر السابق فوراً، وبذلك يتحقّق شرط المستخدم: "إذا تم تشغيل
  /// مقطع جديد، يجب أن يُغلق المقطع السابق فوراً".
  final AudioPlayer _player = AudioPlayer(
    // السماح بإدارة التركيز تلقائيّاً: نوقِف التشغيل عند المكالمات
    // والتنبيهات الطويلة، ونستأنفه عند عودة التركيز إلينا. هذا يُكمِّل
    // ما يفعله `audio_session` ويغطّي الحالات التي لا تُسلَّم فيها
    // الأحداث إلى مستهلك خارجيّ.
    handleInterruptions: true,
    handleAudioSessionActivation: true,
    androidApplyAudioAttributes: true,
  );

  /// تعيين المصدر مع بياناته الوصفيّة ليُعرض في الإشعار وشاشة القفل.
  /// - [source]      : رابط/مسار الملف الصوتيّ (مُطلق).
  /// - [mediaId]     : مُعرِّف فريد (id من المحتوى). مطلوب للـ MediaItem.
  /// - [title]       : اسم المقطع (يظهر في الإشعار).
  /// - [album]       : القسم أو التصنيف (اختياريّ).
  /// - [artist]      : اسم المؤلّف/المدرِّس (اختياريّ).
  /// - [artworkUrl]  : صورة مصغّرة (اختياريّة) — ستظهر في MediaSession.
  Future<void> setSource(
    String source, {
    required String mediaId,
    required String title,
    String? album,
    String? artist,
    String? artworkUrl,
  }) async {
    final normalizedSource = _normalizeSource(source);
    if (normalizedSource.isEmpty) {
      throw ArgumentError('Audio source cannot be empty');
    }

    final mediaItem = MediaItem(
      id: mediaId,
      title: title,
      album: album,
      artist: artist,
      artUri: (artworkUrl != null && artworkUrl.trim().isNotEmpty)
          ? Uri.tryParse(artworkUrl.trim())
          : null,
    );

    if (_isRemoteSource(normalizedSource)) {
      try {
        // بدون headers: ExoPlayer يتواصل مباشرة مع HTTPS، لا proxy محلّيّ.
        // ملاحظة: تمرير headers يُفعّل proxy محلّيّ (cleartext 127.0.0.1)
        // وهو مسموح في network_security_config لكنّه لا لزوم له هنا.
        await _player.setAudioSource(
          AudioSource.uri(Uri.parse(normalizedSource), tag: mediaItem),
        );
      } catch (e) {
        debugPrint('[AudioPlayerDatasource] Streaming failed: $e');
        // المحاولة الثانية: تنزيل مؤقّت. مفيد للمحتوى الذي
        // قد يحتاج متابعة تحويلات متعدّدة أو يُقدَّم بـ MIME غير معتادة.
        final fallbackPath = await _downloadNetworkAudioToTemp(
          normalizedSource,
        );
        debugPrint('Audio fallback to local temp file: $fallbackPath');
        await _player.setAudioSource(
          AudioSource.file(fallbackPath, tag: mediaItem),
        );
      }
    } else {
      await _player.setAudioSource(
        AudioSource.file(normalizedSource, tag: mediaItem),
      );
    }
  }

  // ─── Playlist Source (ConcatenatingAudioSource) ─────────────────────
  // ⚠ هذا هو الشرط الذي يُفعّل أزرار (Next/Prev) في إشعار النظام
  // ولوحة شاشة القفل. `just_audio_background` يعرض هذه الأزرار فقط
  // عندما يرى قائمة تشغيل تحوي أكثر من عنصر (currentIndexStream قابل
  // للتقدّم/الرجوع). لذا نُمرّر القائمة كاملة دفعة واحدة للمشغّل
  // عبر setAudioSource(ConcatenatingAudioSource(...)).
  //
  // كلّ طفل يحمل MediaItem المخصّص به (عنوان، ألبوم، مؤلّف، صورة)
  // فيتغيّر ما يظهر في شاشة القفل تلقائيًّا عند كلّ تقدّم — بدون
  // الحاجة لإعادة setAudioSource في كلّ مقطع (التقنية السابقة كانت
  // تُعيد التهيئة لكلّ مقطع، فيضيع تسلسل القائمة من MediaSession).

  /// مُواصفات مقطع واحد داخل قائمة التشغيل. نُعرِّفها كـ record-like
  /// class حتى لا نُدخل `Content` (طبقة features) إلى طبقة البيانات.
  ///
  /// يمرَّر هذا النوع من `AudioRepoImplem` الذي يقوم بـ mapping من
  /// `Content` إلى [_AudioTrackSource] عبر المساعد [buildTrackSource].
  /// ⚠ هامّ: لا نُمرِّر `headers` هنا. just_audio على Android يُشغّل
  /// proxy محلّيّ على `http://127.0.0.1:PORT/...` فقط حين تُمرَّر
  /// headers، وهذا الـ proxy يعمل بـ cleartext فيرفضه النظام افتراضيًّا
  /// منذ Android 9 (API 28+) برسالة:
  ///   `Cleartext HTTP traffic to 127.0.0.1 not permitted`.
  /// تمرير Uri مجرَّد يجعل ExoPlayer يتواصل مع الخادم HTTPS مباشرة
  /// دون proxy → لا مشكلة Cleartext، والتشغيل يعمل على Android 10/11/12+.
  static List<AudioSource> buildAudioSources(
    List<PlaylistTrackSpec> specs,
  ) {
    return specs.map((spec) {
      final source = _normalizeSourceStatic(spec.source);
      final mediaItem = MediaItem(
        id: spec.mediaId,
        title: spec.title,
        album: spec.album,
        artist: spec.artist,
        artUri: (spec.artworkUrl != null && spec.artworkUrl!.trim().isNotEmpty)
            ? Uri.tryParse(spec.artworkUrl!.trim())
            : null,
      );
      if (_isRemoteSourceStatic(source)) {
        return AudioSource.uri(Uri.parse(source), tag: mediaItem);
      }
      return AudioSource.file(source, tag: mediaItem);
    }).toList(growable: true);
  }

  /// تهيئة المشغّل على قائمة تشغيل كاملة — هذه الدالّة هي النقطة
  /// الوحيدة التي تُفعّل إشعار قائمة التشغيل مع أزرار Next/Prev في
  /// لوحة الإشعارات وشاشة القفل. استدعاؤها يُغلق أيّ AudioSource
  /// سابق تلقائيًّا (سلوك just_audio الرسميّ).
  Future<void> setPlaylistSource({
    required List<PlaylistTrackSpec> tracks,
    required int initialIndex,
    Duration? initialPosition,
  }) async {
    if (tracks.isEmpty) {
      throw ArgumentError('Playlist cannot be empty');
    }
    final clampedIndex = initialIndex.clamp(0, tracks.length - 1);
    final sources = buildAudioSources(tracks);
    // واجهة قائمة التشغيل الجديدة في just_audio 0.10 (`setAudioSources`)
    // تحلّ محلّ `ConcatenatingAudioSource` المهجورة. تمرير القائمة مباشرةً
    // في كلّ استدعاء يضمن أنّ الأطفال المعروضين في MediaSession هُم فعلاً
    // أطفال القائمة الجديدة (وليسوا بقايا القائمة السابقة).
    try {
      await _player.setAudioSources(
        sources,
        initialIndex: clampedIndex,
        initialPosition: initialPosition ?? Duration.zero,
      );
    } catch (e) {
      // Fallback استراتيجيّ: إن فشل المشغّل في فتح المصدر المباشر
      // (شبكة/Cleartext/MIME غير متعرَّف عليه)، نُنزِّل **المقطع الحاليّ
      // فقط** محلّيًّا ونُعيد تهيئة القائمة بحيث يكون المقطع المفعَّل
      // ملفًّا محلّيًّا، والباقي روابط عاديّة (كما كان). هكذا نتفادى
      // انتظار تنزيل القائمة كاملة، ونضمن بدءًا فوريًّا ولائقًا.
      debugPrint('[AudioPlayerDatasource] setPlaylistSource failed: $e');
      final active = tracks[clampedIndex];
      final normalized = _normalizeSourceStatic(active.source);
      if (!_isRemoteSourceStatic(normalized)) rethrow;
      final localPath = await _downloadNetworkAudioToTemp(normalized);
      final patched = List<PlaylistTrackSpec>.from(tracks);
      patched[clampedIndex] = PlaylistTrackSpec(
        mediaId: active.mediaId,
        source: localPath,
        title: active.title,
        album: active.album,
        artist: active.artist,
        artworkUrl: active.artworkUrl,
      );
      final fallbackSources = buildAudioSources(patched);
      await _player.setAudioSources(
        fallbackSources,
        initialIndex: clampedIndex,
        initialPosition: initialPosition ?? Duration.zero,
      );
    }
  }

  /// إضافة عناصر جديدة إلى نهاية القائمة الحاليّة دون مقاطعة التشغيل
  /// الجاري. يُستخدم في Smart Auto-Play: عندما يصل المستمع لآخر
  /// عنصر في "لك / البحث"، يُستدعى هذا لتمديد القائمة ديناميكيًّا.
  Future<void> appendPlaylistSources(List<PlaylistTrackSpec> tracks) async {
    if (tracks.isEmpty) return;
    // لا توجد قائمة تشغيل فعّالة — لا شيء نُمدّده (مسار احتياطيّ نادر).
    if (_player.audioSource == null) return;
    // واجهة الإضافة الجديدة في just_audio 0.10 تحلّ محلّ
    // `ConcatenatingAudioSource.addAll` المهجورة، وتُمدّد القائمة الحيّة
    // دون مقاطعة التشغيل الجاري.
    await _player.addAudioSources(buildAudioSources(tracks));
  }

  // ─── Native Next/Previous (يعمل على مستوى المشغّل والنظام معًا) ─────
  /// يُفضَّل استخدامهما بدلًا من إعادة `setSource` لكلّ مقطع؛ فكلاهما
  /// يُبقي قائمة التشغيل حيّة في MediaSession فتظهر الأزرار دائمًا.
  bool get hasNext => _player.hasNext;
  bool get hasPrevious => _player.hasPrevious;
  Future<void> seekToNext() async {
    if (_player.hasNext) await _player.seekToNext();
  }

  Future<void> seekToPrevious() async {
    if (_player.hasPrevious) await _player.seekToPrevious();
  }

  Future<void> seekToIndex(int index, {Duration position = Duration.zero}) =>
      _player.seek(position, index: index);

  /// يبثّ الفهرس الحاليّ في القائمة — ضروريّ ليكتشف الـ Provider
  /// انتقال المستخدم من زرّ Next/Prev داخل إشعار النظام (أي خارج
  /// واجهتنا) ويُحدِّث حالته تبعًا لذلك.
  Stream<int?> get currentIndexStream => _player.currentIndexStream;
  int? get currentIndex => _player.currentIndex;

  /// فحص static للمساعد [buildAudioSources]. نُعيد استعمال منطق
  /// [_normalizeSource]/[_isRemoteSource] دون تكرار.
  static String _normalizeSourceStatic(String source) {
    final trimmed = source.trim();
    if (trimmed.startsWith('//')) return 'https:$trimmed';
    return trimmed;
  }

  static bool _isRemoteSourceStatic(String source) {
    final uri = Uri.tryParse(source);
    if (uri == null) return false;
    return uri.scheme == 'http' || uri.scheme == 'https';
  }

  static Map<String, String> _headersForUrl(String url) {
    return const {
      'Accept': '*/*',
      'User-Agent': 'NebrasMobileApp/1.0 (AudioPlayer)',
    };
  }

  Future<String> _downloadNetworkAudioToTemp(String source) async {
    final dir = await getTemporaryDirectory();
    final extension = _guessAudioExtension(source);
    final filePath =
        '${dir.path}${Platform.pathSeparator}audio_${DateTime.now().millisecondsSinceEpoch}$extension';

    await Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(minutes: 10),
        sendTimeout: const Duration(seconds: 30),
        followRedirects: true,
        maxRedirects: 10,
        headers: _headersForUrl(source),
      ),
    ).download(source, filePath);
    return filePath;
  }

  String _guessAudioExtension(String source) {
    final lower = source.toLowerCase();
    if (lower.contains('.mp3') || lower.contains('_mp3')) return '.mp3';
    if (lower.contains('.m4a') || lower.contains('_m4a')) return '.m4a';
    if (lower.contains('.aac') || lower.contains('_aac')) return '.aac';
    if (lower.contains('.wav') || lower.contains('_wav')) return '.wav';
    if (lower.contains('.ogg') || lower.contains('_ogg')) return '.ogg';
    if (lower.contains('.mp4') || lower.contains('_mp4')) return '.mp4';
    if (lower.contains('.webm') || lower.contains('_webm')) return '.webm';
    if (lower.contains('.m3u8') || lower.contains('_m3u8')) return '.m3u8';
    return '.mp3';
  }

  String _normalizeSource(String source) {
    final trimmed = source.trim();
    if (trimmed.startsWith('//')) {
      return 'https:$trimmed';
    }
    return trimmed;
  }

  bool _isRemoteSource(String source) {
    final uri = Uri.tryParse(source);
    if (uri == null) return false;
    return uri.scheme == 'http' || uri.scheme == 'https';
  }

  // ─── Controls ───────────────────────────────────────────────────────
  Future<void> play() => _player.play();
  Future<void> pause() => _player.pause();
  Future<void> seek(Duration position) => _player.seek(position);
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);
  Future<void> stop() => _player.stop();

  // ─── Streams & State ────────────────────────────────────────────────
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  bool get isPlaying => _player.playing;
  Duration get position => _player.position;
  Duration? get duration => _player.duration;

  void dispose() {
    _player.dispose();
  }
}
