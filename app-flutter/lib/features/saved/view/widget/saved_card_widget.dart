import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nebras_mobile_app/core/extensions/sized_boxextension.dart';
import 'package:nebras_mobile_app/core/theme/color_manager.dart';
import 'package:nebras_mobile_app/core/theme/text_styles.dart';
import 'package:nebras_mobile_app/core/widgets/smart_network_image.dart';
import 'package:nebras_mobile_app/features/saved/model/saved_item_model.dart';

/// Card widget for displaying a saved content item
/// Horizontal layout: thumbnail on left, info + remove button on right
class SavedCardWidget extends StatelessWidget {
  final SavedItemModel item;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const SavedCardWidget({
    super.key,
    required this.item,
    required this.onTap,
    required this.onRemove,
  });

  IconData _typeIcon(SavedContentType type) {
    switch (type) {
      case SavedContentType.video:
        return Icons.play_circle_outline;
      case SavedContentType.audio:
        return Icons.headphones;
      case SavedContentType.book:
        return Icons.menu_book;
    }
  }

  String _typeLabel(SavedContentType type) {
    switch (type) {
      case SavedContentType.video:
        return 'Video';
      case SavedContentType.audio:
        return 'Audio';
      case SavedContentType.book:
        return 'Book';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(bottom: 12.h),
        padding: EdgeInsets.all(12.w),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12.r),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(8.r),
              child: SmartNetworkImage(
                imageUrl: item.imageUrl,
                title: item.title,
                iconOverride: _typeIcon(item.type),
                width: 80.w,
                height: 80.w,
              ),
            ),

            12.sbw,

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: TextStyles.bodyBold(context),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  6.sbh,
                  // Type badge
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 8.w,
                      vertical: 2.h,
                    ),
                    decoration: BoxDecoration(
                      color: ColorsManager.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4.r),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _typeIcon(item.type),
                          size: 12.sp,
                          color: ColorsManager.primary,
                        ),
                        4.sbw,
                        Text(
                          _typeLabel(item.type).tr(),
                          style: TextStyle(
                            fontSize: 11.sp,
                            color: ColorsManager.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Remove button
            IconButton(
              onPressed: onRemove,
              icon: Icon(
                Icons.bookmark_remove,
                color: ColorsManager.error,
                size: 24.sp,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
