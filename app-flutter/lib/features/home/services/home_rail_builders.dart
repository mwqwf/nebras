import 'package:easy_localization/easy_localization.dart';
import 'package:nebras_mobile_app/core/data/content_ordering.dart';
import 'package:nebras_mobile_app/core/services/continue_watching_service.dart';
import 'package:nebras_mobile_app/core/services/interest_profile_service.dart';
import 'package:nebras_mobile_app/core/services/recommendation_service.dart';
import 'package:nebras_mobile_app/core/utils/text_normalizer.dart';
import 'package:nebras_mobile_app/features/content/model/content_model.dart';
import 'package:nebras_mobile_app/features/home/data/home_section_model.dart';
import 'package:nebras_mobile_app/features/home/model/home_rail.dart';

/// يبني رفوف الصفحة الرئيسيّة من المحتوى والأقسام المحمّلة.
///
/// **مهم:** ترتيب العناصر *داخل* أيّ قسم Firestore يبقى عبر
/// [compareContentOldestFirst] — الرفوف هنا تستخدم `createdAt` تنازلياً
/// أو درجات الشعبيّة فقط لعرض الاكتشاف في الصفحة الرئيسيّة.
class HomeRailBuilders {
  HomeRailBuilders._();

  static const int _railLimit = 12;

  static List<Content> allContentFlat(Iterable<HomeSection> sections) {
    final byId = <String, Content>{};
    for (final s in sections) {
      for (final item in s.items) {
        byId[item.id] = item;
      }
    }
    return byId.values.toList();
  }

  static List<Content> buildNewestRail(List<Content> pool, {int limit = _railLimit}) {
    final copy = List<Content>.of(pool)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return copy.take(limit).toList(growable: false);
  }

  static List<Content> buildPopularRail(
    List<Content> pool, {
    List<String> popularIds = const [],
    int limit = _railLimit,
  }) {
    if (popularIds.isNotEmpty) {
      final byId = {for (final c in pool) c.id: c};
      final ordered = <Content>[];
      for (final id in popularIds) {
        final c = byId[id];
        if (c != null) ordered.add(c);
        if (ordered.length >= limit) break;
      }
      if (ordered.isNotEmpty) return ordered;
    }
    final copy = List<Content>.of(pool)
      ..sort((a, b) => b.viewCount.compareTo(a.viewCount));
    return copy.take(limit).toList(growable: false);
  }

  static List<Content> buildForYouRail(
    List<Content> pool, {
    Set<String> excludeIds = const {},
    int limit = _railLimit,
  }) {
    final filtered = pool.where((c) => !excludeIds.contains(c.id));
    final ranked = RecommendationService.instance.rank(
      filtered,
      discoveryPercent: 15,
    );
    return ranked.take(limit).toList(growable: false);
  }

  static ({List<Content> items, String? subtitle}) buildSearchAffinityRail(
    List<Content> pool, {
    Set<String> excludeIds = const {},
    int limit = _railLimit,
  }) {
    final profile = InterestProfileService.instance;
    final keywords = profile.topKeywords(limit: 5);
    if (keywords.isEmpty) {
      return (items: const <Content>[], subtitle: null);
    }

    final scored = <({Content c, double score})>[];
    for (final item in pool) {
      if (excludeIds.contains(item.id)) continue;
      final titleKeys = extractKeywords(item.title, maxTokens: 12);
      final descKeys = extractKeywords(item.description, maxTokens: 8);
      var score = 0.0;
      for (final k in keywords) {
        if (titleKeys.contains(k)) score += profile.keywordAffinity(k) * 2;
        if (descKeys.contains(k)) score += profile.keywordAffinity(k);
      }
      if (score > 0) scored.add((c: item, score: score));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    final items = scored.map((e) => e.c).take(limit).toList(growable: false);
    final subtitle = keywords.length >= 2
        ? '${keywords[0]}، ${keywords[1]}'
        : keywords.first;
    return (items: items, subtitle: subtitle);
  }

  static Future<List<Content>> buildContinueRail(
    List<Content> pool, {
    int limit = _railLimit,
  }) async {
    final entries = await ContinueWatchingService.instance.activeEntries();
    if (entries.isEmpty) return const [];
    final byId = {for (final c in pool) c.id: c};
    final out = <Content>[];
    for (final e in entries) {
      final c = byId[e.contentId];
      if (c != null) out.add(c);
      if (out.length >= limit) break;
    }
    return out;
  }

  static Set<String> idsOf(Iterable<Content> items) =>
      items.map((c) => c.id).toSet();

  /// يبني الرفوف بالترتيب المحدّد في الوثائق.
  ///
  /// [personalized] : عندما تكون `false` (مستخدم ضيف بلا حساب حقيقيّ) لا
  /// نبني أيّ رفّ يعتمد على سلوك المستخدم (لك / من اهتماماتك / تابع
  /// التصفّح). الضيف يرى فقط الأحدث والأكثر مشاهدة — التطبيق لا يُكوّن له
  /// أيّ ملفّ اهتمامات. التخصيص الكامل محجوز لأصحاب الحسابات.
  static Future<List<HomeRail>> buildAll({
    required List<HomeSection> sections,
    required List<HomeSection> rankedSections,
    List<String> popularIds = const [],
    bool personalized = false,
  }) async {
    final pool = allContentFlat(sections);
    final rails = <HomeRail>[];

    final newest = buildNewestRail(pool);
    rails.add(
      HomeRail(
        type: HomeRailType.newest,
        title: 'home_rail_newest'.tr(),
        items: newest,
      ),
    );

    final popular = buildPopularRail(pool, popularIds: popularIds);
    if (popular.isNotEmpty) {
      rails.add(
        HomeRail(
          type: HomeRailType.popular,
          title: 'home_rail_popular'.tr(),
          items: popular,
        ),
      );
    }

    // الرفوف الشخصيّة محجوزة لأصحاب الحسابات فقط.
    if (!personalized) {
      return rails;
    }

    final excludeForLater = idsOf(newest)..addAll(idsOf(popular));

    final profile = InterestProfileService.instance;
    if (profile.isLoaded && profile.hasSignals) {
      final forYou = buildForYouRail(
        pool,
        excludeIds: excludeForLater,
      );
      if (forYou.isNotEmpty) {
        rails.add(
          HomeRail(
            type: HomeRailType.forYou,
            title: 'home_rail_for_you'.tr(),
            items: forYou,
          ),
        );
        excludeForLater.addAll(idsOf(forYou));
      }
    }

    final searchResult = buildSearchAffinityRail(
      pool,
      excludeIds: excludeForLater,
    );
    if (searchResult.items.isNotEmpty) {
      final title = searchResult.subtitle != null
          ? '${'home_rail_search_prefix'.tr()}: ${searchResult.subtitle}'
          : 'home_rail_search'.tr();
      rails.add(
        HomeRail(
          type: HomeRailType.searchAffinity,
          title: title,
          items: searchResult.items,
        ),
      );
      excludeForLater.addAll(idsOf(searchResult.items));
    }

    final continueItems = await buildContinueRail(pool);
    if (continueItems.isNotEmpty) {
      rails.add(
        HomeRail(
          type: HomeRailType.continueWatching,
          title: 'home_rail_continue'.tr(),
          items: continueItems,
        ),
      );
    }

    // رفّ «تصفّح الأقسام» السفليّ أُزيل عمداً — التنقّل بين الأقسام يتمّ
    // الآن هرميّاً انطلاقاً من المحتوى (زرّ القسم) لا من شبكة سفليّة.

    return rails;
  }
}
