import 'package:flutter/material.dart';
import 'package:nebras_mobile_app/features/video_player/provider/video_player_provider.dart';
import 'package:nebras_mobile_app/features/video_player/view/widgets/control_overlay_widget.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

/// Composite Video Player Widget
/// Handles rendering + overlay + lifecycle safe playback
class VideoPlayerWidget extends StatefulWidget {
  const VideoPlayerWidget({super.key});

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  bool _startedPlayback = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    /// Ensure playback starts only once after widget is built
    if (!_startedPlayback) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        final provider = context.read<VideoPlayerProvider>();

        if (provider.controller != null &&
            provider.controller!.value.isInitialized) {
          provider.play();
        }

        _startedPlayback = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerProvider>(
      builder: (context, provider, _) {
        final controller = provider.controller;

        /// Loading state
        if (provider.isLoading || controller == null) {
          return AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              color: Colors.black,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
          );
        }

        /// Error state
        if (provider.errorMessage != null) {
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
                      color: Colors.redAccent,
                      size: 48,
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        provider.errorMessage!,
                        style: const TextStyle(color: Colors.white70),
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        /// Listen to controller updates (important)
        return ValueListenableBuilder(
          valueListenable: controller,
          builder: (context, VideoPlayerValue value, child) {
            if (!value.isInitialized) {
              return const AspectRatio(
                aspectRatio: 16 / 9,
                child: Center(child: CircularProgressIndicator()),
              );
            }

            return AspectRatio(
              aspectRatio: value.aspectRatio,
              child: GestureDetector(
                // إيماءات يوتيوب السريعة: نقر مزدوج يمين/يسار للتقديم
                // أو الرجوع عشر ثوانٍ دون تغيير بنية المشغّل الحالية.
                onDoubleTapDown: (details) {
                  final width = context.size?.width ?? 0;
                  if (width > 0 && details.localPosition.dx < width / 2) {
                    provider.rewind10s();
                  } else {
                    provider.forward10s();
                  }
                },
                child: Stack(
                  children: [
                    /// Video rendering
                    VideoPlayer(controller),

                    /// Controls overlay
                    const Positioned.fill(child: ControlOverlayWidget()),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
