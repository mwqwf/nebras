import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nebras_mobile_app/core/extensions/sized_boxextension.dart';
import 'package:nebras_mobile_app/core/theme/color_manager.dart';
import 'package:nebras_mobile_app/core/theme/text_styles.dart';

class DownloadedView extends StatelessWidget {
  const DownloadedView({super.key, required this.onRead});
  final VoidCallback onRead;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.check_circle, color: ColorsManager.success, size: 22.sp),
        8.sbw,
        Text(
          "Downloaded".tr(),
          style: TextStyles.smallText(context).copyWith(
            color: ColorsManager.success,
            fontWeight: FontWeight.w500,
          ),
        ),
        const Spacer(),
        ElevatedButton.icon(
          onPressed: onRead,
          icon: Icon(Icons.menu_book, size: 18.sp),
          label: Text("Read".tr()),
          style: ElevatedButton.styleFrom(
            backgroundColor: ColorsManager.primary,
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.r),
            ),
          ),
        ),
      ],
    );
  }
}
