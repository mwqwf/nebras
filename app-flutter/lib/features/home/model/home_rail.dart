import 'package:nebras_mobile_app/features/content/model/content_model.dart';

/// نوع رفّ الصفحة الرئيسيّة — **ليس** قسم Firestore.
///
/// الرفوف عروض مشتقّة من المحتوى المحمّل + الإشارات المحليّة.
/// راجع [HOME_RAILS_ARCHITECTURE.md] و [docs/CONTENT_ORDERING_AND_HOME.md].
enum HomeRailType {
  /// أحدث 12 عنصراً عبر كلّ نبراس (`createdAt` تنازلي).
  newest,

  /// الأكثر شعبية — من `aggregates_popular/top_weekly` أو `view_count`.
  popular,

  /// مقترَح لك — [RecommendationService] بعد بناء ملفّ اهتمام.
  forYou,

  /// من كلمات بحثك/اهتماماتك — يُخفى للمستخدم الجديد.
  searchAffinity,

  /// تابع المشاهدة/القراءة — [ContinueWatchingService] محلّي فقط.
  continueWatching,

  /// تصفّح الأقسام — بطاقات أقسام رئيسية مرتّبة ذكياً.
  browseSections,
}

/// رفّ أفقيّ واحد في الصفحة الرئيسيّة.
class HomeRail {
  final HomeRailType type;
  final String title;
  final String? subtitle;
  final List<Content> items;
  final List<HomeRailSectionRef> sectionRefs;

  const HomeRail({
    required this.type,
    required this.title,
    this.subtitle,
    this.items = const [],
    this.sectionRefs = const [],
  });

  bool get isEmpty =>
      type == HomeRailType.browseSections
          ? sectionRefs.isEmpty
          : items.isEmpty;
}

/// مرجع قسم لرفّ «تصفّح الأقسام».
class HomeRailSectionRef {
  final String id;
  final String title;
  final String? imageUrl;

  const HomeRailSectionRef({
    required this.id,
    required this.title,
    this.imageUrl,
  });
}
