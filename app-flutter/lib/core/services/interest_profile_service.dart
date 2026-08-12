import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nebras_mobile_app/core/utils/text_normalizer.dart';
import 'package:nebras_mobile_app/features/content/model/content_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// InterestProfileService — **محرّك حساب اهتمامات المستخدم (Affinity)**
/// مستقلّ تمامًا عن [UserBehaviorTracker]، لتغذية `RecommendationService`
/// لصفحة "لك" (For You).
///
/// ── لماذا خدمة منفصلة؟ ──
/// [UserBehaviorTracker] يُعبّر عن مسارات استخدام متعدّدة (بحث، ترتيب
/// رئيسيّة، تصفّح، سجلّ)، وأوزانه الداخليّة متشعّبة بين «نقرة قسم»
/// و«فتح محتوى» داخل نفس العدّاد. لإنجاز المتطلّب بأوزان دقيقة ومنع
/// أي تداخل مع المنطق القائم، نُبقي المتتبّع القديم كما هو (بحرفيّته)،
/// ونُنشئ هذه الخدمة كطبقة **إضافيّة** على التخزين (مفاتيح جديدة)
/// وعلى هوكات الاستدعاء (تُستدعى جنبًا إلى جنب مع المتتبّع، ولا تحلّ
/// محلّه).
///
/// ── الأوزان الصارمة (كما طلب المنتج) ──
///   * **Section View** (دخول قسم) ⇒ `+1` لرصيد القسم، `+1` لكلّ كلمة
///     مفتاحيّة مستخرَجة من عنوانه.
///   * **Content Consumption** (فتح كتاب/فيديو/صوت) ⇒ `+3` لرصيد القسم
///     المضيف، `+3` لكلّ كلمة مفتاحيّة من عنوان المحتوى/قسمه.
///   * **Search Query** (استعلام بحث أسفر عن تطابق) ⇒ `+5` لكلّ كلمة
///     مفتاحيّة مُستخرَجة من الاستعلام (النيّة الصريحة أقوى إشارة).
///
/// ── حدود الأداء ──
/// - كلّ الكتابات غير حاجزة (`unawaited` داخل `_persist*`)، فلا يرتبط
///   زمن الاستجابة بالعمليّة.
/// - سقف 120 كلمة مفتاحيّة نشطة (`_maxKeywords`) حتى لا ينتفخ التخزين.
/// - رنكات 16-bit (int) داخليًّا — خفيفة جدًا على الـ JSON encode.
///
/// ── العزل ──
/// - لا يعرف بشبكة ولا بـ Firebase.
/// - لا يعدّل أيّ حالة في `UserBehaviorTracker` أو `InterestStore`.
/// - يُقرأ فقط من `RecommendationService` (طبقة الفرز).
class InterestProfileService extends ChangeNotifier {
  InterestProfileService._();

  /// المثيل العامّ — يجب دائمًا استخدامه.
  static final InterestProfileService instance = InterestProfileService._();

  // ── أوزان النموذج (ثابتة، مرئيّة لاختبارات الوحدة) ──────────
  static const int weightSectionView = 1;
  static const int weightConsumption = 3;
  static const int weightSearch = 5;

  // ── حدود التخزين ───────────────────────────────────────────
  static const int _maxKeywords = 120;
  static const int _maxKeywordsPerTitle = 8;

  // ── مفاتيح التخزين (جديدة — لا تتعارض مع UBT) ─────────────
  static const _kSectionAffinity = 'ips_section_affinity_v1';
  static const _kKeywordAffinity = 'ips_keyword_affinity_v1';
  static const _kTypeAffinity = 'ips_type_affinity_v1';

  // ── الحالة بالذاكرة ───────────────────────────────────────
  /// إجماليّ النقاط لكلّ قسم: مجموع مرجَّح لزيارات القسم + استهلاك
  /// محتواه + إشارات البحث المطابقة. لا نفصل المصادر داخليًّا بعد الجمع
  /// لتبسيط عمليّة القراءة في طبقة الفرز.
  final Map<String, int> _sectionScores = {};

  /// إجماليّ النقاط لكلّ كلمة مفتاحيّة (مطبَّعة عربيًّا عبر
  /// `normalizeText`). تُستعمل عند مطابقة عنوان محتوى جديد لم نرَه قط.
  final Map<String, int> _keywordScores = {};

  /// وزن تفضيل نوع المحتوى — يساعد على «ترجيح الفيديو على الكتاب»
  /// مثلًا إن كان المستخدم يستهلكه أكثر. لا يُحسَب كعدد مطلق وإنّما
  /// يتدرّج مع كلّ استهلاك.
  final Map<ContentType, int> _typeScores = {};

  bool _loaded = false;
  SharedPreferences? _prefs;

  // ── Getters (read-only snapshots) ─────────────────────────
  bool get isLoaded => _loaded;

  /// هل لدينا أيّ إشارة فعلًا؟ يستعمله `ForYouProvider` ليُقرّر التحوّل
  /// إلى المنطق المُشخصَن بدل التحوّل العشوائيّ.
  bool get hasSignals =>
      _sectionScores.isNotEmpty ||
      _keywordScores.isNotEmpty ||
      _typeScores.isNotEmpty;

  Map<String, int> get sectionScores => Map.unmodifiable(_sectionScores);
  Map<String, int> get keywordScores => Map.unmodifiable(_keywordScores);
  Map<ContentType, int> get typeScores => Map.unmodifiable(_typeScores);

  // ──────────────────────────────────────────────────────────
  // دورة الحياة
  // ──────────────────────────────────────────────────────────

  /// يُستدعى مرّة واحدة من `main.dart`. آمن للاستدعاء المتكرّر.
  Future<void> init() async {
    if (_loaded) return;
    try {
      _prefs = await SharedPreferences.getInstance();
      _hydrateIntMap(_prefs!, _kSectionAffinity, _sectionScores);
      _hydrateIntMap(_prefs!, _kKeywordAffinity, _keywordScores);
      _hydrateTypeMap(_prefs!, _kTypeAffinity, _typeScores);
    } catch (e) {
      debugPrint('[InterestProfileService] init error: $e');
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  /// إعادة ضبط كاملة — مفيد لخيار «نسيان اهتماماتي» في الإعدادات.
  Future<void> clearProfile() async {
    _sectionScores.clear();
    _keywordScores.clear();
    _typeScores.clear();
    notifyListeners();
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      await prefs.remove(_kSectionAffinity);
      await prefs.remove(_kKeywordAffinity);
      await prefs.remove(_kTypeAffinity);
    } catch (e) {
      debugPrint('[InterestProfileService] clear error: $e');
    }
  }

  // ──────────────────────────────────────────────────────────
  // التسجيلات (الأوزان المطلوبة: +1/+3/+5)
  // ──────────────────────────────────────────────────────────

  /// تصفّح قسم (Section View). وزنه **+1** للقسم ولكلّ كلمة من عنوانه.
  ///
  /// يُستدعى جنبًا إلى جنب مع `UserBehaviorTracker.instance.recordSectionVisit`
  /// من `SectionRouter` و`SectionLifecycleTracker`. لا يحلّ محلّه.
  Future<void> onSectionView(String sectionId, String sectionTitle) async {
    final id = sectionId.trim();
    if (id.isEmpty) return;
    _sectionScores[id] = (_sectionScores[id] ?? 0) + weightSectionView;

    final keys = extractKeywords(sectionTitle, maxTokens: _maxKeywordsPerTitle);
    for (final k in keys) {
      _keywordScores[k] = (_keywordScores[k] ?? 0) + weightSectionView;
    }
    _pruneKeywords();
    notifyListeners();
    unawaited(_persistAll());
  }

  /// استهلاك فعليّ للمحتوى (فتح قارئ، تشغيل فيديو/صوت). وزنه **+3**.
  ///
  /// يُستدعى من `ContentRouter.open` وشاشات المشغّلات بعد تأكيد الفتح.
  Future<void> onContentConsumed(Content content) async {
    if (content.id.trim().isEmpty) return;

    // وزن القسم المضيف للمحتوى.
    final sectionId = content.section.trim();
    if (sectionId.isNotEmpty) {
      _sectionScores[sectionId] =
          (_sectionScores[sectionId] ?? 0) + weightConsumption;
    }

    // وزن النوع — يدخل في حساب تفضيل المستخدم لنوع المحتوى.
    _typeScores[content.type] =
        (_typeScores[content.type] ?? 0) + weightConsumption;

    // كلمات من عنوان المحتوى + اسم القسم (للتسلسل الدلاليّ).
    final keys = <String>{
      ...extractKeywords(content.title, maxTokens: _maxKeywordsPerTitle),
      ...extractKeywords(content.sectionName, maxTokens: 3),
    };
    for (final k in keys) {
      _keywordScores[k] = (_keywordScores[k] ?? 0) + weightConsumption;
    }
    _pruneKeywords();
    notifyListeners();
    unawaited(_persistAll());
  }

  /// استعلام بحث ناجح (أسفر عن نتائج حقيقيّة). وزنه **+5** — أعلى
  /// إشارة لأنّها نيّة صريحة من المستخدم.
  ///
  /// يُستدعى من `SearchProvider._executeSearch` بعد تأكيد `realMatch`
  /// تمامًا كما تُستدعى `UserBehaviorTracker.recordSearch`.
  Future<void> onSearchQuery(String query) async {
    final keys = extractKeywords(query, maxTokens: 6);
    if (keys.isEmpty) return;
    for (final k in keys) {
      _keywordScores[k] = (_keywordScores[k] ?? 0) + weightSearch;
    }
    _pruneKeywords();
    notifyListeners();
    unawaited(_persistAll());
  }

  // ──────────────────────────────────────────────────────────
  // استعلامات الأفنيتي (تُقرأ من RecommendationService)
  // ──────────────────────────────────────────────────────────

  /// أفنيتي قسم — مجموع نقاطه في ملفّ الاهتمامات (0 إن لم يُسجَّل).
  int sectionAffinity(String sectionId) => _sectionScores[sectionId] ?? 0;

  /// أفنيتي كلمة مفتاحيّة — الإدخال يُطبَّع قبل البحث.
  int keywordAffinity(String keyword) {
    final norm = normalizeText(keyword);
    if (norm.isEmpty) return 0;
    return _keywordScores[norm] ?? 0;
  }

  /// أفنيتي نوع محتوى (فيديو/صوت/...).
  int typeAffinity(ContentType type) => _typeScores[type] ?? 0;

  /// تقدير **رصيد كلّيّ** لعنصر محتوى في ملفّ الاهتمامات:
  ///   * نقاط قسمه (إن وُجد في الخريطة)
  ///   * نصف نقاط نوعه (كعامل مُساند لا يطغى على القسم)
  ///   * مجموع نقاط كلمات عنوانه المطابِقة للاهتمامات
  ///
  /// النتيجة `int` مقبول أن تكون 0 لمحتوى لم يُلامس أيّ اهتمام — وهو
  /// ما يسمح لطبقة الفرز (`RecommendationService`) بترك 15% من المحتوى
  /// عشوائيًّا/استكشافيًّا في أعلى/وسط الخلاصة.
  int contentAffinity(Content content) {
    int score = 0;
    if (content.section.trim().isNotEmpty) {
      score += _sectionScores[content.section] ?? 0;
    }
    score += ((_typeScores[content.type] ?? 0) * 0.5).round();
    final keys = extractKeywords(content.title, maxTokens: _maxKeywordsPerTitle);
    for (final k in keys) {
      score += _keywordScores[k] ?? 0;
    }
    return score;
  }

  /// أعلى N قسم بحسب الأفنيتي — يفيد صفحة "لك" لاختيار «من قسم زاره
  /// المستخدم فعلًا» بدل العشوائية.
  List<String> topSections({int limit = 10}) {
    if (_sectionScores.isEmpty) return const [];
    final entries = _sectionScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(limit).map((e) => e.key).toList(growable: false);
  }

  /// أعلى N كلمة بحسب الأفنيتي — تُستعمل لاستعلامات ذكيّة مستقبليّة
  /// (لم تُنشط في هذه الخدمة لكنها متاحة للقارئ).
  List<String> topKeywords({int limit = 15}) {
    if (_keywordScores.isEmpty) return const [];
    final entries = _keywordScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(limit).map((e) => e.key).toList(growable: false);
  }

  // ──────────────────────────────────────────────────────────
  // أدوات داخليّة
  // ──────────────────────────────────────────────────────────

  void _pruneKeywords() {
    if (_keywordScores.length <= _maxKeywords) return;
    final entries = _keywordScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final keep = entries.take(_maxKeywords).toList();
    _keywordScores
      ..clear()
      ..addEntries(keep);
  }

  Future<void> _persistAll() async {
    try {
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      await prefs.setString(_kSectionAffinity, jsonEncode(_sectionScores));
      await prefs.setString(_kKeywordAffinity, jsonEncode(_keywordScores));
      final encodedTypes = <String, int>{
        for (final entry in _typeScores.entries) entry.key.name: entry.value,
      };
      await prefs.setString(_kTypeAffinity, jsonEncode(encodedTypes));
    } catch (e) {
      debugPrint('[InterestProfileService] persist error: $e');
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
      debugPrint('[InterestProfileService] decode $key error: $e');
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
      debugPrint('[InterestProfileService] decode types error: $e');
    }
  }

  ContentType? _parseType(String raw) {
    for (final t in ContentType.values) {
      if (t.name == raw) return t;
    }
    return null;
  }
}
