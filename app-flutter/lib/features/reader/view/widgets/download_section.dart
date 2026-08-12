import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nebras_mobile_app/features/download/data/download_item_model.dart';
import 'package:nebras_mobile_app/features/download/provider/media_download_provider.dart';
import 'package:nebras_mobile_app/features/reader/view/widgets/deownload_view.dart';
import 'package:nebras_mobile_app/features/reader/view/widgets/downloading_view.dart';
import 'package:nebras_mobile_app/features/reader/view/widgets/error_view.dart';
import 'package:nebras_mobile_app/features/reader/view/widgets/idle_view.dart';
import 'package:provider/provider.dart';

class DownloadSection extends StatelessWidget {
  const DownloadSection({
    super.key,
    required this.onRead,
    required this.contentId,
    required this.url,
    this.title = '',
    this.imageUrl,
  });

  final VoidCallback onRead;
  final String contentId;
  final String url;
  final String title;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    return Consumer<MediaDownloadProvider>(
      builder: (_, provider, child) {
        return Container(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16.r),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            switchInCurve: Curves.easeIn,
            switchOutCurve: Curves.easeOut,
            child: _buildState(context, provider),
          ),
        );
      },
    );
  }

  Widget _buildState(BuildContext context, MediaDownloadProvider provider) {
    final status = provider.getStatus(contentId);
    final progress = provider.getProgress(contentId);

    switch (status) {
      case MediaDownloadStatus.idle:
        return IdleView(
          key: const ValueKey('idle'),
          onRead: onRead,
          onDownload: () {
            provider.start(contentId, url, 'document',
                title: title, imageUrl: imageUrl);
          },
        );

      case MediaDownloadStatus.downloading:
        return DownloadingView(
          progress: progress,
          key: const ValueKey('downloading'),
          onCancel: () {
            provider.cancel(contentId);
          },
        );

      case MediaDownloadStatus.paused:
        return IdleView(
          key: const ValueKey('paused'),
          onRead: onRead,
          onDownload: () {
            provider.resume(contentId);
          },
        );

      case MediaDownloadStatus.completed:
        return DownloadedView(
          key: const ValueKey('downloaded'),
          onRead: onRead,
        );

      case MediaDownloadStatus.failed:
        return ErrorView(
          key: const ValueKey('error'),
          onRetry: () {
            provider.start(contentId, url, 'document',
                title: title, imageUrl: imageUrl);
          },
        );
    }
  }
}
