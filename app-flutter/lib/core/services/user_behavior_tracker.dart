import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nebras_mobile_app/core/utils/text_normalizer.dart';
import 'package:nebras_mobile_app/features/content/model/content_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// UserBehaviorTracker — **الملف الشخصي السلوكيّ للمستخدم** (Global).
///
/// ── الفلسفة ──
/// بنية بسيطة وصامتة تسجّل ثلاثة تدفّقات مستقلّة:
///   1) **زيارات الأقسام** (Section Visits): كل ضغط على قسم يزيد عدّاد الـ
///      `sectionId` ويستخرج الكلمات المفتاحيّة من عنوانه.
///   2) **فتحات المحتوى** (Content Opens): كلّ فتح لعنصر يزيد عدّاد نوعه
///      وقسمه ويستخرج كلمات عنوانه/وصفه.
///   3) **استعلامات البحث** (Search Queries): كلّ بحث يُغذّي سجلّ
///      الكلمات المفتاحيّة مباشرة (كما هي، مع تطبيع عربيّ).
///
/// ── لماذا خدمة واحدة عامّة؟ ──
/// في التطبيق مكوّنات عدّة تحتاج القراءة من نفس النموذج (ترتيب الصفحة
/// الرئيسية، توصيات "لك"، قائمة "ذات صلة" أسفل المشغّلات، البحث الذكيّ،
/// الإحصاءات). خدمة واحدة كمنبع حقيقة تجنّبنا ثلاث مشاكل:
///   * تكرار الكتابة على `SharedPreferences`.
///   * انقسام المفاتيح المُخزَّنة (تضارب بين `InteractionTracker`
///     و `InterestStore` و أي مخزن جديد).
///   * انحراف التطبيع النصّيّ العربيّ بين الأماكن.
///
/// ── العزل ──
/// * لا يعرف بشبكة ولا بـ Firebase — مجرّد `SharedPreferences`.
/// * سنجة (Singleton) ثابتة كي يستطيع أيّ Mixin/Widget استدعاؤه بلا
///   `context.read` عندما يكون السياق غير مناسب (مثل `ContentRouter`
///   وهو دالّة ثابتة).
///
/// ── التزامن ──
/// يمتدّ من [ChangeNotifier] فيمكن حقنه عبر `Provider` لمن يرغب بإعادة
/// بناء UI عند تغيّر الاهتمامات. لكنّه يعمل بدون Provider أيضًا بسبب
/// الـ singleton الثابت.
class UserBehaviorTracker extends ChangeNotifier {
  UserBehaviorTracker._();

  /// المثيل العامّ — يجب دائمًا استخدامه. لا تُنشئ مثيلًا جديدًا.
  static final UserBehaviorTracker instance = UserBehaviorTracker._();

  // ── مفاتيح التخزين ───────────────────────────────────────────
  static const _kSections = 'ubt_section_counts_v1';
  static const _kTypes = 'ubt_type_counts_v1';
  static const _kKeywords = 'ubt_keyword_counts_v1';
  static const _kSectionKeywordIndex = 'ubt_section_keywords_v1';
  static const _kLastSearches = 'ubt_last_searches_v1';
  static const _kBrowsedSections = 'ubt_browsed_sections_v1';
  static const _kSectionTitles = 'ubt_section_titles_v1';
  static const _kSectionLastVisit = 'ubt_section_last_visit_v1';
  static const _kQuickExitStreak = 'ubt_quick_exit_streak_v1';

  // ── الحدود القصوى للتخزين (حماية من التضخّم) ─────────────────
  static const _maxKeywords = 80;
  static const _maxLastSearches = 30;
  static const _maxKeywordsPerSection = 8;

  /// عتبة الزمن لاعتبار الزيارة "تصفّحًا حقيقيًّا" بدل "نقرة مرور سريعة".
  /// 5 ثوانٍ تبدو معقولة: أقلّ منها غالبًا تراجع فوريّ.
  static const _browsedThreshold = Duration(seconds: 5);

  /// أقلّ من هذه المدّة = «خروج سريع» (لا يُحسب تصفّحاً).
  static const _quickExitThreshold = Duration(seconds: 2);

  static const _visitDecayAfter = Duration(days: 30);

  // ── الحالة بالذاكرة (يُزامَن مع Prefs) ─────────────────────
  /// عدد مرّات فتح/زيارة كلّ قسم — المفتاح `sectionId`.
  final Map<String, int> _sectionCounts = {};

  /// عدد مرّات فتح المحتوى لكلّ نوع.
  final Map<ContentType, int> _typeCounts = {};

  /// عدد مرّات تكرار كلّ كلمة مفتاحيّة (مطبّعة) — يُغذّي البحث
  /// والتوصيات.
  final Map<String, int> _keywordCounts = {};

  /// يربط كلّ `sectionId` بقائمة الكلمات المفتاحيّة المستخرجة من عناوين
  /// القسم وعناصره — مفيد لمقارنة قسمين وكأنّهما يتشاركان موضوعًا.
  final Map<String, List<String>> _sectionKeywords = {};

  /// آخر كلمات بحث (FIFO) — لاستخدامها كتلميحات في "لك" والبحث.
  final List<String> _lastSearches = [];

  /// الأقسام التي **تصفّحها** المستخدم فعليًّا (قضى فيها وقتًا أو نقَر
  /// على أحد أبنائها/عناصرها). يختلف عن [_sectionCounts] لأنّ الأخير
  /// يرتفع بأيّ نقرة ولو عاد المستخدم فورًا؛ بينما هذا مؤشّر نيّة
  /// أقوى تستفيد منه صفحة "لك" لتغذية نفسها.
  final Map<String, int> _browsedSectionCounts = {};

  /// فهرسة عناوين الأقسام لمنع الاعتماد على قائمة `HomeProvider` عند
  /// قراءة بروفايل المستخدم لاحقًا (قد تُقرأ قبل تحميل Firebase).
  final Map<String, String> _sectionTitles = {};

  /// آخر زيارة لكلّ قسم (ISO) — لتقادم الزيارات >30 يوم.
  final Map<String, String> _sectionLastVisitIso = {};

  /// خروج سريع متتالي (<2 ث) — إن وصل 5 يُطبَّق عقوبة في ترتيب الأقسام.
  final Map<String, int> _quickExitStreak = {};

  /// ميقات بداية زيارة القسم الحاليّ — يُستعمل داخليًّا لاكتشاف متى
  /// يستحقّ "تسجيل التصفّح". لا يُحفظ في التخزين.
  final Map<String, DateTime> _sectionEnterAt = {};

  bool _loaded = false;
  SharedPreferences? _prefs;

  // ── Getters (read-only snapshots) ────────────────────────────
  bool get isLoaded => _loaded;
  Map<String, int> get sectionCounts => Map.unmodifiable(_sectionCounts);
  Map<ContentType, int> get typeCounts => Map.unmodifiable(_typeCounts);
  Map<String, int> get keywordCounts => Map.unmodifiable(_keywordCounts);
  List<String> get lastSearches => List.unmodifiable(_lastSearches);
  Map<String, int> get browsedSectionCounts =>
      Map.unmodifiable(_browsedSectionCounts);
  Map<String, String> get sectionTitles => Map.unmodifiable(_sectionTitles);

  // ──────────────────────────────────────────────────────────────
  // تحميل / تفريغ الحالة
  // ──────────────────────────────────────────────────────────────

  /// يُستدعى مرّة واحدة عند إقلاع التطبيق (من `main.dart`).
  /// آمن للاستدعاء المتكرّر.
  Future<void> init() async {
    if (_loaded) return;
    try {
      _prefs = await SharedPreferences.getInstance();
      _hydrateIntMap(_prefs!, _kSections, _sectionCounts);
      _hydrateTypeMap(_prefs!, _kTypes, _typeCounts);
      _hydrateIntMap(_prefs!, _kKeywords, _keywordCounts);
      _hydrateStringListMap(_prefs!, _kSectionKeywordIndex, _sectionKeywords);
      _hydrateIntMap(_prefs!, _kBrowsedSections, _browsedSectionCounts);
      _hydrateStringMap(_prefs!, _kSectionTitles, _sectionTitles);
      _hydrateStringMap(_prefs!, _kSectionLastVisit, _sectionLastVisitIso);
      _hydrateIntMap(_prefs!, _kQuickExitStreak, _quickExitStreak);
      final searches = _prefs!.getStringList(_kLastSearches) ?? const [];
      _lastSearches
        ..clear()
        ..addAll(searches);
    } catch (e) {
      debugPrint('[UserBehaviorTracker] init error: $e');
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  /// تصفير كامل — مفيد لاختبارات أو لخيار "نسيان اهتماماتي".
  Future<void> clear() async {
    _sectionCounts.clear();
    _typeCounts.clear();
    _keywordCounts.clear();
    _sectionKeywords.clear();
    _lastSearches.clear();
    _browsedSectionCounts.clear();
    _sectionTitles.clear();
    _sectionLastVisitIso.clear();
    _quickExitStreak.clear();
    _sectionEnterAt.clear();
    notifyListeners();
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      await prefs.remove(_kSections);
      await prefs.remove(_kTypes);
      await prefs.remove(_kKeywords);
      await prefs.remove(_kSectionKeywordIndex);
      await prefs.remove(_kLastSearches);
      await prefs.remove(_kBrowsedSections);
      await prefs.remove(_kSectionTitles);
      await prefs.remove(_kSectionLastVisit);
      await prefs.remove(_kQuickExitStreak);
    } catch (e) {
      debugPrint('[UserBehaviorTracker] clear error: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────
  // التسجيلات (Recording) — تُستدعى من أيّ مكان صامتًا
  // ──────────────────────────────────────────────────────────────

  /// يُسجَّل عندما يضغط المستخدم على قسم في الصفحة الرئيسية أو في البحث.
  /// يزيد عدّاد القسم ويضيف كلماته إلى سجلّ الاهتمامات.
  ///
  /// **صامت تمامًا**: لا يرمي أخطاء ولا يُشوّش المستخدم؛ نطبع أثرًا في
  /// debugPrint فقط إن تعطّل التخزين.
  Future<void> recordSectionVisit(String sectionId, String sectionTitle) async {
    final id = sectionId.trim();
    if (id.isEmpty) return;
    _sectionCounts[id] = (_sectionCounts[id] ?? 0) + 1;
    _sectionEnterAt[id] = DateTime.now();
    _sectionLastVisitIso[id] = DateTime.now().toIso8601String();
    final title = sectionTitle.trim();
    if (title.isNotEmpty) {
      _sectionTitles[id] = title;
    }

    final keywords = extractKeywords(sectionTitle, maxTokens: _maxKeywordsPerSection);
    if (keywords.isNotEmpty) {
      _sectionKeywords[id] = keywords;
      for (final k in keywords) {
        _keywordCounts[k] = (_keywordCounts[k] ?? 0) + 1;
      }
      _pruneKeywords();
    }
    notifyListeners();
    unawaited(_persistSections());
    unawaited(_persistKeywords());
    unawaited(_persistSectionTitles());
    unawaited(_persistSectionLastVisit());
  }

  /// يُستدعى عند مغادرة شاشة القسم (dispose). إن كان المستخدم قد قضى
  /// [_browsedThreshold] أو أكثر، نعتبره "تصفّحًا جدّيًّا" ونزيد عدّاد
  /// [_browsedSectionCounts]. هذه الإشارة أقوى من نقرة واحدة لأنّها
  /// مؤشّر نيّة أوضح، فتستعملها صفحة "لك" لتغذية نفسها.
  Future<void> recordSectionExit(String sectionId) async {
    final id = sectionId.trim();
    if (id.isEmpty) return;
    final enteredAt = _sectionEnterAt.remove(id);
    if (enteredAt == null) return;
    final spent = DateTime.now().difference(enteredAt);
    if (spent < _quickExitThreshold) {
      _quickExitStreak[id] = (_quickExitStreak[id] ?? 0) + 1;
      notifyListeners();
      unawaited(_persistQuickExitStreak());
      return;
    }
    _quickExitStreak[id] = 0;
    unawaited(_persistQuickExitStreak());
    if (spent < _browsedThreshold) return;
    _browsedSectionCounts[id] = (_browsedSectionCounts[id] ?? 0) + 1;
    notifyListeners();
    unawaited(_persistBrowsedSections());
  }

  /// مضاعف زيارة القسم: 1.0 حديثاً، 0.3 إن آخر زيارة قبل >30 يوماً.
  double visitDecayMultiplier(String sectionId) {
    final iso = _sectionLastVisitIso[sectionId];
    if (iso == null) return 1.0;
    final at = DateTime.tryParse(iso);
    if (at == null) return 1.0;
    if (DateTime.now().difference(at) > _visitDecayAfter) return 0.3;
    return 1.0;
  }

  /// عقوبة إن خرج المستخدم 5 مرّات متتالية خلال <2 ثانية.
  double quickExitPenalty(String sectionId) {
    final streak = _quickExitStreak[sectionId] ?? 0;
    if (streak >= 5) return -1.5;
    return 0.0;
  }

  /// تسجيل فوريّ لـ "تصفّح كامل" حين يوجد مؤشّر صريح (مثل الضغط على
  /// عنصر أو التمرير لنهاية القائمة). يتجاوز عتبة الوقت.
  Future<void> recordSectionBrowsed(String sectionId, [String? title]) async {
    final id = sectionId.trim();
    if (id.isEmpty) return;
    _browsedSectionCounts[id] = (_browsedSectionCounts[id] ?? 0) + 1;
    if (title != null && title.trim().isNotEmpty) {
      _sectionTitles[id] = title.trim();
    }
    _sectionEnterAt.remove(id);
    notifyListeners();
    unawaited(_persistBrowsedSections());
    unawaited(_persistSectionTitles());
  }

  /// يُسجَّل عندما يفتح المستخدم عنصر محتوى (من أي مكان: الرئيسية،
  /// لك، البحث).
  Future<void> recordContentOpen(Content content) async {
    if (content.id.trim().isEmpty) return;
    _typeCounts[content.type] = (_typeCounts[content.type] ?? 0) + 1;

    if (content.section.trim().isNotEmpty) {
      _sectionCounts[content.section] =
          (_sectionCounts[content.section] ?? 0) + 1;
    }
    final keywords = <String>{
      ...extractKeywords(content.title, maxTokens: _maxKeywordsPerSection),
      ...extractKeywords(content.sectionName, maxTokens: 3),
    };
    for (final k in keywords) {
      _keywordCounts[k] = (_keywordCounts[k] ?? 0) + 1;
    }
    _pruneKeywords();
    notifyListeners();
    unawaited(_persistSections());
    unawaited(_persistTypes());
    unawaited(_persistKeywords());
  }

  /// يُسجَّل عند كلّ بحث ناجح (أو حتّى عند الضغط على بحث بعد توقّف debounce).
  /// نُرجّح وزن الكلمة عند البحث أكثر قليلًا من مجرّد زيارة، لأنّها
  /// نيّة صريحة من المستخدم.
  Future<void> recordSearch(String query) async {
    final normalized = normalizeText(query);
    if (normalized.isEmpty || normalized.length < 2) return;

    _lastSearches.remove(normalized);
    _lastSearches.insert(0, normalized);
    if (_lastSearches.length > _maxLastSearches) {
      _lastSearches.removeRange(_maxLastSearches, _lastSearches.length);
    }

    // كلّ كلمة من الاستعلام تُحتسب كاهتمام مضاعف (+2) لأنّها نيّة صريحة.
    for (final k in extractKeywords(query, maxTokens: 6)) {
      _keywordCounts[k] = (_keywordCounts[k] ?? 0) + 2;
    }
    _pruneKeywords();
    notifyListeners();
    unawaited(_persistKeywords());
    unawaited(_persistLastSearches());
  }

  /// إزالة كلمة بحث واحدة من السجلّ (لا تؤثر على `_keywordCounts` لأنّ
  /// الاهتمامات تُبنى عبر الوقت ولا نحذف إشارة المستخدم السابقة — نحن
  /// فقط ننظّف عرض السجلّ).
  Future<void> removeSearch(String query) async {
    final normalized = normalizeText(query);
    if (normalized.isEmpty) return;
    final removed = _lastSearches.remove(normalized);
    if (!removed) return;
    notifyListeners();
    unawaited(_persistLastSearches());
  }

  /// تفريغ كامل لسجلّ البحث المعروض للمستخدم، مع إبقاء اهتماماته العامّة.
  Future<void> clearSearchHistory() async {
    if (_lastSearches.isEmpty) return;
    _lastSearches.clear();
    notifyListeners();
    unawaited(_persistLastSearches());
  }

  /// واجهة صريحة: تُستدعى عند دخول قسم.
  Future<void> recordSectionEnter(String sectionId, String sectionTitle) {
    return recordSectionVisit(sectionId, sectionTitle);
  }

  /// واجهة صريحة: تُستدعى عند تشغيل/عرض محتوى فعليًا.
  Future<void> recordContentPlayed(Content content) {
    return recordContentOpen(content);
  }

  /// واجهة صريحة: تُستدعى عند كتابة المستخدم كلمة بحث.
  Future<void> recordSearchKeyword(String query) {
    return recordSearch(query);
  }

  // ──────────────────────────────────────────────────────────────
  // الاستعلام (Scoring / Querying)
  // ──────────────────────────────────────────────────────────────

  /// وزن قسم مقارنةً بالأقسام الأخرى — يعتمد على عدد الزيارات. يبدأ من 0.
  ///
  /// يُضمّن زيارات التصفّح الفعليّة بوزن مضاعف لأنّها مؤشّر نيّة أقوى:
  /// دخول قسم وتصفّحه حقيقيًّا يساوي ≈ نقرتَين عابرتَين.
  int sectionScore(String sectionId) {
    final clicks = _sectionCounts[sectionId] ?? 0;
    final browsed = _browsedSectionCounts[sectionId] ?? 0;
    return clicks + browsed * 2;
  }

  /// وزن التصفّح الفعليّ (أقوى من مجرّد نقرة) — مفيد للتمييز بين
  /// "قسم مرّ به المستخدم خطأ" و"قسم قضى فيه وقتًا".
  int browsedSectionScore(String sectionId) =>
      _browsedSectionCounts[sectionId] ?? 0;

  /// أعلى N قسم — مرتّب تنازليًّا بـ `sectionScore` (نقرات + تصفّح).
  /// يُرجع المعرِّفات، ويُتاح للقارئ الحصول على العنوان عبر [sectionTitles].
  List<String> topSectionIds({int limit = 10}) {
    if (_sectionCounts.isEmpty && _browsedSectionCounts.isEmpty) {
      return const [];
    }
    final ids = <String>{
      ..._sectionCounts.keys,
      ..._browsedSectionCounts.keys,
    };
    final scored = ids
        .map((id) => MapEntry(id, sectionScore(id)))
        .where((e) => e.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return scored.take(limit).map((e) => e.key).toList(growable: false);
  }

  /// وزن نوع محتوى (فيديو/صوت/...) — يُستخدم في ترتيب قائمة "ذات صلة"
  /// لترجيح النوع الذي يُفضّله المستخدم.
  int typeScore(ContentType type) => _typeCounts[type] ?? 0;

  /// وزن كلمة مفتاحيّة. المدخل يُطبَّع قبل البحث.
  int keywordScore(String keyword) {
    final norm = normalizeText(keyword);
    if (norm.isEmpty) return 0;
    return _keywordCounts[norm] ?? 0;
  }

  /// أعلى N كلمة مفتاحيّة — تعكس اهتمامات المستخدم المُجمَّعة.
  /// تُستخدم في صفحة "لك" وفي اقتراحات البحث الأوّليّة.
  List<String> topKeywords({int limit = 20}) {
    final entries = _keywordCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(limit).map((e) => e.key).toList(growable: false);
  }

  /// الكلمات المفتاحيّة المسجَّلة لقسم — تُستخدم لحساب تشابه قسمين.
  List<String> keywordsForSection(String sectionId) =>
      _sectionKeywords[sectionId] ?? const [];

  /// لقطة شاملة لملفّ السلوك — يُستعمل في صفحة "لك" لتحويل كلّ
  /// الإشارات إلى استعلامات صامتة: كلمات تبحث بها،
  /// وأقسام تتصفّحها، ونوع محتوى يُرجَّح.
  ///
  /// **الاستخدام المتوقَّع**:
  ///   * `keywords`: ترسل لمحرّك البحث لجلب محتوى جديد يطابق الاهتمام.
  ///   * `sectionIds`: تُلتقط من `HomeProvider.sections` وتُفتح ضمنها
  ///     عناصر جديدة لم يرَها المستخدم بعد.
  ///   * `preferredType`: يُستخدم كفلتر فرز (ليس حذفًا) لكي يُقدَّم
  ///     النوع الذي يفضّله المستخدم في المقدّمة.
  BehaviorProfile profileSnapshot({
    int maxKeywords = 12,
    int maxSections = 8,
  }) {
    final keywords = topKeywords(limit: maxKeywords);
    final sections = topSectionIds(limit: maxSections);
    ContentType? preferredType;
    if (_typeCounts.isNotEmpty) {
      final sorted = _typeCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      preferredType = sorted.first.key;
    }
    return BehaviorProfile(
      keywords: keywords,
      sectionIds: sections,
      sectionTitles: Map.unmodifiable({
        for (final id in sections)
          if (_sectionTitles.containsKey(id)) id: _sectionTitles[id]!,
      }),
      recentSearches: List.unmodifiable(_lastSearches.take(maxKeywords)),
      preferredType: preferredType,
    );
  }

  /// نسبة تشابه سياقيّ بين عنصرَي محتوى، تجمع: القسم + النوع + الكلمات.
  /// النتيجة بين 0 و 1 تقريبًا — تستخدمها `RecommendationEngine`.
  double similarityBetween(Content reference, Content candidate) {
    if (reference.id == candidate.id) return 0.0;

    double score = 0.0;
    if (reference.section == candidate.section &&
        reference.section.trim().isNotEmpty) {
      score += 0.55;
    }
    if (reference.subSection != null &&
        reference.subSection == candidate.subSection) {
      score += 0.15;
    }
    if (reference.type == candidate.type) score += 0.10;

    score += keywordOverlapScore(reference.title, candidate.title) * 0.20;
    return score.clamp(0.0, 1.0);
  }

  // ──────────────────────────────────────────────────────────────
  // أدوات داخليّة
  // ──────────────────────────────────────────────────────────────

  void _pruneKeywords() {
    if (_keywordCounts.length <= _maxKeywords) return;
    final entries = _keywordCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final keep = entries.take(_maxKeywords).toList();
    _keywordCounts
      ..clear()
      ..addEntries(keep);
  }

  Future<void> _persistSections() async {
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      await prefs.setString(_kSections, jsonEncode(_sectionCounts));
      await prefs.setString(
        _kSectionKeywordIndex,
        jsonEncode(_sectionKeywords),
      );
    } catch (e) {
      debugPrint('[UserBehaviorTracker] persist sections error: $e');
    }
  }

  Future<void> _persistTypes() async {
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      final encoded = <String, int>{
        for (final entry in _typeCounts.entries) entry.key.name: entry.value,
      };
      await prefs.setString(_kTypes, jsonEncode(encoded));
    } catch (e) {
      debugPrint('[UserBehaviorTracker] persist types error: $e');
    }
  }

  Future<void> _persistKeywords() async {
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      await prefs.setString(_kKeywords, jsonEncode(_keywordCounts));
    } catch (e) {
      debugPrint('[UserBehaviorTracker] persist keywords error: $e');
    }
  }

  Future<void> _persistLastSearches() async {
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      await prefs.setStringList(_kLastSearches, _lastSearches);
    } catch (e) {
      debugPrint('[UserBehaviorTracker] persist searches error: $e');
    }
  }

  Future<void> _persistBrowsedSections() async {
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      await prefs.setString(_kBrowsedSections, jsonEncode(_browsedSectionCounts));
    } catch (e) {
      debugPrint('[UserBehaviorTracker] persist browsed error: $e');
    }
  }

  Future<void> _persistSectionTitles() async {
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      await prefs.setString(_kSectionTitles, jsonEncode(_sectionTitles));
    } catch (e) {
      debugPrint('[UserBehaviorTracker] persist titles error: $e');
    }
  }

  Future<void> _persistSectionLastVisit() async {
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      await prefs.setString(
        _kSectionLastVisit,
        jsonEncode(_sectionLastVisitIso),
      );
    } catch (e) {
      debugPrint('[UserBehaviorTracker] persist last visit error: $e');
    }
  }

  Future<void> _persistQuickExitStreak() async {
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      await prefs.setString(_kQuickExitStreak, jsonEncode(_quickExitStreak));
    } catch (e) {
      debugPrint('[UserBehaviorTracker] persist quick exit error: $e');
    }
  }

  void _hydrateIntMap(
    SharedPreferences prefs,
    String key,
    Map<String, int> target,
  ) {
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        decoded.forEach((k, v) {
          final id = k.toString();
          final count = (v is int)
              ? v
              : int.tryParse(v?.toString() ?? '') ?? 0;
          if (count > 0) target[id] = count;
        });
      }
    } catch (e) {
      debugPrint('[UserBehaviorTracker] decode $key error: $e');
    }
  }

  void _hydrateTypeMap(
    SharedPreferences prefs,
    String key,
    Map<ContentType, int> target,
  ) {
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        decoded.forEach((k, v) {
          final type = _parseType(k.toString());
          if (type == null) return;
          final count = (v is int)
              ? v
              : int.tryParse(v?.toString() ?? '') ?? 0;
          if (count > 0) target[type] = count;
        });
      }
    } catch (e) {
      debugPrint('[UserBehaviorTracker] decode types error: $e');
    }
  }

  void _hydrateStringListMap(
    SharedPreferences prefs,
    String key,
    Map<String, List<String>> target,
  ) {
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        decoded.forEach((k, v) {
          if (v is List) {
            target[k.toString()] = v.map((e) => e.toString()).toList();
          }
        });
      }
    } catch (e) {
      debugPrint('[UserBehaviorTracker] decode section keywords error: $e');
    }
  }

  ContentType? _parseType(String raw) {
    for (final t in ContentType.values) {
      if (t.name == raw) return t;
    }
    return null;
  }

  void _hydrateStringMap(
    SharedPreferences prefs,
    String key,
    Map<String, String> target,
  ) {
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        decoded.forEach((k, v) {
          target[k.toString()] = v?.toString() ?? '';
        });
      }
    } catch (e) {
      debugPrint('[UserBehaviorTracker] decode $key error: $e');
    }
  }
}

/// BehaviorProfile — لقطة مضغوطة لاهتمامات المستخدم، يُنتجها
/// [UserBehaviorTracker.profileSnapshot] ويستهلكها تحديدًا
/// `ForYouProvider` لبناء استعلامات صامتة.
///
/// **غير قابل للتغيير** (immutable) — القيم كلها unmodifiable حتى لا
/// يُعدّلها المستهلك عن طريق الخطأ. لإعادة حسابه استدعِ الدالّة
/// [UserBehaviorTracker.profileSnapshot] مجدّدًا.
class BehaviorProfile {
  final List<String> keywords;
  final List<String> sectionIds;
  final Map<String, String> sectionTitles;
  final List<String> recentSearches;
  final ContentType? preferredType;

  const BehaviorProfile({
    required this.keywords,
    required this.sectionIds,
    required this.sectionTitles,
    required this.recentSearches,
    required this.preferredType,
  });

  bool get isEmpty =>
      keywords.isEmpty && sectionIds.isEmpty && recentSearches.isEmpty;
  bool get isNotEmpty => !isEmpty;

  /// مفتاح بحث مدموج — يجمع الكلمات المميَّزة وآخر بحث لم يُفهرس بعد.
  /// مفيد للخدمات التي تريد استعلامًا واحدًا فقط.
  String primaryQuery({int maxWords = 4}) {
    final words = <String>{};
    for (final k in recentSearches) {
      if (words.length >= maxWords) break;
      words.add(k);
    }
    for (final k in keywords) {
      if (words.length >= maxWords) break;
      words.add(k);
    }
    return words.join(' ').trim();
  }
}
