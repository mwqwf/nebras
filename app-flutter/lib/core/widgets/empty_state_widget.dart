import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:lottie/lottie.dart';
import 'package:nebras_mobile_app/core/extensions/sized_boxextension.dart';
import 'package:nebras_mobile_app/core/theme/text_styles.dart';

class EmptyStateWidget extends StatelessWidget {
  const EmptyStateWidget({super.key, required this.message, this.height});

  final String message;
  final double? height;

  @override
  Widget build(BuildContext context) {
    // الملفّان `empty_dark.json` و `empty_light.json` كانا متطابقين
    // بايتيّاً (158KB لكلٍّ منهما). أبقينا ملفّاً واحداً فقط ووفّرنا
    // ~158KB من حجم الـ AAB النهائيّ. التلوين يتمّ runtime عبر معدِّل
    // ColorFilter إذا احتجنا لاحقاً لاختلاف بصريّ بين الوضعَين.
    const animationPath = 'assets/lottie/empty.json';

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Lottie.asset(
              animationPath,
              height: height ?? 260.h,
              repeat: true,
              fit: BoxFit.contain,
              frameRate: FrameRate.max,
            ),

            24.sbh,

            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyles.body(context),
            ),
          ],
        ),
      ),
    );
  }
}
