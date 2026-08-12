import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nebras_mobile_app/core/services/interest_profile_service.dart';
import 'package:nebras_mobile_app/core/services/user_behavior_tracker.dart';

/// SectionLifecycleTracker — ويدجت غلاف بسيط يُسجّل خروج المستخدم من
/// شاشة قسم في [UserBehaviorTracker]. يعمل بالتكامل مع
/// `recordSectionVisit` الذي يُستدعى عند الدخول (من `SectionRouter`):
///
///   * عند الدخول: `recordSectionVisit` (يضع ميقاتًا داخليًّا).
///   * عند الخروج (dispose): يستدعي `recordSectionExit` الذي يفحص
///     ما إذا قضى المستخدم الحدّ الأدنى من الوقت فيحسب الزيارة
///     "تصفّحًا جدّيًّا".
///
/// **لماذا غلاف بدل إضافة منطق لكلّ شاشة؟**
/// لتجنّب تسريب مسؤوليّة التتبّع إلى كلّ `StatefulWidget`. أيّ شاشة
/// تصفّح (Firebase) تلفّ محتواها بهذا الغلاف فقط.
class SectionLifecycleTracker extends StatefulWidget {
  final String sectionId;
  final String? sectionTitle;
  final Widget child;

  const SectionLifecycleTracker({
    super.key,
    required this.sectionId,
    required this.child,
    this.sectionTitle,
  });

  @override
  State<SectionLifecycleTracker> createState() =>
      _SectionLifecycleTrackerState();
}

class _SectionLifecycleTrackerState extends State<SectionLifecycleTracker> {
  @override
  void initState() {
    super.initState();
    // نُسجّل الزيارة مرّة ثانية هنا كاحتياط — `recordSectionVisit` idempotent
    // (ببساطة يرفع العدّاد)، فلا ضرر، ويفيد عند الوصول لشاشة القسم بطريق
    // لا يمرّ عبر `SectionRouter` (مثلًا من إشعار).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        UserBehaviorTracker.instance.recordSectionVisit(
          widget.sectionId,
          widget.sectionTitle ?? '',
        ),
      );
      unawaited(
        InterestProfileService.instance.onSectionView(
          widget.sectionId,
          widget.sectionTitle ?? '',
        ),
      );
    });
  }

  @override
  void dispose() {
    // Fire-and-forget — نعدّ "تصفّحًا" لو قضى المستخدم زمنًا كافيًا.
    unawaited(UserBehaviorTracker.instance.recordSectionExit(widget.sectionId));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
