import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nebras_mobile_app/core/di/setup_locator.dart';
import 'package:nebras_mobile_app/core/media/content_context.dart';
import 'package:nebras_mobile_app/features/content/model/content_model.dart';
import 'package:nebras_mobile_app/features/content/view/content_router.dart.dart';
import 'package:nebras_mobile_app/features/home/data/home_section_model.dart';
import 'package:nebras_mobile_app/features/home/providers/home_provider.dart';
import 'package:nebras_mobile_app/features/home/view/home_screen.dart';
import 'package:nebras_mobile_app/core/services/section_router.dart';
import 'package:nebras_mobile_app/features/search/domain/usecase/get_section_content_usecase.dart';
import 'package:provider/provider.dart';

/// مُوجِّه الإشعارات
///
/// يوفّر `navigatorKey` عموميّاً يُستخدم في `MaterialApp.navigatorKey`،
/// حتى نستطيع تنفيذ عمليّات التنقّل حتى لو جاء الحدث من خارج شجرة الـ
/// widgets (مثل `FirebaseMessaging.onMessageOpenedApp` أو من isolate آخر
/// أثناء الضغط على إشعار محليّ في الخلفية).
///
/// عند الضغط على إشعار:
///  - إذا كان `type == 'content_added'` وعندنا `contentId` → نبحث داخل
///    HomeProvider عن العنصر ونفتح شاشته الصحيحة عبر [ContentRouter].
///    وإن لم نجده (بيانات لم تصل بعد، أو خارج الصفحة الأولى) نسقط على
///    فتح شاشة القسم الحاوي حتى يعثر المستخدم على المحتوى لحظة وصوله.
///  - إذا كان `type == 'section_created'` وعندنا `sectionId` → نفتح شاشة
///    القسم المناسبة حسب مستواه (main/sub/secondary).
class NotificationNavigator {
  NotificationNavigator._();
  static final NotificationNavigator instance = NotificationNavigator._();

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  /// إذا وصل الإشعار قبل جهوزيّة الـ Navigator (مثلاً عند فتح التطبيق
  /// من حالة مُنهاة) نؤجّل عمليّة الفتح حتى يظهر أوّل إطار.
  void handle(Map<String, dynamic> data) {
    if (data.isEmpty) return;
    unawaited(_handleAsync(data));
  }

  Future<void> _handleAsync(Map<String, dynamic> data) async {
    // ننتظر جهوزيّة الـ Navigator — ضروريّ في حالة الإقلاع من terminated.
    final navigator = await _waitForNavigator();
    if (navigator == null) return;

    final context = navigator.context;
    if (!context.mounted) return;
    final type = (data['type'] ?? '').toString().toLowerCase();

    try {
      if (type == 'section_created') {
        await _openSection(context, data);
      } else {
        // content_added أو أي نوع آخر يحمل contentId
        await _openContent(context, data);
      }
    } catch (e, st) {
      debugPrint('[NotificationNavigator] failed to handle tap: $e\n$st');
    }
  }

  /// يُرجع NavigatorState فور توفّره، أو null إذا مرّت مهلة معقولة دون ظهوره.
  Future<NavigatorState?> _waitForNavigator() async {
    for (var i = 0; i < 40; i++) {
      final state = navigatorKey.currentState;
      if (state != null) return state;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    return navigatorKey.currentState;
  }

  // ── فتح محتوى ──────────────────────────────────────────────
  Future<void> _openContent(
    BuildContext context,
    Map<String, dynamic> data,
  ) async {
    final contentId = (data['contentId'] ?? '').toString().trim();
    if (contentId.isEmpty) {
      // لا معرّف — نفتح القسم الحاوي كخطّة بديلة.
      await _openSection(context, data);
      return;
    }

    // نحاول أوّلاً العثور على العنصر في الـ HomeProvider (live stream).
    final provider = _readHomeProvider(context);
    Content? content = provider?.let(
      (p) => _findContentInProvider(p, contentId),
    );

    // إن وُجد فوراً في الـ provider نفتحه مباشرة (أدقّ نسخة — تحمل اسم
    // القسم والوصف الكاملين).
    if (content != null) {
      if (!context.mounted) return;
      await ContentRouter.open(
        context,
        content,
        contentContext: ContentContext.direct,
      );
      return;
    }

    // لم نجده في الـ provider بعد. إذا حملت حمولة الإشعار رابط مصدر صالحاً
    // نبني منها كائن Content ونفتحه **فوراً** — هذا يضمن أنّ الضغط على أيّ
    // إشعار محتوى ينقل المستخدم إلى المحتوى مباشرة دون انتظار وصول لقطة
    // Firestore تحتوي العنصر (التي قد تتأخّر أو لا يكون العنصر ضمن الصفحة
    // الأولى أصلاً، فكان الضغط سابقاً لا يفعل شيئاً).
    final fromPayload = _contentFromNotificationData(data, contentId);
    if (fromPayload != null) {
      if (!context.mounted) return;
      await ContentRouter.open(
        context,
        fromPayload,
        contentContext: ContentContext.direct,
      );
      return;
    }

    // لا رابط في الحمولة — ننتظر دفعة أو دفعتين من الـ stream (قد يكون
    // التطبيق لحظة تلقّي الإشعار لم يستلم بعد snapshot يحتوي العنصر).
    if (provider != null) {
      content = await _waitForContent(provider, contentId);
    }

    // وكخطّة أخيرة، نقرأ مباشرة من قسم محدّد عبر الـ use case.
    content ??= await _fetchContentFromSections(data, contentId);

    if (content != null) {
      if (!context.mounted) return;
      await ContentRouter.open(
        context,
        content,
        contentContext: ContentContext.direct,
      );
      return;
    }

    // لم نعثر عليه — نفتح القسم الحاوي حتى يجده المستخدم يدويّاً.
    if (!context.mounted) return;
    await _openSection(context, data);
  }

  /// يبني كائن [Content] من حمولة الإشعار الخام عند تعذّر إيجاد العنصر في
  /// الـ HomeProvider. يعتمد على [Content.fromJson] الذي يستنبط النوع من
  /// امتداد الرابط (mp3/pdf/youtube…)، فيكفي وجود رابط مصدر صالح حتى يفتح
  /// المحتوى مباشرة. يُرجع null إذا لم تحمل الحمولة رابطاً قابلاً للتشغيل
  /// (عندها نتراجع إلى انتظار الـ stream أو فتح القسم).
  Content? _contentFromNotificationData(
    Map<String, dynamic> data,
    String contentId,
  ) {
    final sourceUrl = _firstNonEmpty([
      data['sourceUrl'],
      data['video_url'],
      data['file_url'],
      data['audio_url'],
      data['youtube_url'],
      data['url'],
    ]);
    if (sourceUrl == null) return null;

    final content = Content.fromJson(<String, dynamic>{
      'id': contentId,
      'title': (data['title'] ?? '').toString(),
      'description': (data['body'] ?? data['description'] ?? '').toString(),
      'content_type': (data['type'] ?? '').toString(),
      'sourceUrl': sourceUrl,
      'thumbnail':
          (data['thumbnail'] ?? data['thumbnailUrl'] ?? '').toString(),
      'subsection':
          (data['subSectionId'] ?? data['sectionId'] ?? '').toString(),
      'secondary_subsection': (data['secondarySectionId'] ?? '').toString(),
    });

    // حارس: لا نُرجع كائناً بلا مصدر صالح (يطابق منطق ContentRouter).
    if ((content.sourceUrl ?? '').trim().isEmpty) return null;
    return content;
  }

  String? _firstNonEmpty(Iterable<dynamic> values) {
    for (final v in values) {
      final s = (v ?? '').toString().trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }

  Content? _findContentInProvider(HomeProvider provider, String contentId) {
    for (final section in provider.sections) {
      for (final item in section.items) {
        if (item.id == contentId) return item;
      }
    }
    return null;
  }

  Future<Content?> _waitForContent(
    HomeProvider provider,
    String contentId,
  ) async {
    for (var i = 0; i < 20; i++) {
      final c = _findContentInProvider(provider, contentId);
      if (c != null) return c;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return null;
  }

  Future<Content?> _fetchContentFromSections(
    Map<String, dynamic> data,
    String contentId,
  ) async {
    final candidates = <String>[
      (data['secondarySectionId'] ?? '').toString(),
      (data['subSectionId'] ?? '').toString(),
      (data['mainSectionId'] ?? '').toString(),
    ].where((s) => s.trim().isNotEmpty).toList();

    if (candidates.isEmpty) return null;
    try {
      final useCase = locator<GetSectionContentUseCase>();
      for (final sectionId in candidates) {
        final list = await useCase(sectionId);
        for (final item in list) {
          if (item.id == contentId) return item;
        }
      }
    } catch (e) {
      debugPrint('[NotificationNavigator] fetchContentFromSections: $e');
    }
    return null;
  }

  // ── فتح قسم ────────────────────────────────────────────────
  Future<void> _openSection(
    BuildContext context,
    Map<String, dynamic> data,
  ) async {
    final secondaryId = (data['secondarySectionId'] ?? '').toString().trim();
    final subId = (data['subSectionId'] ?? '').toString().trim();
    final mainId = (data['mainSectionId'] ?? '').toString().trim();
    final sectionId = (data['sectionId'] ?? '').toString().trim();
    final level = (data['level'] ?? '').toString().toLowerCase();

    // نُرجّح الأعمق فالأعمّ: ثانوي → فرعيّ → رئيسيّ → sectionId عام.
    String targetId = '';
    String targetLevel = '';
    if (secondaryId.isNotEmpty) {
      targetId = secondaryId;
      targetLevel = 'secondary';
    } else if (subId.isNotEmpty) {
      targetId = subId;
      targetLevel = 'sub';
    } else if (mainId.isNotEmpty) {
      targetId = mainId;
      targetLevel = 'main';
    } else if (sectionId.isNotEmpty) {
      targetId = sectionId;
      targetLevel = level;
    }

    if (targetId.isEmpty) return;

    // ننتظر دفعة HomeProvider حتى نعرف نوع القسم إن لم يُحدَّد صراحة.
    final provider = _readHomeProvider(context);
    HomeSection? section;
    if (provider != null) {
      section = await _waitForSection(provider, targetId);
      if (section != null && targetLevel.isEmpty) {
        targetLevel = _levelForType(section.type);
      }
    }

    if (!context.mounted) return;

    if (section != null) {
      await SectionRouter.open(context, section);
      return;
    }

    final navigator = Navigator.of(context);
    switch (targetLevel) {
      case 'main':
      case 'main_section':
        navigator.push(
          MaterialPageRoute(
            builder: (_) => SubSectionsScreen(mainSectionId: targetId),
          ),
        );
        break;
      case 'sub':
      case 'sub_section':
        navigator.push(
          MaterialPageRoute(
            builder: (_) => SecondarySectionsScreen(subSectionId: targetId),
          ),
        );
        break;
      case 'secondary':
      case 'secondary_section':
      default:
        navigator.push(
          MaterialPageRoute(
            builder: (_) => ContentListScreen(sectionId: targetId),
          ),
        );
    }
  }

  Future<HomeSection?> _waitForSection(
    HomeProvider provider,
    String id,
  ) async {
    for (var i = 0; i < 20; i++) {
      try {
        final s = provider.sections.firstWhere((s) => s.id == id);
        return s;
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return null;
  }

  String _levelForType(String type) {
    switch (type) {
      case 'main_section':
        return 'main';
      case 'sub_section':
        return 'sub';
      case 'secondary_section':
        return 'secondary';
      default:
        return '';
    }
  }

  HomeProvider? _readHomeProvider(BuildContext context) {
    try {
      return Provider.of<HomeProvider>(context, listen: false);
    } catch (_) {
      return null;
    }
  }
}

extension _Let<T extends Object> on T {
  R let<R>(R Function(T it) block) => block(this);
}
