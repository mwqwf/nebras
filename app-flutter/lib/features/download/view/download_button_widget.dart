import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nebras_mobile_app/core/theme/color_manager.dart';
import 'package:nebras_mobile_app/features/download/data/download_item_model.dart';
import 'package:nebras_mobile_app/features/download/provider/media_download_provider.dart';
import 'package:provider/provider.dart';

/// Reusable download button that reflects download state
/// - idle → download icon
/// - downloading → circular progress with pause
/// - paused → resume icon
/// - completed → check icon
/// - failed → retry icon
class DownloadButton extends StatelessWidget {
  final String contentId;
  final String url;
  final String contentType;
  final String title;
  final String? imageUrl;

  const DownloadButton({
    super.key,
    required this.contentId,
    required this.url,
    required this.contentType,
    required this.title,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<MediaDownloadProvider>(
      builder: (context, provider, _) {
        final status = provider.getStatus(contentId);
        final progress = provider.getProgress(contentId);

        switch (status) {
          case MediaDownloadStatus.idle:
            return IconButton(
              icon: Icon(Icons.download, size: 28.sp),
              onPressed: () => provider.start(
                contentId,
                url,
                contentType,
                title: title,
                imageUrl: imageUrl,
              ),
              tooltip: 'Download'.tr(),
            );

          case MediaDownloadStatus.downloading:
            return SizedBox(
              width: 48.w,
              height: 48.w,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: progress > 0 ? progress : null,
                    strokeWidth: 2.5,
                    color: ColorsManager.primary,
                  ),
                  IconButton(
                    icon: Icon(Icons.pause, size: 20.sp),
                    onPressed: () => provider.pause(contentId),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Pause'.tr(),
                  ),
                ],
              ),
            );

          case MediaDownloadStatus.paused:
            return IconButton(
              icon: Icon(
                Icons.play_arrow,
                size: 28.sp,
                color: ColorsManager.warning,
              ),
              onPressed: () => provider.resume(contentId),
              tooltip: 'Resume'.tr(),
            );

          case MediaDownloadStatus.completed:
            return IconButton(
              icon: Icon(
                Icons.check_circle,
                size: 28.sp,
                color: ColorsManager.success,
              ),
              onPressed: () {
                _showDeleteDialog(context, provider);
              },
              tooltip: 'Downloaded'.tr(),
            );

          case MediaDownloadStatus.failed:
            return IconButton(
              icon: Icon(
                Icons.refresh,
                size: 28.sp,
                color: ColorsManager.error,
              ),
              onPressed: () => provider.resume(contentId),
              tooltip: 'Retry'.tr(),
            );
        }
      },
    );
  }

  void _showDeleteDialog(BuildContext context, MediaDownloadProvider provider) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Delete Download'.tr()),
        content: Text('Remove downloaded file?'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'.tr()),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              provider.delete(contentId);
            },
            child: Text(
              'Delete'.tr(),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}
