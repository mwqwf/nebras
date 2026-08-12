import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:nebras_mobile_app/core/theme/color_manager.dart';
import 'package:nebras_mobile_app/features/video_player/provider/video_player_provider.dart';
import 'package:provider/provider.dart';

class VideoProgressBarWidget extends StatelessWidget {
  const VideoProgressBarWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerProvider>(
      builder: (_, provider, _) {
        final duration = provider.duration;
        final position = provider.position;

        if (duration.inMilliseconds <= 0) {
          return const SizedBox.shrink();
        }

        final progress = (position.inMilliseconds / duration.inMilliseconds)
            .clamp(0.0, 1.0);

        double bufferedProgress = 0.0;
        if (provider.buffered.isNotEmpty) {
          bufferedProgress =
              provider.buffered
                  .map((range) => range.end.inMilliseconds)
                  .reduce(math.max) /
              duration.inMilliseconds;

          bufferedProgress = bufferedProgress.clamp(0.0, 1.0);
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              // Buffered bar
              LinearProgressIndicator(
                value: bufferedProgress,
                backgroundColor: Colors.white24,
                valueColor: const AlwaysStoppedAnimation(Colors.white38),
                minHeight: 3,
              ),

              // Scrubbable slider
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 12,
                  ),
                ),
                child: Slider(
                  value: progress,
                  onChangeStart: (_) {
                    provider.onScrubStart();
                  },
                  onChanged: (value) {
                    final newPosition = duration * value.clamp(0.0, 1.0);
                    provider.seekTo(newPosition);
                  },
                  onChangeEnd: (_) {
                    provider.onScrubEnd();
                  },
                  activeColor: ColorsManager.whiteColor,
                  inactiveColor: Colors.transparent,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
