import 'dart:math' as math;

import 'package:nebras_mobile_app/core/services/interest_profile_service.dart';
import 'package:nebras_mobile_app/features/content/model/content_model.dart';

/// RecommendationService — **طبقة الفرز الذكيّة** لصفحة "لك".
///
/// نقطة الدخول الوحيدة من صفحة "لك" هي [rank]. الخدمة بلا حالة تقريبًا
/// (تقرأ من [InterestProfileService] كمنبع حقيقة) وبلا شبكة — فهي
/// مجرّد محوِّل رياضيّ يرتّب قائمة محتوى مُعطاة.
///
/// ── الفكرة الأساسيّة ──
/// لكلّ عنصر محتوى نحسب:
///   score = contentAffinity(content) + jitter
///
/// ثمّ نرتّب تنازليًّا، ونحجز نسبة **Discovery** (افتراضيًّا 15%)
/// للعناصر ذات الأفنيتي المنخفض أو الصفر — كي لا يُحبس المستخدم
/// في فقاعة اهتماماته ويُتاح له استكشاف مواضيع جديدة.
///
/// ── لماذا طبقة مستقلّة؟ ──
/// - تبقى دوال الترتيب خالصة (Pure) وسهلة الاختبار.
/// - يمكن إعادة استعمالها لاحقًا في «مقترحات أسفل المشغّل» و«اكتشف
///   المزيد» دون تكرار الكود.
/// - لا تمسّ `ForYouProvider` بمنطقها السابق؛ نُغلّف الإخراج فقط.
class RecommendationService {
  RecommendationService._();

  /// المثيل العامّ — ثابت وبلا حالة داخليّة.
  static final RecommendationService instance = RecommendationService._();

  /// الحدّ الأدنى لحجم القائمة الذي تستحقّ معه تطبيق منطق Discovery.
  /// تحت هذا الحدّ (< 10 عناصر) نعيد القائمة مرتّبة فقط — لأنّ إقحام
  /// «عشوائيّ» في خلاصة قصيرة يبدو كخلل وليس كاكتشاف.
  static const int _discoveryMinPool = 10;

  /// يرتّب [pool] تنازليًّا وفق أفنيتي المستخدم في
  /// [InterestProfileService]، مع حجز نسبة [discoveryPercent] للمحتوى
  /// الاستكشافيّ (العناصر التي لم يلامسها رصيد المستخدم بعد).
  ///
  /// * [seed]: لتثبيت الـ jitter خلال عرض واحد وتجنّب اهتزاز الترتيب
  ///   بين إعادات البناء. عندما يُستدعى الخلط يُمرّر seed جديد.
  ///
  /// **ضمانات**:
  ///   - إن كان ملفّ الاهتمامات فارغًا، تُعاد القائمة كما هي (الترتيب
  ///     الحاليّ من [ForYouProvider] يُحترم بالكامل) — أيّ كسر هنا
  ///     يعني كسر فوريّ للبناء السابق.
  ///   - لا يُكرَّر عنصر.
  ///   - حجم القائمة المُعادة == حجم المدخَل تمامًا.
  List<Content> rank(
    Iterable<Content> pool, {
    int discoveryPercent = 15,
    int? seed,
  }) {
    final items = pool.toList(growable: false);
    if (items.isEmpty) return const <Content>[];

    // السلوك الآمن: لو الخدمة لم تُحمَّل أو ملفّ فارغ ⇒ لا نُعِد ترتيب
    // القائمة (نحافظ على مخرج `ForYouProvider._rebuild` كما هو).
    final profile = InterestProfileService.instance;
    if (!profile.isLoaded || !profile.hasSignals) {
      // Cold start: مزيج أحدث + شعبي — لا صفحة فارغة (راجع docs/CONTENT_ORDERING_AND_HOME.md).
      return _coldStartFeed(items);
    }

    final rng = math.Random(seed ?? DateTime.now().millisecondsSinceEpoch);

    // 1) احسب درجة كلّ عنصر.
    final scored = items.map((c) {
      double base = profile.contentAffinity(c).toDouble();

      // jitter صغير نسبة إلى الدرجة ذاتها كي لا يُهمّش العناصر العالية.
      final jitter = rng.nextDouble() * (base < 1 ? 0.5 : base * 0.05);
      return _Scored(c, base + jitter, base);
    }).toList();

    // 2) افصل Discovery (أفنيتي <= 0) عن العناصر المُشخصَنة.
    final personalized = <_Scored>[];
    final discovery = <_Scored>[];
    for (final e in scored) {
      if (e.baseScore <= 0) {
        discovery.add(e);
      } else {
        personalized.add(e);
      }
    }
    personalized.sort((a, b) => b.score.compareTo(a.score));
    discovery.shuffle(rng);

    // 3) لو القائمة قصيرة جدًا أو لا يوجد Discovery متاح، أعد المُشخصَن
    //    متبوعًا بالبقيّة دون إقحام (يحفظ راحة البصر).
    if (items.length < _discoveryMinPool ||
        discovery.isEmpty ||
        personalized.isEmpty) {
      return [
        ...personalized.map((e) => e.content),
        ...discovery.map((e) => e.content),
      ];
    }

    // 4) احجز نسبة Discovery من الحجم الكلّيّ (بحدّ أدنى 1 وأقصى عدد
    //    Discovery المتاح). نستخدم النسبة على الحجم الكامل لضمان تأثير
    //    مرئيّ حتى لو كانت الخلاصة كبيرة.
    final cappedPct = discoveryPercent.clamp(0, 50);
    final discoveryQuota = ((items.length * cappedPct) / 100)
        .round()
        .clamp(1, discovery.length);

    // 5) إدراج Discovery على فواصل منتظمة. نترك أوّل موضع دائمًا
    //    لعنصر مُشخصَن (أعلى درجة) كي يشعر المستخدم أنّ الصفحة تتكلّم
    //    معه منذ السطر الأوّل.
    final stride = math.max(3, (items.length / (discoveryQuota + 1)).floor());
    final output = <Content>[];
    int pIdx = 0;
    int dIdx = 0;
    for (int i = 0; i < items.length; i++) {
      final isDiscoverySlot =
          i > 0 && i % stride == 0 && dIdx < discoveryQuota;
      if (isDiscoverySlot && dIdx < discovery.length) {
        output.add(discovery[dIdx++].content);
      } else if (pIdx < personalized.length) {
        output.add(personalized[pIdx++].content);
      } else if (dIdx < discovery.length) {
        // نفد المحتوى المُشخصَن — أكمل من Discovery.
        output.add(discovery[dIdx++].content);
      }
    }

    // 6) أيّ فائض (نادر لو اختلّت الحسابات) يُلحق بالذيل دون تكرار.
    if (output.length < items.length) {
      final seen = <String>{for (final c in output) c.id};
      while (pIdx < personalized.length) {
        final c = personalized[pIdx++].content;
        if (seen.add(c.id)) output.add(c);
      }
      while (dIdx < discovery.length) {
        final c = discovery[dIdx++].content;
        if (seen.add(c.id)) output.add(c);
      }
    }

    return output;
  }

  /// مستخدم جديد: 50% أحدث + 50% الأكثر مشاهدة/شعبيّة محلياً.
  static List<Content> _coldStartFeed(List<Content> items) {
    if (items.isEmpty) return const <Content>[];
    final newest = List<Content>.of(items)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final popular = List<Content>.of(items)
      ..sort((a, b) {
        final byViews = b.viewCount.compareTo(a.viewCount);
        if (byViews != 0) return byViews;
        return b.createdAt.compareTo(a.createdAt);
      });
    final half = (items.length / 2).ceil().clamp(1, items.length);
    final seen = <String>{};
    final out = <Content>[];
    var ni = 0;
    var pi = 0;
    while (out.length < items.length && (ni < newest.length || pi < popular.length)) {
      if (out.length.isEven && ni < newest.length) {
        final c = newest[ni++];
        if (seen.add(c.id)) out.add(c);
      } else if (pi < popular.length) {
        final c = popular[pi++];
        if (seen.add(c.id)) out.add(c);
      } else if (ni < newest.length) {
        final c = newest[ni++];
        if (seen.add(c.id)) out.add(c);
      } else {
        break;
      }
      if (out.length >= half * 2) break;
    }
    for (final c in newest.followedBy(popular)) {
      if (out.length >= items.length) break;
      if (seen.add(c.id)) out.add(c);
    }
    return out;
  }

  /// تقرير مختصر — **للتصحيح فقط**. مفيد لمشاهدة توزّع الأفنيتي عبر
  /// قائمة المحتوى المعروضة في "لك" أثناء تجريب الميزة.
  Map<String, int> describe(Iterable<Content> pool) {
    final profile = InterestProfileService.instance;
    int personalized = 0;
    int discovery = 0;
    int totalAffinity = 0;
    for (final c in pool) {
      final a = profile.contentAffinity(c);
      totalAffinity += a;
      if (a > 0) {
        personalized++;
      } else {
        discovery++;
      }
    }
    return {
      'personalized': personalized,
      'discovery': discovery,
      'totalAffinity': totalAffinity,
    };
  }
}

class _Scored {
  final Content content;
  final double score;
  final double baseScore;
  const _Scored(this.content, this.score, this.baseScore);
}
