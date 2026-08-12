import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nebras_mobile_app/core/theme/text_styles.dart';
import 'package:nebras_mobile_app/core/theme/color_manager.dart';

class NotificationTile extends StatelessWidget {
  const NotificationTile({
    super.key,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.dismissibleKey,
    required this.onDismissed,
    this.isRead = false,
    this.onTap,
  });

  final String title;
  final String body;
  final DateTime createdAt;
  final Key dismissibleKey;
  final void Function(DismissDirection direction) onDismissed;
  final bool isRead;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: dismissibleKey,
      direction: DismissDirection.endToStart,
      background: _buildDismissBackground(context, isSecondary: false),
      secondaryBackground: _buildDismissBackground(context, isSecondary: true),
      onDismissed: onDismissed,
      child: Container(
        decoration: BoxDecoration(
          color: isRead
              ? Theme.of(context).colorScheme.surface
              : ColorsManager.primary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(
            color: isRead
                ? ColorsManager.border
                : ColorsManager.primary.withValues(alpha: 0.2),
          ),
        ),
        child: ListTile(
          contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
          leading: Stack(
            children: [
              CircleAvatar(
                radius: 22.r,
                backgroundColor: ColorsManager.primary,
                child: Icon(
                  Icons.notifications,
                  color: ColorsManager.whiteColor,
                  size: 20.sp,
                ),
              ),
              // Unread dot indicator
              if (!isRead)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    width: 10.r,
                    height: 10.r,
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.surface,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          title: Text(
            title,
            style: TextStyles.bodyBold(context).copyWith(
              color: isRead
                  ? ColorsManager.textMuted
                  : ColorsManager.textPrimary,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 4.h),
              Text(
                body,
                style: TextStyles.smallText(
                  context,
                ).copyWith(color: ColorsManager.textSecondary),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: 4.h),
              Text(
                _formatTime(createdAt),
                style: TextStyles.smallText(
                  context,
                ).copyWith(color: ColorsManager.textMuted, fontSize: 11.sp),
              ),
            ],
          ),
          onTap: onTap,
        ),
      ),
    );
  }

  String _formatTime(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'Just now'.tr();
    if (diff.inMinutes < 60) {
      return '{} minutes ago'.tr(args: ['${diff.inMinutes}']);
    }
    if (diff.inHours < 24) {
      return '{} hours ago'.tr(args: ['${diff.inHours}']);
    }
    if (diff.inDays < 7) return '{} days ago'.tr(args: ['${diff.inDays}']);
    return '${date.day}/${date.month}/${date.year}';
  }

  Widget _buildDismissBackground(
    BuildContext context, {
    required bool isSecondary,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.red.shade600,
        borderRadius: BorderRadius.circular(16.r),
      ),
      alignment: isSecondary ? Alignment.centerRight : Alignment.centerLeft,
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isSecondary)
            Icon(Icons.delete_outline, color: ColorsManager.whiteColor),
          if (!isSecondary) SizedBox(width: 8.w),
          Text(
            'Delete'.tr(),
            style: TextStyle(
              color: ColorsManager.whiteColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (isSecondary) SizedBox(width: 8.w),
          if (isSecondary)
            const Icon(Icons.delete_outline, color: ColorsManager.whiteColor),
        ],
      ),
    );
  }
}
