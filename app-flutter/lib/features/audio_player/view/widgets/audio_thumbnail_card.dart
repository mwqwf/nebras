import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nebras_mobile_app/core/extensions/sized_boxextension.dart';
import 'package:nebras_mobile_app/core/theme/text_styles.dart';
import 'package:nebras_mobile_app/core/widgets/smart_network_image.dart';

class AudioThumbnailCard extends StatelessWidget {
  final String title;
  final String? thumbnailUrl;

  const AudioThumbnailCard({super.key, required this.title, this.thumbnailUrl});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 300.w,
          height: 220.h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16.r),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16.r),
            // العنصر النائب الذكيّ يتولّى حالات `null`/فشل التحميل تلقائيًّا
            // مع أيقونة نوع الوسيط (صوت) فوق تدرّج متناسق.
            child: SmartNetworkImage(
              imageUrl: thumbnailUrl,
              title: title,
              iconOverride: Icons.music_note,
            ),
          ),
        ),
        12.sbh,
        Center(
          child: Text(
            title,
            style: TextStyles.heading3(context),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
