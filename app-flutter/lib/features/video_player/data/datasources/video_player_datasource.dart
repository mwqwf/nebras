import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

/// استثناء مُخصَّص يُرفع عندما يرفض الخادم البعيد تسليم الملف
/// (HTTP 401/403 — أو 404 على ملف مقيَّد). يحمل مفتاح ترجمة ثابتًا
/// [translationKey] ليستهلكه `VideoPlayerProvider` ويترجمه إلى رسالة
/// عربيّة/إنجليزيّة واضحة عبر `easy_localization` (بدل إظهار
/// `DioException` الخام للمستخدم). وهو عامّ لأيّ خادم يردّ
/// بنفس الرموز.
class MediaAccessDeniedException implements Exception {
  /// مفتاح الترجمة داخل `ar/en/fr.json` (`.tr()` في طبقة العرض).
  final String translationKey;

  /// رمز HTTP الذي أرجعه الخادم (401/403/404)، مفيد للوج فقط.
  final int statusCode;

  /// الـ URL الذي فشل — لا يُعرض للمستخدم، فقط للوج التشخيصيّ.
  final String? url;

  const MediaAccessDeniedException({
    required this.translationKey,
    required this.statusCode,
    this.url,
  });

  @override
  String toString() =>
      'MediaAccessDeniedException(status=$statusCode, key=$translationKey)';
}

/// Video Player Data Source
/// Wraps video_player plugin
/// Pure playback layer (no UI, no provider)
class VideoPlayerDatasource {
  VideoPlayerController? _controller;

  final StreamController<Duration> _positionController =
      StreamController.broadcast();
  final StreamController<Duration?> _durationController =
      StreamController.broadcast();
  final StreamController<bool> _playingController =
      StreamController.broadcast();
  final StreamController<List<DurationRange>> _bufferedController =
      StreamController.broadcast();

  VoidCallback? _listener;

  // ───────────── YouTube Detection ─────────────
  /// Static utility — detects YouTube URLs before any initialization
  static bool isYouTubeUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('youtube.com') ||
        lower.contains('youtu.be') ||
        lower.contains('youtube');
  }

  // ───────────── Getters ─────────────
  bool get isPlaying => _controller?.value.isPlaying ?? false;
  Duration get position => _controller?.value.position ?? Duration.zero;
  Duration? get duration => _controller?.value.duration;
  double get aspectRatio => _controller?.value.aspectRatio ?? 16 / 9;
  bool get isInitialized => _controller?.value.isInitialized ?? false;
  VideoPlayerController? get controller => _controller;

  // ───────────── Streams ─────────────
  Stream<Duration> get positionStream => _positionController.stream;
  Stream<Duration?> get durationStream => _durationController.stream;
  Stream<bool> get playingStateStream => _playingController.stream;
  Stream<List<DurationRange>> get bufferedStream => _bufferedController.stream;

  // ───────────── Initialize ─────────────
  Future<void> setSource(String source) async {
    debugPrint('[VideoPlayerDatasource] setSource: $source');

    await _disposeController();

    final normalized = _normalizeSource(source);

    if (isYouTubeUrl(normalized)) {
      throw UnsupportedError(
        'YouTube URLs are not supported by the native video player. '
        'URL: $normalized',
      );
    }

    if (_isRemoteSource(normalized)) {
      try {
        await _initializeRemote(normalized);
      } catch (streamError) {
        debugPrint(
          '[VideoPlayerDatasource] Streaming failed, falling back to download. Error: $streamError',
        );
        await _disposeController();

        // ── التحقّق المبكّر من رموز الرفض (401/403) ──────────────
        // العناصر المقيَّدة وصولًا
        // يردّ عليها الخادم بـ 401/403 عند Streaming وعند Download معًا،
        // فلا جدوى من محاولة التنزيل؛ نُسرّع برفع استثناء مترجَم واضح
        // بدل إظهار رسالة Dio الخام.
        final earlyAccess = _accessDeniedFromPlayerError(streamError, normalized);
        if (earlyAccess != null) throw earlyAccess;

        try {
          final localPath = await _downloadRemoteToTemp(normalized);
          debugPrint(
            '[VideoPlayerDatasource] Fallback local path: $localPath',
          );
          await _initializeLocal(localPath);
        } catch (fallbackError) {
          debugPrint(
            '[VideoPlayerDatasource] Fallback also failed: $fallbackError',
          );
          final lateAccess = _accessDeniedFromDioError(fallbackError, normalized);
          if (lateAccess != null) throw lateAccess;
          rethrow;
        }
      }
    } else {
      await _initializeLocal(normalized);
    }
  }

  /// يستخرج رمز HTTP من رسالة [PlatformException] التي يُطلقها
  /// `video_player/ExoPlayer` عند فشل المصدر. ExoPlayer لا يعرض الرمز
  /// هيكليًّا، لكنّه يُدرجه ضمن نصّ الرسالة (مثل `Response code: 401`).
  MediaAccessDeniedException? _accessDeniedFromPlayerError(
    Object error,
    String url,
  ) {
    final text = error is PlatformException
        ? (error.message ?? '').toLowerCase()
        : error.toString().toLowerCase();
    // نبحث عن بصمة ExoPlayer الثابتة أو الأرقام الصريحة.
    for (final code in const [401, 403]) {
      if (text.contains('response code: $code') || text.contains(' $code ')) {
        return MediaAccessDeniedException(
          translationKey: 'media_access_denied',
          statusCode: code,
          url: url,
        );
      }
    }
    return null;
  }

  /// يستخرج رمز HTTP من [DioException] لمسار التنزيل الاحتياطيّ.
  MediaAccessDeniedException? _accessDeniedFromDioError(
    Object error,
    String url,
  ) {
    if (error is! DioException) return null;
    final status = error.response?.statusCode ?? 0;
    if (status == 401 || status == 403) {
      return MediaAccessDeniedException(
        translationKey: 'media_access_denied',
        statusCode: status,
        url: url,
      );
    }
    if (status == 404) {
      return MediaAccessDeniedException(
        translationKey: 'media_not_found',
        statusCode: status,
        url: url,
      );
    }
    return null;
  }

  /// يبني headers HTTP مناسبة بحسب المضيف.
  static Map<String, String> _headersFor(String url) {
    return const {
      'Accept': '*/*',
      'User-Agent': 'NebrasMobileApp/1.0 (VideoPlayer)',
    };
  }

  Future<void> _initializeRemote(String url) async {
    final uri = Uri.parse(url);
    _controller = VideoPlayerController.networkUrl(
      uri,
      videoPlayerOptions: VideoPlayerOptions(allowBackgroundPlayback: false),
      httpHeaders: _headersFor(url),
    );

    await _controller!
        .initialize()
        .timeout(const Duration(seconds: 60));

    debugPrint(
      "[VideoPlayerDatasource] Initialized: duration=${_controller!.value.duration} buffered=${_controller!.value.buffered}",
    );
    _setupListeners();
  }

  Future<void> _initializeLocal(String path) async {
    final file = File(path);
    final exists = await file.exists();
    final size = exists ? await file.length() : 0;
    debugPrint('[VideoPlayerDatasource] Local file size: $size, exists: $exists');
    if (!exists || size <= 0) {
      throw FileSystemException('Video file is missing or empty', path);
    }
    _controller = VideoPlayerController.file(file);
    await _controller!.initialize();
    _setupListeners();
  }

  String _normalizeSource(String source) {
    var trimmed = source.trim();
    if (trimmed.startsWith('//')) {
      trimmed = 'https:$trimmed';
    }
    return trimmed;
  }

  bool _isRemoteSource(String source) {
    final uri = Uri.tryParse(source);
    if (uri == null) return false;
    return uri.scheme == 'http' || uri.scheme == 'https';
  }

  /// Last-resort fallback: download the video to a temporary file and play it
  /// from local storage. Useful when streaming fails (network instability,
  /// codec quirks, large moov atom at EOF, etc.) — mirrors the strategy used
  /// in [AudioPlayerDatasource].
  Future<String> _downloadRemoteToTemp(String url) async {
    final dir = await getTemporaryDirectory();
    final extension = _guessVideoExtension(url);
    final filePath =
        '${dir.path}${Platform.pathSeparator}video_${DateTime.now().millisecondsSinceEpoch}$extension';

    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(minutes: 10),
        sendTimeout: const Duration(seconds: 30),
        followRedirects: true,
        maxRedirects: 10,
        headers: _headersFor(url),
      ),
    );

    await dio.download(
      url,
      filePath,
      onReceiveProgress: (received, total) {
        if (total > 0) {
          final pct = ((received / total) * 100).toStringAsFixed(1);
          debugPrint('[VideoPlayerDatasource] Downloading video: $pct%');
        }
      },
    );

    return filePath;
  }

  String _guessVideoExtension(String source) {
    final lower = source.toLowerCase();
    if (lower.contains('.mp4') || lower.contains('_mp4')) return '.mp4';
    if (lower.contains('.mkv') || lower.contains('_mkv')) return '.mkv';
    if (lower.contains('.mov') || lower.contains('_mov')) return '.mov';
    if (lower.contains('.webm') || lower.contains('_webm')) return '.webm';
    if (lower.contains('.m4v') || lower.contains('_m4v')) return '.m4v';
    if (lower.contains('.avi') || lower.contains('_avi')) return '.avi';
    if (lower.contains('.3gp') || lower.contains('_3gp')) return '.3gp';
    return '.mp4';
  }

  /// Dispose only the controller, not the streams
  Future<void> _disposeController() async {
    if (_listener != null && _controller != null) {
      _controller!.removeListener(_listener!);
      _listener = null;
    }
    await _controller?.dispose();
    _controller = null;
  }

  void _setupListeners() {
    _listener = () {
      if (_controller == null) return;

      final value = _controller!.value;
      if (value.hasError) {
        debugPrint("[VideoPlayerDatasource] ERROR: ${value.errorDescription}");
        return;
      }

      if (value.isBuffering) {
        debugPrint("[VideoPlayerDatasource] BUFFERING...");
      }

      _positionController.add(value.position);
      _durationController.add(value.duration);
      _playingController.add(value.isPlaying);
      _bufferedController.add(value.buffered);
    };

    _controller!.addListener(_listener!);
  }

  // ───────────── Controls ─────────────
  Future<void> play() async => await _controller?.play();

  Future<void> pause() async => await _controller?.pause();

  Future<void> seek(Duration position) async =>
      await _controller?.seekTo(position);

  Future<void> setSpeed(double speed) async =>
      await _controller?.setPlaybackSpeed(speed);

  // ───────────── Dispose ─────────────
  Future<void> dispose() async {
    if (_controller != null && _listener != null) {
      _controller!.removeListener(_listener!);
    }

    await _controller?.dispose();
    _controller = null;
  }
}
