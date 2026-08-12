import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nebras_mobile_app/core/widgets/smart_network_image.dart';

/// خليّة قسم على شكل بطاقة مربّعة تُستخدم في نمط عرض الشبكة (ثلاثة في صفّ).
///
/// تعرض الصورة دائماً عبر [SmartNetworkImage] — الذي يتعامل مع غياب
/// الرابط أو فشل التحميل عبر بطاقة افتراضيّة ذكيّة مبنيّة على كلمات
/// العنوان (قرآن/عقيدة/فقه/...). لم يعد هناك fallback محلّي هنا.
class SectionGridTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? imageUrl;
  final VoidCallback onTap;

  const SectionGridTile({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.cardColor,
      borderRadius: BorderRadius.circular(14.r),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(8.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // الصورة — تحتلّ معظم ارتفاع البطاقة لتعطي هويّة بصرية.
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10.r),
                  child: SmartNetworkImage(
                    imageUrl: imageUrl,
                    title: title,
                  ),
                ),
              ),
              SizedBox(height: 8.h),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
