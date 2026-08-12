import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nebras_mobile_app/core/extensions/sized_boxextension.dart';
import 'package:nebras_mobile_app/core/theme/text_styles.dart';
import 'package:nebras_mobile_app/core/widgets/smart_network_image.dart';
import 'package:nebras_mobile_app/features/content/model/content_model.dart';

class BoookHeaderWidget extends StatelessWidget {
  const BoookHeaderWidget({super.key, required this.content});

  final Content content;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      width: double.infinity,
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Book cover
          ClipRRect(
            borderRadius: BorderRadius.circular(12.r),
            child: SmartNetworkImage(
              imageUrl: content.thumbnailUrl,
              title: content.title,
              iconOverride: Icons.menu_book,
              width: 110.w,
              height: 155.h,
            ),
          ),
          16.sbw,
          // Book info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                8.sbh,
                Text(
                  content.title,
                  style: TextStyles.heading3(context),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                if (content.section.isNotEmpty &&
                    (content.sectionName?.trim().isNotEmpty ?? false)) ...[
                  8.sbh,
                  Row(
                    children: [
                      Icon(
                        Icons.folder_outlined,
                        size: 14.sp,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      4.sbw,
                      Flexible(
                        child: Text(
                          content.sectionName!.trim(),
                          style: TextStyles.greysmallText(context),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
