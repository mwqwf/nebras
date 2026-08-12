import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nebras_mobile_app/core/theme/color_manager.dart';
import 'package:nebras_mobile_app/features/video_player/provider/video_player_provider.dart';
import 'package:nebras_mobile_app/features/video_player/view/widgets/video_progress_baar_widget.dart';
import 'package:nebras_mobile_app/features/video_player/view/widgets/video_time_indicator.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

/// Control Overlay Widget
/// Shows auto-hiding playback controls on top of video
/// Controls auto-hide after 3 seconds of inactivity
class ControlOverlayWidget extends StatefulWidget {
  const ControlOverlayWidget({super.key});

  @override
  State<ControlOverlayWidget> createState() => _ControlOverlayWidgetState();
}

class _ControlOverlayWidgetState extends State<ControlOverlayWidget>
    with SingleTickerProviderStateMixin {
  bool _visible = true;
  Timer? _hideTimer;

  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      value: 1.0,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeInOut,
    );
    _startHideTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _visible) {
        _hideControls();
      }
    });
  }

  void _showControls() {
    if (!_visible) {
      setState(() => _visible = true);
      _animController.forward();
    }
    _startHideTimer();
  }

  void _hideControls() {
    _animController.reverse().then((_) {
      if (mounted) {
        setState(() => _visible = false);
      }
    });
  }

  void toggleControls() {
    if (_visible) {
      _hideTimer?.cancel();
      _hideControls();
    } else {
      _showControls();
    }
  }

  void _onUserInteraction() {
    _showControls();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerProvider>(
      builder: (context, provider, child) {
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: toggleControls,
          child: Stack(
            children: [
              FadeTransition(
                opacity: _fadeAnimation,
                child: _visible
                    ? Container(
                        color: Colors.black.withValues(alpha: 0.4),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Top/center/bottom فقط داخل الـ Column؛ بطاقة
                            // "التالي" تُرسم كـ overlay حتى لا تسبب RenderFlex.
                            _buildTopBar(context, provider),
                            _buildCenterControls(context, provider),
                            _buildBottomBar(context, provider),
                          ],
                        ),
                      )
                    : const SizedBox.expand(),
              ),
              if (_visible &&
                  provider.showNextSuggestion &&
                  provider.nextSuggestion != null)
                Positioned.fill(child: _buildNextSuggestion(context, provider)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTopBar(BuildContext context, VideoPlayerProvider provider) {
    // زرّ الوضع المصغّر (PiP) يظهر فقط على Android حين يكون الـ provider
    // قد سجَّل معالِج التصغير (عبر `_VideoPlayerView.initState`). على iOS
    // لا تتوفّر واجهة PiP الآليّة عبر `video_player`/`floating`، لذا
    // نُخفي الزرّ تماماً تجنّبًا لإعطاء المستخدم خياراً ميّتاً.
    final bool showPipButton =
        Platform.isAndroid && provider.onPipRequested != null;

    return Padding(
      padding: EdgeInsets.only(top: 8.h, right: 12.w, left: 12.w),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Picture-in-Picture button (Android only)
          if (showPipButton) ...[
            GestureDetector(
              onTap: () {
                _onUserInteraction();
                provider.onPipRequested?.call();
              },
              child: Container(
                padding: EdgeInsets.all(6.w),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(16.r),
                ),
                child: Icon(
                  Icons.picture_in_picture_alt_rounded,
                  color: ColorsManager.whiteColor,
                  size: 18.sp,
                ),
              ),
            ),
            SizedBox(width: 8.w),
          ],
          // Speed/quality menu. الجودة هنا UI-only للتدفقات المباشرة الحالية؛
          // تغيير الجودة الفعلي يحتاج manifests متعددة من الخادم لاحقاً.
          GestureDetector(
            onTap: () {
              _onUserInteraction();
              _showPlaybackOptionsSheet(context, provider);
            },
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(16.r),
              ),
              child: Text(
                '${provider.playBackSpeed}x · ${provider.qualityLabel}',
                style: TextStyle(
                  color: ColorsManager.whiteColor,
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCenterControls(
    BuildContext context,
    VideoPlayerProvider provider,
  ) {
    // عرض Previous: فقط إن وُجد عنصر سابق فعليّ في القائمة.
    // عرض Next: إن وُجد تالٍ، أو كان السياق يسمح بـ Smart Auto-Play
    // (forYou / search / home) ليُطلق ضغطه playSimilarContent() عبر
    // provider.playNext() — هذا هو الإصلاح الحقيقيّ الذي يجعل الزرّ
    // يظهر ويعمل في "لك / البحث".
    final showPrev = provider.hasPrevious;
    final showNext = provider.canGoNext;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        if (showPrev)
          _ControlButton(
            icon: Icons.skip_previous_rounded,
            size: 36.sp,
            onTap: () {
              _onUserInteraction();
              provider.playPrevious();
            },
          ),

        _ControlButton(
          icon: Icons.replay_10,
          size: 36.sp,
          onTap: () {
            _onUserInteraction();
            provider.rewind10s();
          },
        ),

        _ControlButton(
          icon: provider.isPlaying
              ? Icons.pause_circle_filled
              : Icons.play_circle_filled,
          size: 56.sp,
          onTap: () {
            _onUserInteraction();
            provider.toggle();
          },
        ),

        _ControlButton(
          icon: Icons.forward_10,
          size: 36.sp,
          onTap: () {
            _onUserInteraction();
            provider.forward10s();
          },
        ),

        if (showNext)
          _ControlButton(
            icon: Icons.skip_next_rounded,
            size: 36.sp,
            onTap: () {
              _onUserInteraction();
              provider.playNext();
            },
          ),
      ],
    );
  }

  Widget _buildNextSuggestion(
    BuildContext context,
    VideoPlayerProvider provider,
  ) {
    final suggestion = provider.nextSuggestion!;
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 320.w),
          child: Container(
            padding: EdgeInsets.all(12.w),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(14.r),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.play_circle_fill,
                      color: ColorsManager.whiteColor,
                      size: 28.sp,
                    ),
                    SizedBox(width: 10.w),
                    Expanded(
                      child: Text(
                        '${provider.nextSuggestionSeconds}s  ${suggestion.title}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: ColorsManager.whiteColor,
                          fontSize: 12.sp,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8.h),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Flexible(
                      child: TextButton(
                        onPressed: provider.cancelNextSuggestion,
                        child: Text(
                          'إلغاء',
                          style: TextStyle(
                            color: ColorsManager.whiteColor,
                            fontSize: 12.sp,
                          ),
                        ),
                      ),
                    ),
                    Flexible(
                      child: TextButton(
                        onPressed: provider.acceptNextSuggestion,
                        child: Text(
                          'تشغيل',
                          style: TextStyle(
                            color: ColorsManager.primaryblue,
                            fontSize: 12.sp,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context, VideoPlayerProvider provider) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Progress bar
          const VideoProgressBarWidget(),

          // Time + fullscreen row
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const VideoTimeIndicatorWidget(),
                _ControlButton(
                  icon: provider.isFullscreen
                      ? Icons.fullscreen_exit
                      : Icons.fullscreen,
                  size: 24.sp,
                  onTap: () {
                    if (provider.isFullscreen) {
                      provider.exitFullscreen(context);
                    } else {
                      provider.enterFullscreen(context);
                      if (context.mounted) {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ChangeNotifierProvider.value(
                              value: provider,
                              child: const _FullscreenVideoPage(),
                            ),
                          ),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showPlaybackOptionsSheet(
    BuildContext context,
    VideoPlayerProvider provider,
  ) {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    const qualities = ['Auto', '1080p', '720p', '480p', '360p'];
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
      ),
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 4.h),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    'Speed',
                    style: TextStyle(color: Colors.white70, fontSize: 12.sp),
                  ),
                ),
              ),
              ...speeds.map((speed) {
                final selected = provider.playBackSpeed == speed;
                return ListTile(
                  dense: true,
                  title: Text(
                    '${speed}x',
                    style: TextStyle(
                      color: selected
                          ? ColorsManager.primaryblue
                          : ColorsManager.whiteColor,
                    ),
                  ),
                  trailing: selected
                      ? Icon(Icons.check, color: ColorsManager.primaryblue)
                      : null,
                  onTap: () {
                    provider.setPlayBackSpeed(speed);
                    Navigator.pop(context);
                  },
                );
              }),
              const Divider(color: Colors.white24),
              Padding(
                padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 4.h),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    'Quality',
                    style: TextStyle(color: Colors.white70, fontSize: 12.sp),
                  ),
                ),
              ),
              ...qualities.map((quality) {
                final selected = provider.qualityLabel == quality;
                return ListTile(
                  dense: true,
                  title: Text(
                    quality,
                    style: TextStyle(
                      color: selected
                          ? ColorsManager.primaryblue
                          : ColorsManager.whiteColor,
                    ),
                  ),
                  trailing: selected
                      ? Icon(Icons.check, color: ColorsManager.primaryblue)
                      : null,
                  onTap: () {
                    provider.setQualityLabel(quality);
                    Navigator.pop(context);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

@visibleForTesting
Widget buildVideoNextSuggestionCardForTest({
  required BuildContext context,
  required String title,
  required int seconds,
  required VoidCallback onCancel,
  required VoidCallback onPlayNow,
}) {
  return Center(
    child: SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 320.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$seconds s  $title',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            Wrap(
              children: [
                TextButton(onPressed: onCancel, child: const Text('Cancel')),
                TextButton(onPressed: onPlayNow, child: const Text('Play')),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// Simple control button widget — يدعم حالة "معطّل" لإخفاء التفاعل
/// مع عرض لون باهت (مثلاً حين لا يوجد "تالٍ" في قائمة التشغيل).
class _ControlButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final VoidCallback? onTap;

  const _ControlButton({
    required this.icon,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Icon(icon, color: ColorsManager.whiteColor, size: size),
    );
  }
}

/// Internal fullscreen page — receives provider via ChangeNotifierProvider.value
class _FullscreenVideoPage extends StatelessWidget {
  const _FullscreenVideoPage();

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerProvider>(
      builder: (context, provider, _) {
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;
            await provider.exitFullscreen(context);
          },
          child: Scaffold(
            backgroundColor: ColorsManager.blackcolor,
            body: Stack(
              children: [
                // Video
                Center(
                  child: provider.controller != null
                      ? AspectRatio(
                          aspectRatio: provider.controller!.value.aspectRatio,
                          child: VideoPlayer(provider.controller!),
                        )
                      : const SizedBox.shrink(),
                ),
                // Controls overlay
                const Positioned.fill(child: ControlOverlayWidget()),
              ],
            ),
          ),
        );
      },
    );
  }
}
