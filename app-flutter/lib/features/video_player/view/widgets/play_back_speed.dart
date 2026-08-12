import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nebras_mobile_app/core/theme/color_manager.dart';
import 'package:provider/provider.dart';
import '../../provider/video_player_provider.dart';

const List<double> speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

void showPlaybackSpeedSheet(BuildContext context) {
  final provider = context.read<VideoPlayerProvider>();

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.black87,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
    ),
    builder: (_) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: speeds.map((speed) {
          final isSelected = provider.playBackSpeed == speed;

          return ListTile(
            title: Text(
              '${speed}x',
              style: TextStyle(
                color: isSelected
                    ? ColorsManager.primaryblue
                    : ColorsManager.whiteColor,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            onTap: () {
              provider.setPlayBackSpeed(speed);
              Navigator.pop(context);
            },
          );
        }).toList(),
      );
    },
  );
}
