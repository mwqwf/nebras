import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nebras_mobile_app/core/extensions/navigation_extension.dart';
import 'package:nebras_mobile_app/core/services/interest_profile_service.dart';
import 'package:nebras_mobile_app/core/services/user_behavior_tracker.dart';
import 'package:nebras_mobile_app/features/content/model/content_model.dart';
import 'package:nebras_mobile_app/features/home/data/home_section_model.dart';
import 'package:nebras_mobile_app/features/home/providers/home_provider.dart';
import 'package:nebras_mobile_app/features/home/view/home_screen.dart';
import 'package:provider/provider.dart';

/// SectionRouter — توجيه موحَّد لفتح قسم بغضّ النظر عن مصدره. هذا هو **المدخل الوحيد** الذي يعرف
/// قواعد التفرّع، فيمنع تكرارها في كلّ شاشة تسرد أقسامًا (الصفحة
/// الرئيسيّة، البحث، "لك").
///
/// التفرّع:
///   3) **Firebase**: `main_section` → [SubSectionsScreen]،
///      `sub_section` → [SecondarySectionsScreen]، وإلّا
///      [ContentListScreen].
///
/// **ملاحظة تصميم**: تسجيل الزيارة في [UserBehaviorTracker] يحصل هنا
/// مركزيًّا كي يعمل لجميع مصادر التنقّل (لا فقط من الصفحة الرئيسيّة).
class SectionRouter {
  const SectionRouter._();

  /// يفتح القسم المناسب. آمن للاستدعاء من أيّ شاشة طالما أن `context`
  /// يحوي `HomeProvider` فوقه في شجرة Providers (وهو موفَّر على مستوى
  /// الجذر في `main.dart`). لو لم يُعثر على `HomeProvider` نتعامل مع
  /// ذلك كـ Firebase-only ونفترض أن القسم من Firebase.
  static Future<void> open(BuildContext context, HomeSection section) async {
    unawaited(
      UserBehaviorTracker.instance.recordSectionVisit(section.id, section.title),
    );
    // طبقة محرك التوصيات المستقلّة: +1 لأفنيتي القسم والكلمات المفتاحيّة
    // لعنوانه. لا يلمس حالة UserBehaviorTracker ولا يغيّر سلوك التنقّل.
    unawaited(
      InterestProfileService.instance.onSectionView(section.id, section.title),
    );

    HomeProvider? provider;
    try {
      provider = context.read<HomeProvider>();
    } catch (_) {
      provider = null;
    }

    // 3) Firebase — السلوك الأصليّ بحسب نوع القسم.
    if (!context.mounted) return;
    if (section.type == 'main_section') {
      // اختصار ذكي: قسم رئيسي بلا أبناء لكن مع عناصر محتوًى مباشرة → قائمة المحتوى.
      final hasSubs = provider?.sections.any(
            (s) => s.type == 'sub_section' && s.parentId == section.id,
          ) ??
          false;
      if (!hasSubs && section.items.isNotEmpty) {
        context.push(ContentListScreen(sectionId: section.id));
        return;
      }
      context.push(SubSectionsScreen(mainSectionId: section.id));
    } else if (section.type == 'sub_section') {
      // قسم فرعي بلا ثانويّات لكن مع محتوًى مباشر → قائمة المحتوى.
      final hasSecs = provider?.sections.any(
            (s) =>
                (s.type == 'secondary_section' ||
                    s.type == 'secondary_sub_section') &&
                s.parentId == section.id,
          ) ??
          false;
      if (!hasSecs && section.items.isNotEmpty) {
        context.push(ContentListScreen(sectionId: section.id));
        return;
      }
      context.push(SecondarySectionsScreen(subSectionId: section.id));
    } else {
      context.push(ContentListScreen(sectionId: section.id));
    }
  }

  /// يحلّ القسم الأوراق (الأكثر تحديداً) الذي ينتمي إليه [content] من
  /// شجرة [HomeProvider]. يُرجَّح القسم الثانويّ إن وُجد، وإلّا القسم
  /// الفرعيّ. يُرجِع `null` إن تعذّر الحلّ (محتوى لم يصل بعد، أو لا provider).
  static HomeSection? resolveLeafSection(
    BuildContext context,
    Content content,
  ) {
    HomeProvider? provider;
    try {
      provider = context.read<HomeProvider>();
    } catch (_) {
      return null;
    }
    final sections = provider.sections;
    HomeSection? byId(String id) {
      for (final s in sections) {
        if (s.id == id) return s;
      }
      return null;
    }

    final secId = content.subSection?.trim() ?? '';
    final subId = content.section.trim();
    HomeSection? leaf;
    if (secId.isNotEmpty) leaf = byId('secondary:$secId');
    leaf ??= (subId.isNotEmpty ? byId('sub:$subId') : null);
    return leaf;
  }

  /// يفتح القسم الذي ينتمي إليه [content] مع **مسار صعود كامل** في مكدّس
  /// التنقّل: عند الضغط على «رجوع» يصعد المستخدم تدريجيّاً
  /// (محتوى القسم → الأقسام الثانويّة → الأقسام الفرعيّة → الرئيسيّة)
  /// بدل القفز مباشرةً للخلف. هذا هو سلوك «زرّ القسم» في شاشات المحتوى.
  static Future<void> openContentTrail(
    BuildContext context,
    Content content,
  ) async {
    HomeProvider? provider;
    try {
      provider = context.read<HomeProvider>();
    } catch (_) {
      return;
    }
    final leaf = resolveLeafSection(context, content);
    if (leaf == null) return;

    final sections = provider.sections;
    HomeSection? byId(String id) {
      for (final s in sections) {
        if (s.id == id) return s;
      }
      return null;
    }

    // بناء سلسلة الأجداد من الورقة صعوداً إلى الجذر (الرئيسيّ).
    final chain = <HomeSection>[];
    final guard = <String>{};
    HomeSection? cur = leaf;
    while (cur != null && guard.add(cur.id)) {
      chain.add(cur);
      final pid = cur.parentId;
      cur = (pid == null || pid.isEmpty) ? null : byId(pid);
    }
    // من الجذر إلى الورقة كي يُبنى المكدّس بالترتيب الصحيح للصعود.
    final ordered = chain.reversed.toList(growable: false);

    unawaited(
      UserBehaviorTracker.instance.recordSectionVisit(leaf.id, leaf.title),
    );
    unawaited(
      InterestProfileService.instance.onSectionView(leaf.id, leaf.title),
    );

    if (!context.mounted) return;
    final navigator = Navigator.of(context);
    // نُعيد المكدّس إلى الجذر (الرئيسيّة) قبل بناء مسار الأقسام، حتى يصعد
    // المستخدم بزرّ «رجوع» من قائمة المحتوى إلى الأقسام ثمّ إلى الرئيسيّة
    // مباشرةً، دون المرور بشاشة المحتوى التي انطلق منها.
    navigator.popUntil((route) => route.isFirst);
    for (final s in ordered) {
      final isLeaf = s.id == leaf.id;
      Widget screen;
      if (isLeaf) {
        // الورقة دائماً قائمة محتوى — سواء كانت قسماً فرعيّاً يحوي محتوًى
        // مباشراً أو قسماً ثانويّاً.
        screen = ContentListScreen(sectionId: s.id);
      } else if (s.type == 'main_section') {
        screen = SubSectionsScreen(mainSectionId: s.id);
      } else {
        // قسم فرعيّ وسيط → قائمة الأقسام الثانويّة تحته.
        screen = SecondarySectionsScreen(subSectionId: s.id);
      }
      navigator.push(MaterialPageRoute(builder: (_) => screen));
    }
  }
}
