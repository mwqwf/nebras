import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nebras_mobile_app/core/widgets/auto_link_text.dart';
import 'package:nebras_mobile_app/core/widgets/content_section_breadcrumb_nav.dart';
import 'package:nebras_mobile_app/features/content/model/content_model.dart';

/// عارض الصور داخل التطبيق — لا يخرج المستخدم إلى متصفّح خارجي.
///
/// بسيط ومعزول: يقبل [Content] من نوع [ContentType.image] ويعرض الصورة
/// في نفس أسلوب بقيّة المشغّلات (شريط أدوات بسيط + عنوان + خلفية داكنة
/// + تكبير/تصغير عبر [InteractiveViewer]). الوصف يُعرض أسفل الصورة عند
/// توفّره — مثلاً عندما يكون المحتوى «صورة + وصف» دون ملف PDF.
class ImageViewerScreen extends StatelessWidget {
  final Content content;

  const ImageViewerScreen({super.key, required this.content});

  @override
  Widget build(BuildContext context) {
    final url = content.sourceUrl?.trim().isNotEmpty == true
        ? content.sourceUrl!
        : content.thumbnailUrl;
    final description = content.description.trim();
    // عند العرض الكامل نسمح بدقّة أعلى لكنّنا نظلّ نحدّ من فكّ التشفير
    // بحدّ أقصى مرتبط بأبعاد الشاشة لتفادي OOM على الأجهزة محدودة الذاكرة.
    final mq = MediaQuery.of(context);
    final dpr = mq.devicePixelRatio;
    final memCacheWidth = (mq.size.width * dpr).round();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          content.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Hero(
              tag: 'image_${content.id}',
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 5,
                child: Center(
                  child: CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.contain,
                    memCacheWidth: memCacheWidth,
                    placeholder: (_, _) => const SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                    errorWidget: (_, _, _) => Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white.withValues(alpha: 0.6),
                      size: 64.sp,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (description.isNotEmpty)
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(16.w),
              color: Colors.black87,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AutoLinkText(
                    description,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 13.sp,
                      height: 1.4,
                    ),
                    linkStyle: TextStyle(
                      color: const Color(0xFF90CAF9),
                      fontSize: 13.sp,
                      height: 1.4,
                      decoration: TextDecoration.underline,
                      decorationColor: const Color(0xFF90CAF9),
                    ),
                    textAlign: TextAlign.start,
                  ),
                  SizedBox(height: 12.h),
                  ContentSectionBreadcrumbNav(content: content),
                ],
              ),
            )
          else if (url.isEmpty)
            Padding(
              padding: EdgeInsets.all(24.w),
              child: Text(
                'Content unavailable'.tr(),
                style: const TextStyle(color: Colors.white70),
              ),
            ),
        ],
      ),
    );
  }
}
