import 'dart:math' as math;

import 'package:nebras_mobile_app/core/services/user_behavior_tracker.dart';
import 'package:nebras_mobile_app/core/utils/text_normalizer.dart';
import 'package:nebras_mobile_app/features/content/model/content_model.dart';
import 'package:nebras_mobile_app/features/home/data/home_section_model.dart';

/// RecommendationEngine — محرّك حساب "المحتوى ذي الصلة" للتطبيق كلّه.
///
/// ── كيف يعمل؟ ──
/// عند طلب توصيات لعنصر [reference]، نأخذ **جميع** عناصر المحتوى
/// المُحمَّلة في الأقسام (Firebase + أي مصدر أضيف مسبقًا)، ثم نُعطي لكلّ
/// مرشّح مجموع نقاط مكوّن من:
///   * **السياق** (نفس القسم/الفرعيّ): وزن كبير — المستخدم يريد استكمال
///     ما يقرأه/يسمعه غالبًا.
///   * **النوع**: وزن متوسّط — إن كان يشاهد فيديو، نرجّح الفيديو.
///   * **تطابق الكلمات** (Jaccard): لتقاط المواضيع المشابهة عبر الأقسام.
///   * **وزن الاهتمام** من [UserBehaviorTracker]: إن كان المستخدم زار
///     القسم أو فتح هذا النوع أكثر، نرفع العنصر قليلًا.
///
/// ── لماذا مستقلّة عن [UserBehaviorTracker]؟ ──
/// المتتبّع يحفظ بيانات خام، وهذا المحرّك يُفسّرها. الفصل يتيح اختبار
/// منطق التوصية دون قاعدة بيانات وهميّة، ويسمح أيضًا بتغيير المعادلة
/// لاحقًا دون تغيير التخزين.
class RecommendationEngine {
  RecommendationEngine._();

  /// الحدّ الافتراضيّ لعدد التوصيات المُعادة.
  static const int defaultLimit = 12;

  /// يحسب قائمة مرتّبة من المرشّحين الأفضل.
  ///
  /// [pool] هو الفضاء الذي نستخرج منه المرشّحين — عادةً `HomeProvider.sections`
  /// أو مجموعة عناصر محتوى خاصّة (كقائمة بحث).
  ///
  /// عنصر [reference] يُستثنى تلقائيًّا من النتيجة.
  static List<Content> relatedFor(
    Content reference, {
    required List<HomeSection> pool,
    UserBehaviorTracker? tracker,
    int limit = defaultLimit,
  }) {
    final flat = _flatten(pool, excludeId: reference.id);
    if (flat.isEmpty) return const [];

    final t = tracker ?? UserBehaviorTracker.instance;
    final scored = <_Scored>[];
    for (final c in flat) {
      final score = _score(reference, c, t);
      if (score > 0) scored.add(_Scored(c, score));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(limit).map((e) => e.content).toList(growable: false);
  }

  /// نسخة بديلة: ترتيب مجموعة [candidates] مُعطاة مسبقًا (مثلاً نتائج
  /// بحث) حسب الصلة بـ [reference]. لا تُفلتر بقوّة — ترجع كلّ عنصر
  /// أُدخل إليها مع وزنه.
  static List<Content> rankCandidates(
    Content reference,
    List<Content> candidates, {
    UserBehaviorTracker? tracker,
  }) {
    if (candidates.isEmpty) return const [];
    final t = tracker ?? UserBehaviorTracker.instance;
    final scored = candidates
        .where((c) => c.id != reference.id)
        .map((c) => _Scored(c, _score(reference, c, t)))
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return scored.map((e) => e.content).toList(growable: false);
  }

  /// يستخرج أفضل كلمات مفتاحيّة من العنوان — مفيد لبحث الأرشيف/دار
  /// الإسلام عن "ذات صلة" من الشبكة.
  static List<String> keywordsFrom(Content reference, {int max = 3}) {
    final keys = extractKeywords(reference.title, maxTokens: max + 2);
    if (keys.length <= max) return keys;
    return keys.take(max).toList(growable: false);
  }

  /// توصيات هجينة بنسبة 50/50 — نصفان صريحان:
  ///
  ///   * **Same Category (50%)**: مرشّحون من نفس القسم/الفرعيّ تمامًا
  ///     مرتّبون بتشابه النوع ثمّ بالتداخل الكلماتيّ.
  ///   * **Related Topics (50%)**: مرشّحون من أيّ قسم ولكن بأعلى درجات
  ///     تطابق كلمات مع عنوان [reference] (Jaccard + substring).
  ///
  /// يتمّ تضفير الاثنين على شكل [same, related, same, related, …] حتى
  /// لا يطغى نصف على آخر في واجهة المستخدم. عند نفاد أحد النصفين نملأ
  /// الباقي من الآخر (graceful degradation) كي لا نظهر فجوة للمستخدم.
  ///
  /// [externalPool] اختياريّ لإدخال مرشّحين من خارج `HomeProvider.sections`
  /// المُحمَّلة داخل الشاشة نفسها. إن أتى فارغًا، نعمل على `pool` فقط.
  static List<Content> hybridRelatedFor(
    Content reference, {
    required List<HomeSection> pool,
    List<Content> externalPool = const [],
    UserBehaviorTracker? tracker,
    int limit = defaultLimit,
  }) {
    if (limit <= 0) return const [];

    final flat = _flatten(pool, excludeId: reference.id);
    final extras = externalPool
        .where((c) => c.id.trim().isNotEmpty && c.id != reference.id)
        .toList();

    final all = <Content>[];
    final seen = <String>{reference.id};
    for (final c in [...flat, ...extras]) {
      if (seen.add(c.id)) all.add(c);
    }
    if (all.isEmpty) return const [];

    final t = tracker ?? UserBehaviorTracker.instance;

    // ── 1) نفس القسم/الفرعيّ ──
    final refSection = reference.section.trim();
    final refSub = reference.subSection?.trim();
    final sameBucket = <_Scored>[];
    for (final c in all) {
      final sameSection = refSection.isNotEmpty && c.section == refSection;
      final sameSub = refSub != null &&
          refSub.isNotEmpty &&
          c.subSection != null &&
          c.subSection == refSub;
      if (!sameSection && !sameSub) continue;
      // داخل الـ bucket نُرجّح بتشابه النوع + تداخل الكلمات.
      double s = sameSub ? 2.0 : 1.0;
      if (c.type == reference.type) s += 0.6;
      s += keywordOverlapScore(reference.title, c.title) * 1.5;
      s += math.log(1 + t.typeScore(c.type)) * 0.15;
      sameBucket.add(_Scored(c, s));
    }
    sameBucket.sort((a, b) => b.score.compareTo(a.score));

    // ── 2) كلمات مفتاحيّة متشابهة (أيّ قسم) ──
    final refTitle = reference.title;
    final sameIds = sameBucket.map((e) => e.content.id).toSet();
    final relatedBucket = <_Scored>[];
    for (final c in all) {
      if (sameIds.contains(c.id)) continue; // لا تُكرّر ما في السلة الأولى.
      final overlap = keywordOverlapScore(refTitle, c.title);
      final rel = relevanceScore(refTitle, c.title);
      final combined = overlap * 1.8 + rel * 1.2;
      if (combined <= 0) continue;
      double s = combined;
      if (c.type == reference.type) s += 0.4;
      s += math.log(1 + t.sectionScore(c.section)) * 0.15;
      relatedBucket.add(_Scored(c, s));
    }
    relatedBucket.sort((a, b) => b.score.compareTo(a.score));

    // ── 3) تضفير 50/50 مع تعويض ──
    final halfSame = (limit / 2).ceil();
    final halfRelated = limit - halfSame;
    final pickedSame = sameBucket.take(halfSame).toList();
    final pickedRelated = relatedBucket.take(halfRelated).toList();

    // تعويض: لو نقص أحد النصفين نملأ من الآخر.
    if (pickedSame.length < halfSame) {
      final needed = halfSame - pickedSame.length;
      final already = pickedRelated.map((e) => e.content.id).toSet();
      for (final candidate in relatedBucket.skip(pickedRelated.length)) {
        if (pickedRelated.length + pickedSame.length >= limit) break;
        if (already.add(candidate.content.id)) {
          pickedRelated.add(candidate);
          if (pickedRelated.length >= halfRelated + needed) break;
        }
      }
    }
    if (pickedRelated.length < halfRelated) {
      final needed = halfRelated - pickedRelated.length;
      final already = pickedSame.map((e) => e.content.id).toSet();
      for (final candidate in sameBucket.skip(pickedSame.length)) {
        if (pickedSame.length + pickedRelated.length >= limit) break;
        if (already.add(candidate.content.id)) {
          pickedSame.add(candidate);
          if (pickedSame.length >= halfSame + needed) break;
        }
      }
    }

    // التضفير [same, related, same, related, …].
    final out = <Content>[];
    final addedIds = <String>{};
    final iterLimit = pickedSame.length > pickedRelated.length
        ? pickedSame.length
        : pickedRelated.length;
    for (var i = 0; i < iterLimit && out.length < limit; i++) {
      if (i < pickedSame.length) {
        final c = pickedSame[i].content;
        if (addedIds.add(c.id)) out.add(c);
      }
      if (out.length >= limit) break;
      if (i < pickedRelated.length) {
        final c = pickedRelated[i].content;
        if (addedIds.add(c.id)) out.add(c);
      }
    }
    return _ensureMediaMix(out, all, limit: limit);
  }

  /// واجهة صريحة مطلوبة لشاشات المشغّل: تجلب مقترحات هجينة وتضمن وجود
  /// خليط من الفيديو/الصوت/الكتب عند التوفّر داخل البيانات.
  static List<Content> getRelatedContent(
    Content reference, {
    required List<HomeSection> pool,
    List<Content> externalPool = const [],
    UserBehaviorTracker? tracker,
    int limit = defaultLimit,
  }) {
    return hybridRelatedFor(
      reference,
      pool: pool,
      externalPool: externalPool,
      tracker: tracker,
      limit: limit,
    );
  }

  // ─── internals ────────────────────────────────────────────────

  static double _score(Content ref, Content c, UserBehaviorTracker t) {
    // تطابق السياق — أهمّ إشارة.
    double score = 0.0;
    if (ref.section.trim().isNotEmpty && ref.section == c.section) {
      score += 3.0;
    }
    if (ref.subSection != null && ref.subSection == c.subSection) {
      score += 1.5;
    }
    if (ref.type == c.type) score += 0.7;

    // تشابه الكلمات — يلتقط المواضيع المتشابهة حتّى عبر أقسام مختلفة.
    final overlap = keywordOverlapScore(ref.title, c.title);
    score += overlap * 2.0;

    // تفضيل المستخدم — نُضخّم قليلًا، ليس كثيرًا حتّى لا يُكرّر نفسه.
    final typeBoost = math.log(1 + t.typeScore(c.type)) * 0.3;
    final sectionBoost = math.log(1 + t.sectionScore(c.section)) * 0.25;
    score += typeBoost + sectionBoost;

    return score;
  }

  static List<Content> _flatten(
    List<HomeSection> sections, {
    required String excludeId,
  }) {
    final seen = <String>{excludeId};
    final out = <Content>[];
    for (final s in sections) {
      for (final c in s.items) {
        if (c.id.trim().isEmpty) continue;
        if (seen.add(c.id)) out.add(c);
      }
    }
    return out;
  }

  static List<Content> _ensureMediaMix(
    List<Content> ranked,
    List<Content> sourcePool, {
    required int limit,
  }) {
    if (ranked.isEmpty) return ranked;

    final requiredTypes = <ContentType>{
      ContentType.video,
      ContentType.youtube,
      ContentType.audio,
      ContentType.book,
    };
    final present = ranked.take(limit).map((e) => e.type).toSet();
    final missing = requiredTypes.where((e) => !present.contains(e)).toList();
    if (missing.isEmpty) return ranked.take(limit).toList(growable: false);

    final out = ranked.take(limit).toList();
    final used = out.map((e) => e.id).toSet();

    for (final missingType in missing) {
      Content? candidate;
      for (final c in sourcePool) {
        if (c.type == missingType && !used.contains(c.id)) {
          candidate = c;
          break;
        }
      }
      if (candidate == null) continue;
      if (out.length >= limit) {
        out.removeLast();
      }
      out.add(candidate);
      used.add(candidate.id);
    }
    return out.take(limit).toList(growable: false);
  }
}

class _Scored {
  final Content content;
  final double score;
  const _Scored(this.content, this.score);
}
