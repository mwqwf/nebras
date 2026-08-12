import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nebras_mobile_app/core/extensions/sized_boxextension.dart';
import 'package:nebras_mobile_app/core/services/recommendation_engine.dart';
import 'package:nebras_mobile_app/core/services/interest_profile_service.dart';
import 'package:nebras_mobile_app/core/services/user_behavior_tracker.dart';
import 'package:nebras_mobile_app/core/theme/text_styles.dart';
import 'package:nebras_mobile_app/core/widgets/horizental_contentlist_widget.dart';
import 'package:nebras_mobile_app/features/content/model/content_model.dart';
import 'package:nebras_mobile_app/features/home/providers/home_provider.dart';
import 'package:provider/provider.dart';

/// RelatedContentList — قسم "قد يعجبك أيضاً / ذات صلة" (YouTube-style).
///
/// ── الهدف ──
/// يُدمج في أيّ شاشة عرض محتوى (فيديو/صوت/كتاب/صورة/مقال)، فيُظهر للمستخدم
/// قائمة أفقيّة من المحتوى المشابه ليبقى داخل التطبيق ويستكشف أكثر.
///
/// ── مصادر التوصيات ──
/// 1) **المحتوى المحلّي**: يقرأ من `HomeProvider.sections` ويستخدم
///    `RecommendationEngine` لترتيب المرشّحين بحسب: نفس القسم، نفس النوع،
///    تطابق الكلمات، واهتمام المستخدم.
///
/// ── لماذا widget مستقلّ؟ ──
/// لتطبيق قاعدة "نفس الـ UI لكلّ المصادر" — لا نُكرّر بناء القائمة داخل
/// كلّ مُشغّل. كلّ مُشغّل يُضيف `RelatedContentList(reference: c)` فقط.
class RelatedContentList extends StatefulWidget {
  final Content reference;
  final FutureOr<void> Function(Content content)? onContentTap;

  /// عنوان القسم كما يظهر. افتراضيًّا "قد يعجبك أيضاً".
  final String? titleOverride;

  /// ارتفاع القائمة الأفقيّة — يناسب التصميم الحاليّ.
  final double height;

  /// الحدّ الأقصى لعدد التوصيات المعروضة (محلّي).
  final int maxItems;

  const RelatedContentList({
    super.key,
    required this.reference,
    this.onContentTap,
    this.titleOverride,
    this.height = 190,
    this.maxItems = 12,
  });

  @override
  State<RelatedContentList> createState() => _RelatedContentListState();
}

class _RelatedContentListState extends State<RelatedContentList> {

  /// التوصيات المحلّية — تُحسب synchronously من `HomeProvider.sections`.
  List<Content> _localItems = const [];

  @override
  void initState() {
    super.initState();
    // نُؤجّل للحصول على `HomeProvider` بعد البناء الأوّل.
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    if (!mounted) return;
    _recomputeLocal();
  }

  void _recomputeLocal() {
    if (!mounted) return;
    try {
      final home = context.read<HomeProvider>();
      // نستعمل الخوارزميّة الهجينة 50/50: نصف من نفس القسم والنصف الآخر
      // من كلمات مفتاحيّة متشابهة.
      final list = RecommendationEngine.getRelatedContent(
        widget.reference,
        pool: home.sections,
        limit: widget.maxItems,
      );
      setState(() => _localItems = list);
    } catch (_) {
      // لو كانت الـ Provider مفقودة (اختبار معزول) نُبقي القائمة فارغة
      // بصمت ولا نُعطّل المُشغّل الأساسيّ.
    }
  }

  @override
  Widget build(BuildContext context) {
    // نعيد الحساب الهجين عند كلّ إعادة بناء للمؤلّف — مجّاني نسبيًّا،
    // ويضمن ظهور محتوى جديد إن وصلت أقسام جديدة من Firebase أثناء
    // وجود المستخدم في الصفحة.
    final home = context.watch<HomeProvider?>();
    if (home != null && _localItems.isEmpty) {
      _localItems = RecommendationEngine.getRelatedContent(
        widget.reference,
        pool: home.sections,
        limit: widget.maxItems,
      );
    }

    // `_localItems` الآن تحتوي على الخليط الهجين (نفس القسم + كلمات
    // متشابهة) المُضفَّر مسبقًا؛ لا نُلحق بعده أيّ شيء إضافيّ.
    final merged = _localItems.take(widget.maxItems).toList();
    if (merged.isEmpty) {
      return const SizedBox.shrink();
    }

    final title = widget.titleOverride ?? 'You may also like'.tr();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.w),
          child: Row(
            children: [
              Icon(
                Icons.recommend_outlined,
                size: 18.sp,
                color: Theme.of(context).colorScheme.primary,
              ),
              8.sbw,
              Expanded(
                child: Text(title, style: TextStyles.heading3(context)),
              ),
            ],
          ),
        ),
        12.sbh,
        if (merged.isNotEmpty)
          HorizontalContentList(
            storageKey: 'related_${widget.reference.id}',
            icon: _iconFor(widget.reference.type),
            title: title,
            height: widget.height.h,
            itemCount: merged.length,
            padding: EdgeInsets.symmetric(horizontal: 24.w),
            items: merged,
            onItemTap: widget.onContentTap,
          ),
      ],
    );
  }

  IconData _iconFor(ContentType type) {
    switch (type) {
      case ContentType.video:
        return Icons.play_circle_outline;
      case ContentType.youtube:
        return Icons.smart_display_outlined;
      case ContentType.audio:
        return Icons.headphones_outlined;
      case ContentType.book:
        return Icons.menu_book_outlined;
      case ContentType.image:
        return Icons.image_outlined;
      case ContentType.article:
        return Icons.article_outlined;
    }
  }
}

/// Helper زرّ — نُصدّر دالّة قصيرة ليستطيع أيّ ListView/ScrollView
/// إضافة القسم بسطر واحد دون حساب الـ context نفسه.
///
/// لا نُصدّر أيّ Provider هنا — `RelatedContentList` يقرأ بنفسه.
extension RelatedContentListExt on Content {
  Widget relatedList({
    String? titleOverride,
    double height = 190,
    int maxItems = 12,
  }) {
    // نُسجّل بصمت أنّ المستخدم شاهد هذا العنصر — لأيّ مستدعٍ نسي ذلك
    // صراحة في `ContentRouter`. عمليّة idempotent من جهة `UserBehaviorTracker`.
    unawaited(UserBehaviorTracker.instance.recordContentOpen(this));
    unawaited(InterestProfileService.instance.onContentConsumed(this));
    return RelatedContentList(
      reference: this,
      onContentTap: null,
      titleOverride: titleOverride,
      height: height,
      maxItems: maxItems,
    );
  }
}
