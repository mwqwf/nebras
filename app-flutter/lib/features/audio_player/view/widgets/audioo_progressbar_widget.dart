import 'package:flutter/material.dart';
import 'package:nebras_mobile_app/features/audio_player/provider/audio_player_provider.dart';
import 'package:provider/provider.dart';

/// شريط تقدّم تفاعليّ للصوت مع:
/// - عرض الموضع الحاليّ والمدّة الكلّيّة.
/// - السحب الفوريّ (Instant Seek) مع معاينة الموضع الجديد.
/// - النقر لأيّ موضع للانتقال الفوريّ (Tap-to-seek).
/// - رأس قابلة للتكبير أثناء السحب لتحسين وضوح اللمس.
/// - تحديث سلس للموضع أثناء التشغيل (بدون اهتزاز) بعد رفع الإصبع.
class AudioProgressBar extends StatefulWidget {
  final double barHeight;
  final Color? progressColor;
  final Color? backgroundColor;
  final Color? thumbColor;
  final bool showTimeLabels;
  final TextStyle? timeLabelStyle;

  const AudioProgressBar({
    super.key,
    this.barHeight = 4.0,
    this.progressColor,
    this.backgroundColor,
    this.thumbColor,
    this.showTimeLabels = true,
    this.timeLabelStyle,
  });

  @override
  State<AudioProgressBar> createState() => _AudioProgressBarState();
}

class _AudioProgressBarState extends State<AudioProgressBar> {
  /// هل يسحب المستخدم المقبض الآن؟ نُجمِّد تحديث الموضع الحيّ حتى
  /// يرفع إصبعه فلا يقفز الشريط بين موضع السحب وموضع التشغيل.
  bool _isDragging = false;

  /// الموضع المؤقّت أثناء السحب (قبل الالتزام بـ seek).
  Duration? _dragPosition;

  @override
  Widget build(BuildContext context) {
    return Consumer<AudioPlayerProvider>(
      builder: (context, audioProvider, child) {
        final displayPosition = _isDragging && _dragPosition != null
            ? _dragPosition!
            : audioProvider.position;

        final duration = audioProvider.duration;

        final progress = duration.inMilliseconds > 0
            ? (displayPosition.inMilliseconds / duration.inMilliseconds).clamp(
                0.0,
                1.0,
              )
            : 0.0;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildProgressBar(
              context,
              provider: audioProvider,
              progress: progress,
              duration: duration,
            ),
            if (widget.showTimeLabels) ...[
              const SizedBox(height: 8),
              _buildTimeLabels(displayPosition, duration),
            ],
          ],
        );
      },
    );
  }

  Widget _buildProgressBar(
    BuildContext context, {
    required AudioPlayerProvider provider,
    required double progress,
    required Duration duration,
  }) {
    final theme = Theme.of(context);
    final progressColor = widget.progressColor ?? theme.colorScheme.primary;
    final backgroundColor =
        widget.backgroundColor ??
        theme.colorScheme.onSurface.withValues(alpha: 0.1);
    final thumbColor = widget.thumbColor ?? progressColor;

    return LayoutBuilder(
      builder: (context, constraints) {
        final barWidth = constraints.maxWidth;

        Duration positionFromDx(double dx) {
          if (duration.inMilliseconds <= 0 || barWidth <= 0) {
            return Duration.zero;
          }
          final ratio = (dx / barWidth).clamp(0.0, 1.0);
          final ms = (duration.inMilliseconds * ratio).round();
          return Duration(milliseconds: ms);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          // ── Tap-to-seek ──────────────────────────────────────────────
          // نقرة مفردة → انتقال فوريّ للموضع المنقور.
          onTapDown: (details) {
            if (duration.inMilliseconds <= 0) return;
            final pos = positionFromDx(details.localPosition.dx);
            provider.seek(pos);
          },
          // ── Drag-to-seek ─────────────────────────────────────────────
          // السحب الأفقيّ يعرض معاينة حيّة، ثمّ يلتزم بالموضع عند
          // الرفع.
          onHorizontalDragStart: (details) {
            if (duration.inMilliseconds <= 0) return;
            setState(() {
              _isDragging = true;
              _dragPosition = positionFromDx(details.localPosition.dx);
            });
          },
          onHorizontalDragUpdate: (details) {
            if (!_isDragging) return;
            setState(() {
              _dragPosition = positionFromDx(details.localPosition.dx);
            });
          },
          onHorizontalDragEnd: (_) async {
            if (!_isDragging) return;
            final target = _dragPosition ?? Duration.zero;
            await provider.seek(target);
            if (!mounted) return;
            setState(() {
              _isDragging = false;
              _dragPosition = null;
            });
          },
          onHorizontalDragCancel: () {
            if (!_isDragging) return;
            setState(() {
              _isDragging = false;
              _dragPosition = null;
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  width: barWidth,
                  height: widget.barHeight,
                  decoration: BoxDecoration(
                    color: backgroundColor,
                    borderRadius: BorderRadius.circular(widget.barHeight / 2),
                  ),
                ),
                AnimatedContainer(
                  duration: _isDragging
                      ? Duration.zero
                      : const Duration(milliseconds: 150),
                  width: barWidth * progress,
                  height: widget.barHeight,
                  decoration: BoxDecoration(
                    color: progressColor,
                    borderRadius: BorderRadius.circular(widget.barHeight / 2),
                  ),
                ),
                Positioned(
                  left: (barWidth * progress).clamp(0.0, barWidth) - 6,
                  child: AnimatedScale(
                    scale: _isDragging ? 1.4 : 1.0,
                    duration: const Duration(milliseconds: 120),
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: thumbColor,
                        shape: BoxShape.circle,
                        boxShadow: _isDragging
                            ? [
                                BoxShadow(
                                  color: thumbColor.withValues(alpha: 0.35),
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTimeLabels(Duration position, Duration duration) {
    final textStyle =
        widget.timeLabelStyle ??
        Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(_formatDuration(position), style: textStyle),
          Text(_formatDuration(duration), style: textStyle),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(1, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(1, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
}
