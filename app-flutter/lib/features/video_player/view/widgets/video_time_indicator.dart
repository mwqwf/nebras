import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nebras_mobile_app/core/theme/color_manager.dart';
import 'package:nebras_mobile_app/features/video_player/provider/video_player_provider.dart';
import 'package:provider/provider.dart';

class VideoTimeIndicatorWidget extends StatelessWidget {
  const VideoTimeIndicatorWidget({super.key});

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final position = context.select<VideoPlayerProvider, Duration>(
      (p) => p.position,
    );
    final duration = context.select<VideoPlayerProvider, Duration>(
      (p) => p.duration,
    );

    if (duration == Duration.zero) {
      return const SizedBox.shrink();
    }
    return Text(
      '${_formatDuration(position)} / ${_formatDuration(duration)}',
      style: TextStyle(fontSize: 12.sp, color: ColorsManager.white70),
    );
  }
}
