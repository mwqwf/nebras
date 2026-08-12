import 'package:flutter/foundation.dart';
import 'package:nebras_mobile_app/core/media/content_context.dart';
import 'package:nebras_mobile_app/features/audio_player/data/datasources/audio_player_datasource.dart'
    show PlaylistTrackSpec;
import 'package:nebras_mobile_app/features/audio_player/domain/repos/audio_repos.dart';
import 'package:nebras_mobile_app/features/audio_player/domain/usecases/get_last_position_usecase.dart';
import 'package:nebras_mobile_app/features/audio_player/domain/usecases/initialize_audio_usecase.dart';
import 'package:nebras_mobile_app/features/audio_player/domain/usecases/save_last_position_usecase.dart';
import 'package:nebras_mobile_app/core/services/content_engagement_service.dart';
import 'package:nebras_mobile_app/core/services/continue_watching_service.dart';
import 'package:nebras_mobile_app/features/content/model/content_model.dart';
import 'dart:async';
import 'package:just_audio/just_audio.dart';

/// توقيع دالّة جالبة للمحتوى المشابه. يُسلَّم إليها [reference]
/// (العنصر الأخير الذي شُغِّل) وعدد العناصر المطلوبة [limit]، ويُعاد
/// قائمة `Content` جاهزة للإدراج في القائمة. كلّ فارغ/خطأ يُعامَل
/// كفشل صامت (المشغّل يتوقّف بلطف بعد آخر مقطع).
typedef SimilarContentFetcher =
    Future<List<Content>> Function({
      required Content reference,
      required int limit,
    });

class AudioPlayerProvider extends ChangeNotifier {
  final InitializeAudioUsecase initializeAudioUsecase;
  final GetLastPositionUsecase getLastPositionUsecase;
  final SaveLastPositionUsecase saveLastPositionUsecase;
  final AudioRepos audioRepos;

  AudioPlayerProvider(
    this.initializeAudioUsecase,
    this.getLastPositionUsecase,
    this.saveLastPositionUsecase,
    this.audioRepos,
  );

  // ─── State ─────────────────────────────
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _speed = 1.0;
  bool _isPlaying = false;
  bool _isLoading = true;
  String? _errorMessage;
  List<Content> _playlist = [];
  int _currentIndex = 0;

  /// سياق التشغيل (لك / بحث / قسم …) — يُقرّر هل نُشغّل اقتراحات
  /// ذكيّة عند نفاد القائمة أم نتوقّف بلطف.
  ContentContext _context = ContentContext.section;

  /// مُموِّن ذكيّ للقوائم عند النفاد — يُحدَّد من الشاشة. لا يُستدعى
  /// إلّا عندما [_context.allowsSmartAutoPlay] == true.
  SimilarContentFetcher? onSimilarContentNeeded;

  /// قفل منع التكرار عند طلب اقتراحات ذكيّة (تفادي نداءات متوازية
  /// من Stream الحالة + Stream currentIndex معًا).
  bool _fetchingSimilar = false;

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription? _playerStateSub;
  StreamSubscription<int?>? _indexSub;

  // ─── Getters ────────────────────────────
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get duration => _duration;
  double get speed => _speed;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  Content? get currentAudio =>
      _playlist.isEmpty ? null : _playlist[_currentIndex];

  /// hasNext/hasPrevious تُحسب من قائمتنا المنطقيّة (نفس ترتيب
  /// ConcatenatingAudioSource). لا نستعمل player.hasNext مباشرة حتى
  /// لا تتفكّك الواجهة قبل وصول currentIndexStream بالفهرس الجديد.
  bool get hasNext => _currentIndex < _playlist.length - 1;
  bool get hasPrevious => _currentIndex > 0;

  /// هل يستطيع المستخدم الضغط على Next الآن؟
  /// صحيح إذا تبقى عنصر تالٍ في القائمة (انتقال فوريّ)،
  /// أو كان السياق يسمح بـ Smart Auto-Play (Next يُطلق
  /// [playSimilarContent] فيجلب اقتراحًا مشابهًا ويُشغّله
  /// تلقائيًّا). هذا هو المفتاح الذي يُفعّل زرّ Next في
  /// صفحات "لك / البحث / الرئيسية" حين لا توجد قائمة.
  bool get canGoNext => hasNext || _context.allowsSmartAutoPlay;
  ContentContext get contentContext => _context;

  void setContentContext(ContentContext context) {
    _context = context;
  }

  // ─── تحميل قائمة تشغيل (ConcatenatingAudioSource) ──────────────
  /// ✅ الطريق الوحيد لتشغيل الصوت الآن. تُبنى القائمة كاملة دفعة
  ///    واحدة فيرى النظام (Android/iOS) قائمة حقيقيّة فيُفعّل أزرار
  ///    Next/Prev في الإشعار وشاشة القفل حتى لو كان التطبيق مغلقًا.
  Future<void> loadPlaylist({
    required List<Content> playlist,
    required int startIndex,
    ContentContext? context,
  }) async {
    if (playlist.isEmpty) {
      _isLoading = false;
      _errorMessage = 'Playlist is empty';
      notifyListeners();
      throw StateError('Playlist is empty');
    }

    // نستبعد العناصر بدون مصدر صوتيّ صالح لضمان أنّ كلّ عنصر في
    // القائمة قابل للتشغيل — لا ننكسر وسط التسلسل.
    final cleaned = playlist
        .where((c) => (c.sourceUrl ?? '').trim().isNotEmpty)
        .toList(growable: false);
    if (cleaned.isEmpty) {
      _isLoading = false;
      _errorMessage = 'Playlist has no playable sources';
      notifyListeners();
      throw StateError('Playlist has no playable sources');
    }

    _playlist = cleaned;
    _currentIndex = startIndex.clamp(0, cleaned.length - 1);
    _position = Duration.zero;
    _duration = Duration.zero;
    _isPlaying = false;
    _isLoading = true;
    _errorMessage = null;
    if (context != null) _context = context;
    notifyListeners();

    try {
      final lastPosition = await getLastPositionUsecase(
        _playlist[_currentIndex].id,
      );

      await audioRepos.initializePlaylist(
        tracks: _playlist.map(_trackSpecOf).toList(growable: false),
        initialIndex: _currentIndex,
        initialPosition: (lastPosition != null && lastPosition.inMilliseconds > 0)
            ? lastPosition
            : Duration.zero,
      );

      _listenToStreams();
      _isLoading = false;
      notifyListeners();

      unawaited(
        audioRepos.play().catchError((error) {
          _errorMessage = error.toString();
          notifyListeners();
        }),
      );
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString();
      debugPrint('[AudioPlayerProvider] loadPlaylist failed: $e');
      notifyListeners();
      rethrow;
    }
  }

  /// مسار التوافق العكسيّ مع الشيفرة القديمة — يُعيد توجيه أيّ
  /// `initializeAudio(singleContent)` إلى [loadPlaylist] بعنصر واحد.
  Future<void> initializeAudio(Content audio) async {
    await loadPlaylist(playlist: [audio], startIndex: 0);
  }

  // ─── Playback Controls ──────────────────

  Future<void> togglePlayPause() async {
    if (_isPlaying) {
      await initializeAudioUsecase.repo.pause();
    } else {
      await initializeAudioUsecase.repo.play();
    }
  }

  Future<void> seek(Duration position) async {
    if (position.isNegative) position = Duration.zero;
    if (position > _duration) position = _duration;
    await initializeAudioUsecase.repo.seek(position);
  }

  void updatePosition(Duration position) {
    _position = position;
    notifyListeners();
  }

  void updateDuration(Duration? duration) {
    if (duration != null) {
      _duration = duration;
      notifyListeners();
    }
  }

  void updatePlayingState(bool playing) {
    _isPlaying = playing;
    notifyListeners();
  }

  // ─── Save Progress ──────────────────────
  Future<void> saveProgress(String audioId) async {
    if (_duration.inMilliseconds > 0) {
      try {
        await saveLastPositionUsecase(
          audioId: audioId,
          position: _position,
          duration: _duration,
        );
        Content? content;
        for (final c in _playlist) {
          if (c.id == audioId) {
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
        debugPrint('Failed to save audio progress: $e');
      }
    }
  }

  void updateSpeed(double speed) {
    _speed = speed;
    notifyListeners();
  }

  // ─── Streams ───────────────────────────
  void _listenToStreams() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playerStateSub?.cancel();
    _indexSub?.cancel();

    _positionSub = audioRepos.getPositionStream().listen((position) {
      _position = position;
      final id = currentAudio?.id;
      if (id != null && position.inSeconds > 0 && position.inSeconds % 5 == 0) {
        saveProgress(id);
      }
      notifyListeners();
    });

    _durationSub = audioRepos.getDurationStream().listen((duration) {
      if (duration != null) {
        _duration = duration;
        notifyListeners();
      }
    });

    _playerStateSub = audioRepos.getPlayerStateStream().listen((state) {
      _isPlaying = audioRepos.isPlaying();
      notifyListeners();

      if (state is PlayerState &&
          state.processingState == ProcessingState.completed) {
        _handleAutoNext();
      }
    });

    // مراقبة الفهرس الحاليّ — يلتقط Next/Prev من إشعار النظام
    // (خارج واجهتنا) ويحفظ تناسق حالتنا مع حالة المشغّل.
    _indexSub = audioRepos.currentIndexStream().listen((index) {
      if (index == null) return;
      if (index < 0 || index >= _playlist.length) return;
      if (index == _currentIndex) return;
      // احفظ موضع المقطع الذي انتهينا منه قبل تغيير الفهرس.
      final prev = _playlist[_currentIndex];
      unawaited(saveProgress(prev.id));
      _currentIndex = index;
      _position = Duration.zero;
      _duration = Duration.zero;
      notifyListeners();
    });
  }

  /// يُنفَّذ عند وصول ProcessingState.completed على آخر مقطع.
  /// السلوك:
  ///   1) إن بقي عنصر تالٍ في القائمة → لا شيء (just_audio ينتقل
  ///      تلقائيًّا داخل ConcatenatingAudioSource وسيُحدَّث currentIndex).
  ///   2) وإلّا وكان السياق يسمح (forYou/search/home) → نطلب
  ///      [playSimilarContent] لمدّ القائمة تلقائيًّا.
  Future<void> _handleAutoNext() async {
    final id = currentAudio?.id;
    if (id != null) {
      await saveProgress(id);
    }
    if (hasNext) {
      // ConcatenatingAudioSource تنتقل تلقائيًّا — لا شيء يُفعل.
      return;
    }
    if (_context.allowsSmartAutoPlay) {
      await playSimilarContent();
    }
  }

  // ─── Smart Auto-Play (playSimilarContent) ──────────────────────
  /// تُستدعى تلقائيًّا عند انتهاء آخر مقطع في سياق "لك/بحث/رئيسية".
  /// تجلب عناصر مشابهة عبر [onSimilarContentNeeded] (تُعرَّف من الشاشة
  /// باستعمال RecommendationEngine + HomeProvider.sections)، ثمّ
  /// تُلحقها بالـ ConcatenatingAudioSource الحاليّة عبر [appendTracks]
  /// كي لا نُعيد تهيئة المشغّل وتظلّ أزرار الإشعار نشطة بسلاسة.
  Future<void> playSimilarContent({int limit = 5}) async {
    if (_fetchingSimilar) return;
    final fetcher = onSimilarContentNeeded;
    final reference = currentAudio;
    if (fetcher == null || reference == null) return;
    _fetchingSimilar = true;
    try {
      final suggestions = await fetcher(reference: reference, limit: limit);
      final filtered = suggestions
          .where(
            (c) =>
                c.type == ContentType.audio &&
                (c.sourceUrl ?? '').trim().isNotEmpty &&
                !_playlist.any((p) => p.id == c.id),
          )
          .take(limit)
          .toList(growable: false);
      if (filtered.isEmpty) return;

      // 1) أضف العناصر لقائمة الـ Provider.
      _playlist = [..._playlist, ...filtered];
      notifyListeners();

      // 2) أضفها لـ ConcatenatingAudioSource → النظام يعرف الآن
      //    بوجود مقاطع إضافيّة → زرّ Next يبقى نشطًا.
      await audioRepos.appendTracks(
        filtered.map(_trackSpecOf).toList(growable: false),
      );

      // 3) إن كنّا فعلًا في حالة "انتهاء" والمشغّل توقّف، ندفعه
      //    إلى العنصر التالي بوضوح حتى لا ينتظر tick آخر.
      if (!_isPlaying) {
        await audioRepos.seekToNext();
        await audioRepos.play();
      }
    } catch (e) {
      debugPrint('[AudioPlayerProvider] playSimilarContent failed: $e');
    } finally {
      _fetchingSimilar = false;
    }
  }

  // ─── Playlist Management ───────────────────────────────────────
  /// يُعيد بناء القائمة بدون إعادة تهيئة المشغّل — يُستخدم عندما
  /// تصل مقاطع مرتبطة بعد بدء التشغيل. يحاول المحافظة على المقطع
  /// الحاليّ في موضعه ويحقن البقيّة بعده عبر [appendTracks] كي لا
  /// ينقطع الصوت ولا تنكسر قائمة الإشعار.
  Future<void> setPlaylist({
    required List<Content> playlist,
    required int currentIndex,
  }) async {
    if (playlist.isEmpty) return;
    if (currentIndex < 0 || currentIndex >= playlist.length) return;

    // العناصر الجديدة التي لم تكن في قائمتنا — هذه نُضيفها فقط.
    final existingIds = _playlist.map((e) => e.id).toSet();
    final additions = playlist
        .where((c) => !existingIds.contains(c.id))
        .where((c) =>
            c.type == ContentType.audio &&
            (c.sourceUrl ?? '').trim().isNotEmpty)
        .toList(growable: false);

    if (additions.isEmpty) {
      _currentIndex = _currentIndex.clamp(0, _playlist.length - 1);
      notifyListeners();
      return;
    }

    _playlist = [..._playlist, ...additions];
    notifyListeners();
    try {
      await audioRepos.appendTracks(
        additions.map(_trackSpecOf).toList(growable: false),
      );
    } catch (e) {
      debugPrint('[AudioPlayerProvider] setPlaylist append failed: $e');
    }
  }

  // ─── Next/Previous — Native (ثابت في الإشعار وفي الواجهة) ──────
  Future<void> playNext() async {
    if (hasNext) {
      await audioRepos.seekToNext();
      return;
    }
    if (_context.allowsSmartAutoPlay) {
      await playSimilarContent();
    }
  }

  Future<void> playPrevious() async {
    if (hasPrevious) {
      await audioRepos.seekToPrevious();
    }
  }

  // ─── Reset ──────────────────────────────
  void reset() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playerStateSub?.cancel();
    _indexSub?.cancel();
    _position = Duration.zero;
    _duration = Duration.zero;
    _speed = 1.0;
    _isPlaying = false;
    _isLoading = true;
    _errorMessage = null;
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playerStateSub?.cancel();
    _indexSub?.cancel();
    super.dispose();
  }

  // ─── Mapping helpers ───────────────────────────────────────────
  PlaylistTrackSpec _trackSpecOf(Content c) => PlaylistTrackSpec(
        mediaId: c.id,
        source: (c.sourceUrl ?? '').trim(),
        title: c.title,
        album: c.sectionName ?? c.section,
        artist: c.author.isNotEmpty ? c.author : null,
        artworkUrl: c.thumbnailUrl.trim().isEmpty ? null : c.thumbnailUrl.trim(),
      );
}
