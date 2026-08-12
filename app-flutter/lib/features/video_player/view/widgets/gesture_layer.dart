import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nebras_mobile_app/features/video_player/provider/video_player_provider.dart';
import 'package:provider/provider.dart';

/// Gesture Layer Widget
/// Handles double-tap left/right for ±10s and single tap to toggle controls
/// Auto-hide timer logic lives here (UI responsibility, not provider)
class GestureLayerWidget extends StatefulWidget {
  final VoidCallback onToggleControls;

  const GestureLayerWidget({super.key, required this.onToggleControls});

  @override
  State<GestureLayerWidget> createState() => _GestureLayerWidgetState();
}

class _GestureLayerWidgetState extends State<GestureLayerWidget>
    with SingleTickerProviderStateMixin {
  _SeekDirection? _seekDirection;
  Timer? _seekResetTimer;

  late AnimationController _rippleController;
  late Animation<double> _rippleAnimation;

  @override
  void initState() {
    super.initState();
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _rippleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _rippleController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _seekResetTimer?.cancel();
    _rippleController.dispose();
    super.dispose();
  }

  void _handleDoubleTap(_SeekDirection direction) {
    final provider = context.read<VideoPlayerProvider>();

    if (direction == _SeekDirection.forward) {
      provider.forward10s();
    } else {
      provider.rewind10s();
    }

    setState(() => _seekDirection = direction);
    _rippleController.forward(from: 0);

    _seekResetTimer?.cancel();
    _seekResetTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) {
        setState(() => _seekDirection = null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Left half — rewind
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onToggleControls,
            onDoubleTap: () => _handleDoubleTap(_SeekDirection.rewind),
            child: _seekDirection == _SeekDirection.rewind
                ? _buildSeekIndicator(Icons.replay_10, Alignment.center)
                : const SizedBox.expand(),
          ),
        ),
        // Right half — forward
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onToggleControls,
            onDoubleTap: () => _handleDoubleTap(_SeekDirection.forward),
            child: _seekDirection == _SeekDirection.forward
                ? _buildSeekIndicator(Icons.forward_10, Alignment.center)
                : const SizedBox.expand(),
          ),
        ),
      ],
    );
  }

  Widget _buildSeekIndicator(IconData icon, Alignment alignment) {
    return AnimatedBuilder(
      animation: _rippleAnimation,
      builder: (context, child) {
        return Align(
          alignment: alignment,
          child: Opacity(
            opacity: (1.0 - _rippleAnimation.value).clamp(0.0, 1.0),
            child: Container(
              width: 64.w,
              height: 64.w,
              decoration: BoxDecoration(
                color: Colors.white.withValues(
                  alpha: 0.2 * (1.0 - _rippleAnimation.value),
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 32.sp),
            ),
          ),
        );
      },
    );
  }
}

enum _SeekDirection { forward, rewind }
