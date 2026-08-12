import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nebras_mobile_app/core/media/content_context.dart';
import 'package:nebras_mobile_app/core/services/content_engagement_service.dart';
import 'package:nebras_mobile_app/core/services/continue_watching_service.dart';
import 'package:nebras_mobile_app/features/content/model/content_model.dart';
import 'package:nebras_mobile_app/features/video_player/data/datasources/video_player_datasource.dart'
    show MediaAccessDeniedException, VideoPlayerDatasource;
import 'package:nebras_mobile_app/features/video_player/domain/repos/video_repos.dart';
import 'package:nebras_mobile_app/features/video_player/domain/usecases/get_last_position_usecase.dart';
import 'package:nebras_mobile_app/features/video_player/domain/usecases/initialize_video_usecase.dart';
import 'package:nebras_mobile_app/features/video_player/domain/usecases/save_last_position_usecase.dart';
import 'package:video_player/video_player.dart';

/// توقيع دالّة جلب محتوى مشابه للفيديو الحاليّ — تُعرَّف من الشاشة
/// (باستخدام RecommendationEngine + HomeProvider) ويستدعيها الـ
/// Provider عند انتهاء القائمة في سياق "For You" أو "Search".
typedef VideoSimilarContentFetcher =
    Future<List<Content>> Function({
      required Content reference,
      required int limit,
    });

/// Video Player Provider
/// Orchestrates video playback use cases and exposes state to UI
/// Does NOT contain business logic — only coordination
class VideoPlayerProvider extends ChangeNotifier {
  final VideoRepos repository;
  final InitializeVideoUsecase initializeVideoUsecase;
  final GetLastPositionUsecase getLastPositionUsecase;
  final SaveLastPositionUsecase saveLastPositionUsecase;

  VideoPlayerProvider(
    this.repository,
    this.initializeVideoUsecase,
    this.getLastPositionUsecase,
    this.saveLastPositionUsecase,
  );

  // ───────────── State ─────────────
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _speed = 1.0;
  String _qualityLabel = 'Auto';
  bool _isPlaying = false;
  bool _isLoading = true;
  bool _isFullscreen = false;
  bool _isScrubbing = false;
  bool _isInAppMiniPlayer = false;
  bool _showNextSuggestion = false;
  int _nextSuggestionSeconds = 0;
  String? _errorMessage;
  List<DurationRange> _buffered = [];

  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _playingSub;
  StreamSubscription? _bufferedSub;
  Timer? _nextSuggestionTimer;

  /// Listener مباشر على الـ VideoPlayerController لكشف نهاية الفيديو.
  /// هذا طبقة أمان ثانية فوق الـ Streams — حزمة `video_player` تُصدر
  /// تحديثات قيمة الـ controller في كلّ إطار، لذا نلتقط بلوغ النهاية
  /// حتى لو اختنق Stream الموضع بسبب throttling.
  VoidCallback? _controllerCompletionListener;

  // ─── Playlist (Next/Prev) ─────────────────────────────────────────
  // قائمة تشغيل اختياريّة تُمرَّر من الشاشة لتفعيل أزرار التالي/السابق.
  // حين تكون فارغة، يعمل المشغّل بنمط "مقطع واحد" كما كان تماماً.
  List<Content> _playlist = const [];
  int _currentIndex = 0;
  bool _isPiPActive = false;

  // ─── Smart Auto-Play Context ──────────────────────────────────────
  ContentContext _context = ContentContext.section;
  VideoSimilarContentFetcher? onSimilarContentNeeded;
  bool _fetchingSimilar = false;

  ContentContext get contentContext => _context;
  void setContentContext(ContentContext context) {
    _context = context;
  }

  /// Optional callback — UI sets this to handle post-playback logic once
  /// there is no "next" track in the playlist. إن وُجد عنصر تالٍ فإنّ
  /// المشغّل ينتقل إليه تلقائيّاً قبل استدعاء هذا الـ callback.
  VoidCallback? onVideoCompleted;

  /// Optional callback — يُستدعى حين يرغب المستخدم بتفعيل الوضع المصغّر
  /// (PiP) يدويًّا (زرّ التصغير في شريط التحكّم) أو تلقائيّاً (زرّ الرجوع).
  /// تُحدَّده الشاشة `_VideoPlayerView` لأنّها الجهة الوحيدة التي تملك
  /// instance من `Floating()` وتعرف أبعاد الشاشة الحاليّة. لا يجوز أن
  /// يعتمد الـ Provider على أيّ حزمة منصّة مباشرة.
  Future<void> Function()? onPipRequested;

  // ───────────── Getters ─────────────
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get duration => _duration;
  double get speed => _speed;
  double get playBackSpeed => _speed;
  String get qualityLabel => _qualityLabel;
  bool get isLoading => _isLoading;
  bool get isFullscreen => _isFullscreen;
  bool get isInAppMiniPlayer => _isInAppMiniPlayer;
  bool get showNextSuggestion => _showNextSuggestion;
  int get nextSuggestionSeconds => _nextSuggestionSeconds;
  bool get isScrubbing => _isScrubbing;
  String? get errorMessage => _errorMessage;
  List<DurationRange> get buffered => _buffered;
  VideoPlayerController? get controller => repository.getController();

  // ─── Playlist Getters ────────────────────────────────────────────
  List<Content> get playlist => List.unmodifiable(_playlist);
  int get currentIndex => _currentIndex;
  Content? get currentVideo =>
      _playlist.isEmpty ? null : _playlist[_currentIndex];
  bool get hasNext => _currentIndex < _playlist.length - 1;
  bool get hasPrevious => _currentIndex > 0;
  Content? get nextSuggestion => hasNext ? _playlist[_currentIndex + 1] : null;

  // ─── PiP State ───────────────────────────────────────────────────
  bool get isPiPActive => _isPiPActive;
  // ignore: use_setters_to_change_properties
  void setPiPActive(bool value) {
    if (_isPiPActive == value) return;
    _isPiPActive = value;
    notifyListeners();
  }

  // ───────────── Initialize ─────────────
  Future<void> initializeVideo(String videoId, String source) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await initializeVideoUsecase(source);

      _listenToStreams(videoId);

      final lastPosition = await getLastPositionUsecase(videoId);
      if (lastPosition != null && lastPosition.inMilliseconds > 0) {
        await repository.seek(lastPosition);
      }

      await repository.play(); // ← moved here

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      // نُحوِّل استثناء المنع (401/403/404 من الخادم البعيد) إلى رسالة
      // مترجمة مفهومة بدل سلسلة Dio الخام. الاستثناءات الأخرى تُعرض كما هي.
      if (e is MediaAccessDeniedException) {
        _errorMessage = e.translationKey.tr();
      } else {
        _errorMessage = e.toString();
      }
      notifyListeners();
    }
  }

  void _listenToStreams(String videoId) {
    // Cancel any previous subscriptions
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playingSub?.cancel();
    _bufferedSub?.cancel();

    // ── شبكة أمان مباشرة على VideoPlayerController ─────────────────
    // نُزيل أيّ listener سابق (لو أُعيدت التهيئة لمقطع جديد)، ثمّ
    // نربط listener يراقب نهاية الفيديو عبر قيمة الـ controller.
    // هذا يضمن تشغيل التالي حتى لو تأخّر Stream الموضع.
    final currentController = repository.getController();
    if (_controllerCompletionListener != null) {
      try {
        currentController?.removeListener(_controllerCompletionListener!);
      } catch (_) {}
    }
    _controllerCompletionListener = () {
      final ctrl = repository.getController();
      if (ctrl == null) return;
      final value = ctrl.value;
      if (!value.isInitialized) return;
      final total = value.duration;
      final pos = value.position;
      if (total <= Duration.zero) return;
      // نعتمد hasEnded عند بلوغ النهاية (±200ms هامش لأخطاء التقطيع).
      final reachedEnd = pos >= total - const Duration(milliseconds: 200);
      if (reachedEnd && !value.isPlaying) {
        _handleVideoCompleted();
      }
    };
    currentController?.addListener(_controllerCompletionListener!);

    DateTime lastUpdate = DateTime.now();
    _positionSub = repository.getPositionStream().listen((pos) {
      if (_isScrubbing) return; // Don't update position while user is scrubbing

      final now = DateTime.now();
      if (now.difference(lastUpdate).inMilliseconds < 300) return;
      lastUpdate = now;

      _position = pos;
      notifyListeners();

      // Check for video completion
      if (_duration > Duration.zero &&
          pos >= _duration - const Duration(milliseconds: 500)) {
        _handleVideoCompleted();
      }

      // Save progress periodically (every 5 seconds)
      if (pos.inSeconds > 0 && pos.inSeconds % 5 == 0) {
        saveProgress(videoId);
      }
    });

    _durationSub = repository.getDurationStream().listen((dur) {
      if (dur != null && dur > Duration.zero) {
        _duration = dur;
        notifyListeners();
      }
    });

    _playingSub = repository.getPlayingStateStream().listen((playing) {
      _isPlaying = playing;
      notifyListeners();

      // Detect playback completion
      if (!playing &&
          _duration > Duration.zero &&
          _position >= _duration - const Duration(milliseconds: 500)) {
        _handleVideoCompleted();
      }
    });

    _bufferedSub = repository.getBufferedStream().listen((ranges) {
      _buffered = ranges;
      notifyListeners();
    });
  }

  bool _completionHandled = false;

  /// يُستدعى تلقائيّاً حين يصل الفيديو إلى نهايته (من خلال Stream الموضع
  /// أو تغيّر حالة التشغيل). السلوك:
  ///   1) إن كانت هناك قائمة تشغيل وعنصر تالٍ → ينتقل إليه فوراً
  ///      (تشغيل تلقائيّ / Auto-play).
  ///   2) وإلّا نستدعي الـ callback الخارجيّ (للشاشات التي ترغب بعرض
  ///      شيء ما عند الانتهاء — مثلاً زرّ "شغّل مرّة أخرى").
  /// الحمايات:
  ///   • علم `_completionHandled` يمنع الاستدعاء المزدوج من مصدرَيْن
  ///     متزامنَيْن (Stream الموضع + Stream حالة التشغيل).
  void _handleVideoCompleted() {
    if (_completionHandled) return;
    _completionHandled = true;
    if (hasNext) {
      _startNextSuggestionCountdown();
      return;
    }
    // لا يوجد "تالٍ" — نتحقّق من السياق: هل نطلب اقتراحات ذكيّة؟
    if (_context.allowsSmartAutoPlay && onSimilarContentNeeded != null) {
      unawaited(playSimilarContent());
      return;
    }
    onVideoCompleted?.call();
  }

  /// يعرض بطاقة "التالي" مع عدّاد قصير بدل القفز الفوري؛ هذا يحاكي YouTube
  /// ويمنح المستخدم فرصة إلغاء التشغيل التلقائي دون تغيير منطق القائمة.
  void _startNextSuggestionCountdown({int seconds = 5}) {
    _nextSuggestionTimer?.cancel();
    _showNextSuggestion = true;
    _nextSuggestionSeconds = seconds;
    notifyListeners();
    _nextSuggestionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_nextSuggestionSeconds <= 1) {
        timer.cancel();
        _showNextSuggestion = false;
        notifyListeners();
        unawaited(playNext());
        return;
      }
      _nextSuggestionSeconds -= 1;
      notifyListeners();
    });
  }

  @visibleForTesting
  void startNextSuggestionCountdownForTest({int seconds = 5}) {
    _startNextSuggestionCountdown(seconds: seconds);
  }

  void cancelNextSuggestion() {
    _nextSuggestionTimer?.cancel();
    _showNextSuggestion = false;
    _nextSuggestionSeconds = 0;
    notifyListeners();
  }

  Future<void> acceptNextSuggestion() async {
    cancelNextSuggestion();
    await playNext();
  }

  /// يُستدعى عند انتهاء آخر فيديو في قائمة التشغيل حين يكون السياق
  /// هو "لك / بحث / رئيسية". يجلب مقاطع مشابهة عبر الـ fetcher ويحقنها
  /// في القائمة ثمّ يُشغّل التالي تلقائيًّا بحيث لا يتوقّف المشغّل.
  ///
  /// تنبيه: للفيديو لا نملك ConcatenatingSource (الحزمة video_player
  /// تدعم مصدرًا واحدًا في المرّة). لذا تكتفي [appendPlaylist] بتوسيع
  /// قائمة الـ Provider، وتتكفّل [playNext] بإعادة تهيئة الـ controller
  /// على المصدر الجديد. هذا يطابق سلوك YouTube الأصليّ (re-initialize).
  Future<void> playSimilarContent({int limit = 5}) async {
    if (_fetchingSimilar) return;
    final fetcher = onSimilarContentNeeded;
    final reference = currentVideo;
    if (fetcher == null || reference == null) return;
    _fetchingSimilar = true;
    try {
      final suggestions = await fetcher(reference: reference, limit: limit);
      final filtered = suggestions
          .where(
            (c) =>
                (c.type == ContentType.video ||
                    c.type == ContentType.youtube) &&
                (c.sourceUrl ?? '').trim().isNotEmpty &&
                !_playlist.any((p) => p.id == c.id),
          )
          .take(limit)
          .toList(growable: false);
      if (filtered.isEmpty) {
        onVideoCompleted?.call();
        return;
      }

      // وسِّع قائمة التشغيل دون مقاطعة.
      _playlist = [..._playlist, ...filtered];
      notifyListeners();

      // الآن hasNext == true → نعرض نفس بطاقة العدّاد بدلاً من القفز
      // الفوري؛ هذا يطبق شرط اقتراح التالي حتى عند الجلب الذكي بعد النهاية.
      _completionHandled = false;
      _startNextSuggestionCountdown();
    } catch (e) {
      debugPrint('[VideoPlayerProvider] playSimilarContent failed: $e');
      onVideoCompleted?.call();
    } finally {
      _fetchingSimilar = false;
    }
  }

  /// يُضيف عناصر جديدة لقائمة التشغيل بدون مقاطعة التشغيل الجاري.
  /// يُستخدم من الشاشة عند وصول مقاطع مرتبطة إضافيّة بعد بدء
  /// التشغيل — يعيد توحيد المنطق مع [AudioPlayerProvider.setPlaylist].
  void appendPlaylist(List<Content> extra) {
    if (extra.isEmpty) return;
    final ids = _playlist.map((e) => e.id).toSet();
    final newcomers = extra
        .where((c) => !ids.contains(c.id))
        .where(
          (c) =>
              (c.type == ContentType.video || c.type == ContentType.youtube) &&
              (c.sourceUrl ?? '').trim().isNotEmpty,
        )
        .toList(growable: false);
    if (newcomers.isEmpty) return;
    _playlist = [..._playlist, ...newcomers];
    notifyListeners();
  }

  // ───────────── Playback Controls ─────────────
  Future<void> play() async => await repository.play();

  Future<void> pause() async => await repository.pause();

  Future<void> toggle() async {
    if (_isPlaying) {
      await pause();
    } else {
      // Reset completion flag if replaying
      if (_position >= _duration - const Duration(milliseconds: 500)) {
        _completionHandled = false;
        await repository.seek(Duration.zero);
      }
      await play();
    }
  }

  Future<void> seek(Duration position) async {
    if (position.isNegative) position = Duration.zero;
    if (_duration > Duration.zero && position > _duration) position = _duration;
    _completionHandled = false;
    await repository.seek(position);
  }

  /// Alias for seek — used by progress bar widget
  Future<void> seekTo(Duration position) async => await seek(position);

  Future<void> forward10s() async {
    final newPos = _position + const Duration(seconds: 10);
    await seek(newPos > _duration ? _duration : newPos);
  }

  Future<void> rewind10s() async {
    final newPos = _position - const Duration(seconds: 10);
    await seek(newPos.isNegative ? Duration.zero : newPos);
  }

  // ─── Playlist Control ────────────────────────────────────────────
  /// تحميل قائمة تشغيل وبدء العنصر في [startIndex]. يُستدعى من
  /// الشاشة عند وجود مقاطع ذات صلة ليتمكّن المستخدم من التنقّل عبر
  /// أزرار التالي/السابق داخل نفس جلسة المشغّل (بدون الخروج والعودة).
  Future<void> loadPlaylist({
    required List<Content> playlist,
    required int startIndex,
  }) async {
    if (playlist.isEmpty) return;
    _playlist = playlist;
    _currentIndex = startIndex.clamp(0, playlist.length - 1);
    notifyListeners();

    await _activatePlaylistIndex(_currentIndex, saveCurrentProgress: false);
  }

  /// تحديث قائمة التشغيل فقط دون إعادة تهيئة المشغّل — يُستخدم حين
  /// تصل قائمة المقاطع ذات الصلة لاحقاً بعد بدء التشغيل.
  void setPlaylist({
    required List<Content> playlist,
    required int currentIndex,
  }) {
    if (playlist.isEmpty) return;
    _playlist = playlist;
    _currentIndex = currentIndex.clamp(0, playlist.length - 1);
    notifyListeners();
  }

  /// التالي:
  ///   1) إن بقي عنصر في قائمة التشغيل ننتقل إليه مباشرة.
  ///   2) وإلّا وكان السياق يسمح (forYou / search / home) نستدعي
  ///      [playSimilarContent] ليجلب الـ Provider اقتراحًا مشابهًا
  ///      ويُشغّله تلقائيًّا — بنفس منطق [AudioPlayerProvider.playNext].
  ///   3) غير ذلك لا شيء يُفعل (قسم ثابت / محفوظات / مباشر).
  Future<void> playNext() async {
    cancelNextSuggestion();
    if (hasNext) {
      await _activatePlaylistIndex(_currentIndex + 1);
      return;
    }
    if (_context.allowsSmartAutoPlay) {
      await playSimilarContent();
    }
  }

  Future<void> playPrevious() async {
    cancelNextSuggestion();
    if (!hasPrevious) return;
    await _activatePlaylistIndex(_currentIndex - 1);
  }

  /// هل يستطيع المستخدم الضغط على Next الآن؟
  /// صحيح إذا تبقى عنصر تالٍ، أو كان السياق يسمح بالاقتراح الذكيّ
  /// (في هذه الحالة ضغطه سيُطلق [playSimilarContent] تلقائيًّا).
  bool get canGoNext => hasNext || _context.allowsSmartAutoPlay;

  Future<void> _activatePlaylistIndex(
    int index, {
    bool saveCurrentProgress = true,
  }) async {
    if (_playlist.isEmpty) return;
    if (index < 0 || index >= _playlist.length) return;
    if (saveCurrentProgress &&
        _currentIndex >= 0 &&
        _currentIndex < _playlist.length) {
      await saveProgress(_playlist[_currentIndex].id);
    }

    _currentIndex = index;
    _position = Duration.zero;
    _duration = Duration.zero;
    _errorMessage = null;
    _completionHandled = false;

    final item = _playlist[_currentIndex];
    final src = (item.sourceUrl ?? '').trim();
    final isYouTubeItem =
        item.type == ContentType.youtube ||
        VideoPlayerDatasource.isYouTubeUrl(src);

    if (isYouTubeItem) {
      _isLoading = false;
      _isPlaying = true;
      notifyListeners();
      return;
    }

    _isPlaying = false;
    notifyListeners();
    if (src.isEmpty) return;
    await initializeVideo(item.id, src);
  }

  // ───────────── Speed Control ─────────────
  Future<void> setSpeed(double speed) async {
    _speed = speed;
    notifyListeners();
    await repository.setSpeed(speed);
  }

  /// Alias for setSpeed — used by playback speed sheet
  Future<void> setPlayBackSpeed(double speed) async => await setSpeed(speed);

  /// واجهة جودة معزولة عن مصادر الفيديو: الحزمة الحالية لا تغيّر الجودة
  /// للروابط المباشرة، لذلك نخزن اختيار المستخدم ونترك YouTube على Auto/HD.
  void setQualityLabel(String qualityLabel) {
    _qualityLabel = qualityLabel;
    notifyListeners();
  }

  void toggleInAppMiniPlayer() {
    _isInAppMiniPlayer = !_isInAppMiniPlayer;
    notifyListeners();
  }

  void exitInAppMiniPlayer() {
    if (!_isInAppMiniPlayer) return;
    _isInAppMiniPlayer = false;
    notifyListeners();
  }

  // ───────────── Scrubbing ─────────────
  void onScrubStart() {
    _isScrubbing = true;
  }

  void onScrubEnd() {
    _isScrubbing = false;
  }

  // ───────────── Fullscreen ─────────────
  Future<void> enterFullscreen(BuildContext context) async {
    _isFullscreen = true;
    notifyListeners();

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> exitFullscreen(BuildContext context) async {
    _isFullscreen = false;
    notifyListeners();

    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );

    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }

  /// حفظ تقدّم مقطع YouTube. مشغّل YouTube لا يمرّ عبر streams المشغّل
  /// الأصليّ، لذا تُغذّيه الواجهة بالموضع/المدّة الحاليَّيْن من
  /// `YoutubePlayerController` ثمّ نعيد استخدام نفس [saveProgress] حتى
  /// يُحفظ الموضع ويظهر المقطع في رفّ «تابع التصفّح» كغيره.
  Future<void> saveYoutubeProgress({
    required String videoId,
    required Duration position,
    required Duration duration,
  }) async {
    if (duration <= Duration.zero) return;
    _position = position;
    _duration = duration;
    await saveProgress(videoId);
  }

  // ───────────── Save Progress ─────────────
  Future<void> saveProgress(String videoId) async {
    if (_duration > Duration.zero) {
      try {
        await saveLastPositionUsecase(
          videoId: videoId,
          position: _position,
          duration: _duration,
        );
        Content? content;
        for (final c in _playlist) {
          if (c.id == videoId) {
            content = c;
            break;
          }
        }
        if (content != null) {
          final ratio =
              _position.inMilliseconds / _duration.inMilliseconds;
          unawaited(
            ContentEngagementService.instance.recordPlayMilestone(
              content,
              ratio: ratio,
            ),
          );
          unawaited(
            ContinueWatchingService.instance.saveProgress(
              contentId: content.id,
              positionMs: _position.inMilliseconds,
              durationMs: _duration.inMilliseconds,
              title: content.title,
              thumbnailUrl: content.thumbnailUrl,
              type: content.type,
            ),
          );
        }
      } catch (e) {
        debugPrint('Failed to save video progress: $e');
      }
    }
  }

  void stopVideo() {
    try {
      final controller = repository.getController();
      controller?.pause();
      controller?.dispose();
    } catch (_) {}
  }

  // ───────────── Reset ─────────────
  void reset() {
    if (_controllerCompletionListener != null) {
      try {
        repository.getController()?.removeListener(
          _controllerCompletionListener!,
        );
      } catch (_) {}
      _controllerCompletionListener = null;
    }
    stopVideo();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playingSub?.cancel();
    _bufferedSub?.cancel();
    _position = Duration.zero;
    _duration = Duration.zero;
    _speed = 1.0;
    _qualityLabel = 'Auto';
    _isPlaying = false;
    _isLoading = false;
    _isFullscreen = false;
    _isScrubbing = false;
    _isInAppMiniPlayer = false;
    _showNextSuggestion = false;
    _nextSuggestionSeconds = 0;
    _errorMessage = null;
    _buffered = [];
    _completionHandled = false;
    _playlist = const [];
    _currentIndex = 0;
    _isPiPActive = false;
    _nextSuggestionTimer?.cancel();
    notifyListeners();
  }

  // ───────────── Dispose ─────────────
  /// عَلَم يوقف موجة `notifyListeners` التي تأتي من callbacks متأخّرة
  /// (مثل انتهاء initializeVideo بعد فشل SSL/timeout الطويل، أو حدث Stream
  /// آخر قبل أن يلتقط cancel(). كان غيابها يُفجّر التطبيق بعشرات الـ
  /// "A VideoPlayerProvider was used after being disposed.").
  bool _disposed = false;

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    try {
      final controller = repository.getController();
      if (_controllerCompletionListener != null) {
        try {
          controller?.removeListener(_controllerCompletionListener!);
        } catch (_) {}
        _controllerCompletionListener = null;
      }
      controller?.pause();
    } catch (_) {}
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playingSub?.cancel();
    _bufferedSub?.cancel();
    _nextSuggestionTimer?.cancel();
    repository.dispose();
    super.dispose();
  }
}
