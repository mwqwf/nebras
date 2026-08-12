import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nebras_mobile_app/features/video_player/data/datasources/video_playback_progress_datasource.dart';
import 'package:nebras_mobile_app/features/video_player/data/datasources/video_player_datasource.dart';
import 'package:nebras_mobile_app/features/video_player/view/widgets/video_player.widget.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

/// MediaPlayerWidget — URL-based player abstraction
/// Detects source type and renders the correct player:
/// - YouTube URLs → YoutubePlayer (youtube_player_flutter)
/// - Direct URLs → VideoPlayerWidget (video_player)
///
/// This widget lives in the presentation layer and makes NO domain/data decisions.
class MediaPlayerWidget extends StatefulWidget {
  final String source;
  final bool isNativeInitialized;

  /// ⚠ يُستدعى عند انتهاء مقطع YouTube (PlayerState.ended). تُمرِّره
  /// الشاشة لربطه بـ `VideoPlayerProvider.playNext()` أو
  /// `VideoPlayerProvider.playSimilarContent()` بحسب السياق.
  /// غير مستعمل في مسار video_player العاديّ (ذاك يملك
  /// _handleVideoCompleted داخل الـ Provider).
  final VoidCallback? onYoutubeEnded;

  /// معرّف المحتوى الحاليّ — يُستخدم لحفظ/استئناف موضع مقاطع YouTube
  /// (مشغّل YouTube لا يمرّ عبر streams المشغّل الأصليّ).
  final String? videoId;

  /// تُستدعى دوريّاً بموضع/مدّة مقطع YouTube الحاليّ كي تحفظ الشاشة التقدّم
  /// (وتُظهره في «تابع التصفّح»). تُهمَل للفيديو الأصليّ.
  final void Function(Duration position, Duration duration)? onYoutubeProgress;

  const MediaPlayerWidget({
    super.key,
    required this.source,
    this.isNativeInitialized = false,
    this.onYoutubeEnded,
    this.videoId,
    this.onYoutubeProgress,
  });

  @override
  State<MediaPlayerWidget> createState() => _MediaPlayerWidgetState();
}

class _MediaPlayerWidgetState extends State<MediaPlayerWidget> {
  YoutubePlayerController? _ytController;
  bool _isYouTube = false;
  bool _endedFired = false;
  bool _showYoutubeControls = true;
  double _youtubeSpeed = 1.0;
  String _youtubeQuality = 'Auto';

  /// موضع الاستئناف المحفوظ (ميلي ثانية) لمقطع YouTube الحاليّ — يُقرأ من
  /// نفس مخزن مواضع الفيديو، ويُطبَّق مرّة واحدة عند جهوزيّة المشغّل.
  int _ytResumeMs = 0;
  bool _ytResumeApplied = false;
  DateTime _lastYoutubeSave = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _isYouTube = VideoPlayerDatasource.isYouTubeUrl(widget.source);

    if (_isYouTube) {
      _loadYoutubeResumePosition();
      final videoId = YoutubePlayer.convertUrlToId(widget.source);
      if (videoId != null) {
        _ytController = YoutubePlayerController(
          initialVideoId: videoId,
          flags: const YoutubePlayerFlags(
            autoPlay: true,
            mute: false,
            enableCaption: false,
            forceHD: false,
          ),
        );
        // ── Listener نهاية المقطع (YouTube) ──────────────────────
        // youtube_player_flutter يبثّ PlayerState عبر controller.value.
        // عند الوصول لـ `PlayerState.ended` نستدعي onYoutubeEnded
        // مرّة واحدة، ليُشغّل الـ Provider التالي أو يطلب اقتراحات.
        _ytController!.addListener(_onYoutubeTick);
      }
    }
  }

  /// يقرأ آخر موضع محفوظ لهذا المقطع من مخزن مواضع الفيديو (نفس المفاتيح
  /// التي يستعملها المشغّل الأصليّ) كي نستأنف من حيث توقّف المستخدم.
  Future<void> _loadYoutubeResumePosition() async {
    final id = widget.videoId?.trim() ?? '';
    if (id.isEmpty) return;
    try {
      final saved = await VideoPlaybackProgressDatasource().getLastPosition(id);
      if (saved != null) _ytResumeMs = saved.inMilliseconds;
    } catch (_) {}
  }

  void _onYoutubeTick() {
    final ctrl = _ytController;
    if (ctrl == null) return;
    final value = ctrl.value;
    final playerState = value.playerState;

    // استئناف من آخر موضع: نطبّقه مرّة واحدة فور جهوزيّة المشغّل.
    if (!_ytResumeApplied && value.isReady) {
      _ytResumeApplied = true;
      if (_ytResumeMs > 2000) {
        ctrl.seekTo(Duration(milliseconds: _ytResumeMs));
      }
    }

    // حفظ دوريّ للتقدّم (كلّ ~5 ثوانٍ) ليظهر في «تابع التصفّح» ويُستأنف.
    if (playerState == PlayerState.playing) {
      final now = DateTime.now();
      final pos = value.position;
      final dur = ctrl.metadata.duration;
      if (dur > Duration.zero &&
          pos > Duration.zero &&
          now.difference(_lastYoutubeSave).inSeconds >= 5) {
        _lastYoutubeSave = now;
        widget.onYoutubeProgress?.call(pos, dur);
      }
    }

    if (playerState == PlayerState.ended && !_endedFired) {
      _endedFired = true;
      widget.onYoutubeEnded?.call();
    }
    // إعادة التشغيل من البداية (بعد seek) تُعيد الحالة لغير ended،
    // نسمح عندها بإطلاق الحدث مرّة أخرى في المرّة التالية.
    if (playerState == PlayerState.playing && _endedFired) {
      _endedFired = false;
    }
  }

  @override
  void didUpdateWidget(covariant MediaPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // عند تغيير مصدر YouTube (مقطع تالٍ في قائمة التشغيل) نُحمّل
    // الـ videoId الجديد في نفس الـ controller حتى لا نُعيد بناء UI.
    if (_isYouTube && widget.source != oldWidget.source) {
      final newId = YoutubePlayer.convertUrlToId(widget.source);
      if (newId != null && _ytController != null) {
        _endedFired = false;
        // مقطع جديد → أعد ضبط الاستئناف واقرأ موضع المقطع الجديد.
        _ytResumeApplied = false;
        _ytResumeMs = 0;
        _lastYoutubeSave = DateTime.fromMillisecondsSinceEpoch(0);
        _loadYoutubeResumePosition();
        _ytController!.load(newId);
      }
    }
  }

  @override
  void dispose() {
    _ytController?.removeListener(_onYoutubeTick);
    _ytController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isYouTube) {
      return _buildYouTubePlayer();
    }
    // Native video_player — rendered by existing VideoPlayerWidget
    return const VideoPlayerWidget();
  }

  Widget _buildYouTubePlayer() {
    if (_ytController == null) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          color: Colors.black,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Colors.white70,
                  size: 48,
                ),
                SizedBox(height: 8.h),
                Text(
                  'Invalid YouTube URL',
                  style: TextStyle(color: Colors.white70, fontSize: 14.sp),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return YoutubePlayerBuilder(
      player: YoutubePlayer(
        controller: _ytController!,
        showVideoProgressIndicator: true,
        progressIndicatorColor: Theme.of(context).colorScheme.primary,
        progressColors: ProgressBarColors(
          playedColor: Theme.of(context).colorScheme.primary,
          handleColor: Theme.of(context).colorScheme.primary,
        ),
      ),
      builder: (context, player) => Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            // إيماءات YouTube المعروفة: النقر المزدوج على نصف الشاشة
            // الأيسر/الأيمن يرجع أو يقدّم عشر ثوانٍ بدون لمس أي مشغّل آخر.
            onDoubleTapDown: (details) {
              final width = context.size?.width ?? 0;
              final current = _ytController!.value.position;
              final delta = details.localPosition.dx < width / 2 ? -10 : 10;
              _ytController!.seekTo(
                Duration(
                  seconds: (current.inSeconds + delta).clamp(0, 1 << 31),
                ),
              );
            },
            onTap: () =>
                setState(() => _showYoutubeControls = !_showYoutubeControls),
            child: player,
          ),
          if (_showYoutubeControls)
            PositionedDirectional(
              top: 8.h,
              end: 8.w,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _YoutubeControlChip(
                    label: '${_youtubeSpeed}x',
                    onTap: _showYoutubeSpeedSheet,
                  ),
                  SizedBox(width: 8.w),
                  _YoutubeControlChip(
                    label: _youtubeQuality,
                    onTap: _showYoutubeQualitySheet,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _showYoutubeSpeedSheet() {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: speeds.map((speed) {
            final selected = _youtubeSpeed == speed;
            return ListTile(
              dense: true,
              title: Text(
                '${speed}x',
                style: TextStyle(
                  color: selected ? Colors.blueAccent : Colors.white,
                ),
              ),
              trailing: selected
                  ? const Icon(Icons.check, color: Colors.blueAccent)
                  : null,
              onTap: () {
                // youtube_player_flutter يدعم تغيير السرعة من controller،
                // ونحفظ القيمة محلياً للعرض في chip العلوي.
                _ytController?.setPlaybackRate(speed);
                setState(() => _youtubeSpeed = speed);
                Navigator.pop(context);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showYoutubeQualitySheet() {
    const qualities = ['Auto', '1080p', '720p', '480p', '360p'];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: qualities.map((quality) {
            final selected = _youtubeQuality == quality;
            return ListTile(
              dense: true,
              title: Text(
                quality,
                style: TextStyle(
                  color: selected ? Colors.blueAccent : Colors.white,
                ),
              ),
              trailing: selected
                  ? const Icon(Icons.check, color: Colors.blueAccent)
                  : null,
              onTap: () {
                // YouTube IFrame يختار الجودة الفعلية تلقائياً غالباً؛ نخزن
                // رغبة المستخدم بصرياً الآن دون اختراع API غير موجودة.
                setState(() => _youtubeQuality = quality);
                Navigator.pop(context);
              },
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _YoutubeControlChip extends StatelessWidget {
  const _YoutubeControlChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(16.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(16.r),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: 12.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
