import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nebras_mobile_app/core/theme/color_manager.dart';

/// بطاقة اختيار لغة
///
/// أُزيلت صورة العَلَم من الواجهة بناءً على طلب المستخدم — الاعتماد الآن
/// على عنوان اللغة فقط مع دائرة اختيار واضحة. للحفاظ على التوافق مع أي
/// استدعاءات قديمة جعلنا [imagePath] اختيارياً (معَطَّل الاستخدام)، كما
/// أضفنا [leadingLabel] لعرض حرف/رمز لغة بديل أنيق في مكان العَلَم.
class LanguageCard extends StatelessWidget {
  const LanguageCard({
    super.key,
    required this.title,
    required this.ontap,
    this.isSelected = false,
    this.imagePath,
    this.leadingLabel,
  });

  final String title;
  final VoidCallback ontap;
  final bool isSelected;

  /// احتفظنا بالحقل لتوافق الاستدعاءات القديمة، لكنه لم يعد يُعرَض.
  final String? imagePath;

  /// نصّ قصير (مثلاً رمز اللغة ISO) يظهر مكان العَلَم كبديل بصري هادئ.
  final String? leadingLabel;

  @override
  Widget build(BuildContext context) {
    final primary = ColorsManager.primaryblue;
    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(14.r),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14.r),
        ),
        onTap: ontap,
        leading: _buildLeading(context, primary),
        title: Text(title),
        trailing: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 24.w,
          height: 24.w,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: primary, width: 2.w),
          ),
          child: AnimatedScale(
            scale: isSelected ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? primary : ColorsManager.transparent,
              ),
              child: isSelected
                  ? Icon(Icons.check, size: 14.w, color: ColorsManager.whiteColor)
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLeading(BuildContext context, Color primary) {
    final label = leadingLabel?.trim();
    if (label == null || label.isEmpty) {
      return CircleAvatar(
        radius: 22.r,
        backgroundColor: primary.withValues(alpha: 0.12),
        child: Icon(Icons.language_outlined, color: primary, size: 22.sp),
      );
    }
    return CircleAvatar(
      radius: 22.r,
      backgroundColor: primary.withValues(alpha: 0.12),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: primary,
          fontWeight: FontWeight.w700,
          fontSize: 14.sp,
        ),
      ),
    );
  }
}
