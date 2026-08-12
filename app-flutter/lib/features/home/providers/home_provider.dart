import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nebras_mobile_app/core/services/popularity_feed_service.dart';
import 'package:nebras_mobile_app/core/services/recommendation_service.dart';
import 'package:nebras_mobile_app/core/services/user_behavior_tracker.dart';
import 'package:nebras_mobile_app/features/home/model/home_rail.dart';
import 'package:nebras_mobile_app/features/home/services/home_rail_builders.dart';
import 'package:nebras_mobile_app/core/utils/text_normalizer.dart';
import 'package:nebras_mobile_app/features/content/model/content_model.dart';
import 'package:nebras_mobile_app/features/home/data/home_section_model.dart';
import 'package:nebras_mobile_app/features/home/domain/get_home_data_usecase.dart';

/// Home Provider
/// يدير حالة الصفحة الرئيسيّة: الأقسام، التحميل، الخطأ، الترقيم.
/// لا يقوم بأيّ نداءات شبكة مباشرة — يفوّض ذلك لـ use case، الذي يقرأ
/// حصرياً من Cloud Firestore عبر [HomeDatasource] (`sections_unified`،
/// `dashboard_uploads`، `content_unified_files`، `content_unified_youtube`).
///
/// لا يوجد أيّ جسر لمصادر خارجية أو مشاريع Firebase ثانوية — البيانات تأتي
/// من قاعدة Nebras الوحيدة.
class HomeProvider extends ChangeNotifier {
  /// How long to wait for the first snapshot before triggering the offline fallback.
  static const Duration weakNetworkBootTimeout = Duration(seconds: 3);

  /// Hard deadline for the one-shot fallback fetch. Must be much larger than
  /// [weakNetworkBootTimeout] — Firebase cold-start on Production can take
  /// 4–8 s, and a 3-second cap guarantees the fetch always fails on first
  /// install with no local Firestore cache.
  static const Duration _fetchTimeout = Duration(seconds: 30);

  final GetHomeDataUseCase _getHomeDataUseCase;

  /// اللغة الحاليّة التي بنينا عليها شجرة البيانات. تُحدَّث من
  /// [startWatching] لتتزامن مع `context.locale`.
  // ignore: unused_field
  String _currentLocale = 'ar';

  HomeProvider(this._getHomeDataUseCase) {
    // نعيد البناء كلّما تغيّر ملفّ المستخدم السلوكيّ كي يُحدَّث الترتيب
    // الذكيّ للأقسام — دون أيّ طلب شبكة. العمليّة خفيفة ومحصورة بـ UI.
    UserBehaviorTracker.instance.addListener(_onTrackerChanged);
  }

  void _onTrackerChanged() {
    unawaited(_rebuildHomeRails());
    notifyListeners();
  }

  // ── State ──────────────────────────────────────────────────
  /// أقسام Firestore — المصدر الوحيد للحقيقة.
  List<HomeSection> _firebaseSections = [];
  bool _isLoading = false;
  String? _errorMessage;
  bool _hasMore = true;
  int _currentPage = 1;
  bool _isFetchingMore = false;

  // اشتراك الـ real-time stream على Firestore (`snapshots()`).
  // نحتفظ به لإلغائه عند dispose أو عند إعادة الاشتراك، حتى لا نترك
  // listeners متراكمة.
  StreamSubscription<List<HomeSection>>? _liveSub;
  bool get _hasLiveSubscription => _liveSub != null;

  /// رفوف الصفحة الرئيسيّة (ليست أقسام Firestore) — راجع docs/CONTENT_ORDERING_AND_HOME.md.
  List<HomeRail> _homeRails = const [];
  List<HomeRail> get homeRails => _homeRails;
  bool _railsBuilding = false;

  /// هل التخصيص مفعَّل؟ يُضبط من الواجهة حسب حالة المصادقة: `true` فقط
  /// لمستخدم حقيقيّ (Google)، و`false` للضيف. يحكم بناء الرفوف الشخصيّة.
  bool _personalizationEnabled = false;
  bool get personalizationEnabled => _personalizationEnabled;

  /// يضبط حالة التخصيص ويعيد بناء الرفوف فوراً إن تغيّرت. تُستدعى من
  /// HomeScreen عند معرفة حالة الحساب أو تغيّرها (دخول/خروج).
  void setPersonalizationEnabled(bool value) {
    if (_personalizationEnabled == value) return;
    _personalizationEnabled = value;
    unawaited(_rebuildHomeRails());
    notifyListeners();
  }

  /// نحاول جلب معرّفات الشعبيّة من الشبكة مرّة واحدة فقط لكلّ جلسة. بدون
  /// هذا الحارس كان كلّ إعادة بناء للرفوف (مع كلّ لقطة حيّة أو تغيّر في
  /// متتبّع السلوك) تُعيد محاولة قراءة مستند الشعبيّة — وإذا كانت القراءة
  /// تُرفض بـ permission-denied تتدفّق مئات المحاولات الفاشلة في السجلّ.
  bool _popularRefreshAttempted = false;

  // ── Idle Auto-Suggest (YouTube-style) ──────────────────────
  Timer? _idleTimer;
  static const Duration _idleThreshold = Duration(seconds: 6);
  List<Content> _suggestedFeed = const [];
  bool _showingSuggestions = false;

  bool get isShowingSuggestions =>
      _showingSuggestions && _suggestedFeed.isNotEmpty;

  List<Content> get suggestedFeed => _suggestedFeed;

  List<Content> get effectiveFeed {
    final personal = personalizedFeed;
    if (personal.isNotEmpty) return personal;
    return isShowingSuggestions ? _suggestedFeed : const <Content>[];
  }

  void resetIdleTimer() {
    _idleTimer?.cancel();
    if (_showingSuggestions) {
      _showingSuggestions = false;
      _suggestedFeed = const <Content>[];
      notifyListeners();
    }
    _idleTimer = Timer(_idleThreshold, _onIdle);
  }

  void _onIdle() {
    if (personalizedFeed.isNotEmpty) return;
    final suggestions = _buildSuggestedFeed();
    if (suggestions.isEmpty) return;
    _suggestedFeed = suggestions;
    _showingSuggestions = true;
    notifyListeners();
  }

  List<Content> _buildSuggestedFeed({int maxItems = 30}) {
    final secs = sections;
    if (secs.isEmpty) return const <Content>[];

    final byId = {for (final s in secs) s.id: s};
    final out = <Content>[];
    final seen = <String>{};

    final tracker = UserBehaviorTracker.instance;
    for (final id in tracker.topSectionIds(limit: 6)) {
      final s = byId[id];
      if (s == null) continue;
      final items = List<Content>.of(s.items)
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      for (final item in items.take(6)) {
        if (seen.add(item.id)) out.add(item);
        if (out.length >= maxItems) return out;
      }
    }

    // شعبيّة محلّية من view_count (بديل قسم Firestore القديم most_watched).
    final popularPool = <Content>[];
    for (final s in secs) {
      popularPool.addAll(s.items);
    }
    popularPool.sort((a, b) {
      final byViews = b.viewCount.compareTo(a.viewCount);
      if (byViews != 0) return byViews;
      return b.createdAt.compareTo(a.createdAt);
    });
    for (final item in popularPool.take(8)) {
      if (seen.add(item.id)) out.add(item);
      if (out.length >= maxItems) return out;
    }

    final pools = secs
        .map(
          (s) => List<Content>.of(s.items)
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
        )
        .where((p) => p.isNotEmpty)
        .toList(growable: false);
    var depth = 0;
    while (out.length < maxItems) {
      var advanced = false;
      for (final pool in pools) {
        if (depth >= pool.length) continue;
        advanced = true;
        final item = pool[depth];
        if (seen.add(item.id)) out.add(item);
        if (out.length >= maxItems) break;
      }
      if (!advanced) break;
      depth++;
    }
    return out;
  }

  // ── Getters ────────────────────────────────────────────────
  /// أقسام Firestore بعد الترتيب الذكيّ. لا دمج مع أيّ مصدر خارجيّ.
  List<HomeSection> get sections => _rankSections(_firebaseSections);

  /// نسخة خام قبل الترتيب الذكيّ — مفيدة لشاشات الإدارة أو الاختبارات.
  List<HomeSection> get sectionsRaw => List<HomeSection>.unmodifiable(
    _firebaseSections,
  );

  List<HomeSection> _rankSections(List<HomeSection> input) {
    if (input.isEmpty) return input;
    final tracker = UserBehaviorTracker.instance;
    if (!tracker.isLoaded) {
      return input;
    }

    final scored = <_ScoredSection>[];
    for (var i = 0; i < input.length; i++) {
      final s = input[i];
      final baseRank = -i.toDouble() * 0.001;
      final arabicBoost = _isArabicIslamicSection(s) ? 6.0 : 0.0;
      var visitBoost = tracker.sectionScore(s.id) > 0
          ? (1 + tracker.sectionScore(s.id)) * 0.8
          : 0.0;
      visitBoost *= tracker.visitDecayMultiplier(s.id);
      final quickPenalty = tracker.quickExitPenalty(s.id);

      double keywordBoost = 0.0;
      for (final k in extractKeywords(s.title, maxTokens: 6)) {
        keywordBoost += tracker.keywordScore(k) * 0.25;
      }
      if (keywordBoost > 5.0) keywordBoost = 5.0;

      scored.add(
        _ScoredSection(
          section: s,
          index: i,
          score:
              arabicBoost + visitBoost + keywordBoost + quickPenalty + baseRank,
        ),
      );
    }

    scored.sort((a, b) {
      final cmp = b.score.compareTo(a.score);
      if (cmp != 0) return cmp;
      return a.index.compareTo(b.index); // stable tie-break
    });
    return scored.map((e) => e.section).toList(growable: false);
  }

  List<Content> get personalizedFeed {
    final allContent = <String, Content>{};
    for (final section in sections) {
      for (final item in section.items) {
        allContent[item.id] = item;
      }
    }

    // بذرة ثابتة مشتقّة من مجموعة المعرّفات: تُبقي ترتيب «لك» مستقرًّا بين
    // عمليات إعادة البناء (يُقرأ هذا الـ getter بكثرة)، وتتغيّر فقط عند
    // تغيّر المحتوى الفعليّ. بدونها كان `rank` يستعمل
    // `Random(DateTime.now())` فيهتزّ الترتيب في كلّ rebuild.
    final seed = Object.hashAll(allContent.keys);
    return RecommendationService.instance
        .rank(allContent.values, seed: seed)
        .toList();
  }

  bool _isArabicIslamicSection(HomeSection s) {
    final title = normalizeText(s.title);
    if (title.isEmpty) return false;
    const islamicHints = <String>[
      'قرا',
      'قران',
      'مصحف',
      'تلاو',
      'تجويد',
      'حديث',
      'سنه',
      'صحيح',
      'بخاري',
      'مسلم',
      'فقه',
      'احكام',
      'فتاو',
      'عقيده',
      'توحيد',
      'ايمان',
      'سير',
      'صحاب',
      'تاريخ اسلام',
      'عربي',
      'لغه',
      'نحو',
      'islam',
      'quran',
      'hadith',
      'arabic',
      'islamic',
      'muslim',
      'sunnah',
    ];
    for (final hint in islamicHints) {
      if (title.contains(hint)) return true;
    }
    return false;
  }

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasMore => _hasMore;
  int get currentPage => _currentPage;
  bool get isFetchingMore => _isFetchingMore;

  /// يحدّث اللغة المستهدفة لشجرة البيانات. يبقى نقطة توسعة آمنة (لا يطلق
  /// شبكة بنفسه — الـ stream يتولّى التزامن).
  void setLocale(String locale) {
    if (_currentLocale == locale) return;
    _currentLocale = locale;
  }

  /// يبدأ اشتراكاً مباشراً مع Cloud Firestore عبر `snapshots()` — أيّ محتوى
  /// أو قسم جديد من لوحة التحكّم يصل إلى هذه الشاشة خلال ميلّي ثانية بدون
  /// الحاجة لمسح بيانات التطبيق أو إعادة تشغيله.
  ///
  /// - يُستدعى مرّة واحدة من HomeScreen.initState، ومرّة أخرى إن رغبنا
  ///   بإعادة تأسيس الاتصال (مثلاً بعد استعادة الشبكة أو بعد استقبال
  ///   إشعار FCM).
  /// - آمن لاستدعائه أكثر من مرّة؛ يُلغي الاشتراك القديم قبل فتح جديد.
  void startWatching() {
    _liveSub?.cancel();

    if (_firebaseSections.isEmpty) {
      // عرض فوريّ: نبذُر الشاشة بآخر لقطة محفوظة محليّاً (Hive) كي يظهر
      // المحتوى لحظة فتح التطبيق للمستخدم العائد بدل skeleton متحرّك لثوانٍ.
      // أوّل لقطة حيّة من Firestore ستستبدل هذه اللقطة بالشجرة الكاملة.
      final cached = _getHomeDataUseCase.cached();
      if (cached.isNotEmpty) {
        _firebaseSections = cached;
        _isLoading = false;
        _errorMessage = null;
        _currentPage = 1;
        unawaited(_rebuildHomeRails());
      } else {
        // أوّل تثبيت — لا كاش محلّي بعد، فلا مفرّ من انتظار الشبكة.
        _isLoading = true;
        _errorMessage = null;
        _currentPage = 1;
      }
      notifyListeners();
    }

    _liveSub = _getHomeDataUseCase
        .watch(page: 1)
        .listen(
          (result) {
            _firebaseSections = result;
            _hasMore = result.isNotEmpty;
            _currentPage = 1;
            _isLoading = false;
            _errorMessage = null;

            final totalItems = _firebaseSections.fold<int>(
              0,
              (prev, s) => prev + s.items.length,
            );
            debugPrint(
              '[HomeProvider] live update: sections=${_firebaseSections.length}, items=$totalItems',
            );
            unawaited(_rebuildHomeRails());
            notifyListeners();
          },
          onError: (Object err, StackTrace st) {
            debugPrint('[HomeProvider] live stream error: $err');
            _isLoading = false;
            _errorMessage = err.toString();
            notifyListeners();
          },
        );

    // في الإنترنت الضعيف قد لا ترسل Firestore أوّل snapshot بسرعة. بعد 3 ثوانٍ
    // نقرأ مسار getHomeData الذي يملك fallback من Hive، فلا تبقى الشاشة عالقة.
    Future<void>.delayed(weakNetworkBootTimeout, () {
      if (_isLoading && _firebaseSections.isEmpty) {
        unawaited(_loadInitialFromWeakNetworkFallback());
      }
    });
  }

  Future<void> _loadInitialFromWeakNetworkFallback() async {
    _isLoading = false;
    await loadInitial();
  }

  // ── Load initial data (fallback — يستخدم قراءة لمرّة واحدة) ────────
  Future<void> loadInitial() async {
    if (_isLoading) return;

    _isLoading = true;
    _errorMessage = null;
    _currentPage = 1;
    _hasMore = true;
    notifyListeners();

    try {
      final result = await _getHomeDataUseCase(
        page: 1,
      ).timeout(_fetchTimeout);
      _firebaseSections = result;
      _hasMore = result.isNotEmpty;
      _currentPage = 1;
      _isLoading = false;

      final totalItems = _firebaseSections.fold<int>(
        0,
        (prev, s) => prev + s.items.length,
      );
      debugPrint(
        '[HomeProvider] sections loaded: ${_firebaseSections.length}, total items: $totalItems',
      );

      unawaited(_rebuildHomeRails());
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  Future<void> _rebuildHomeRails() async {
    if (_railsBuilding || _firebaseSections.isEmpty) return;
    _railsBuilding = true;
    try {
      // لا ننتظر شبكة الشعبيّة هنا: كان `await loadPopularIds()` يحجب بناء
      // الرفوف على قراءة Firestore (أوّل إقلاع أو بعد انتهاء صلاحيّة الكاش)
      // فتبقى الرئيسية تعرض مؤشّر تحميل ثوانٍ — وهو ما يبدو "تمريراً يبحث عن
      // محتوى". نبني فوراً بمعرّفات الشعبيّة المتوفّرة في الذاكرة (قد تكون
      // فارغة، فيسقط رفّ "الأكثر مشاهدة" تلقائياً على ترتيب view_count محليّاً)
      // ثم نُحدّثها في الخلفيّة عند أوّل إقلاع.
      final popularIds = PopularityFeedService.instance.popularIds;
      final built = await HomeRailBuilders.buildAll(
        sections: _firebaseSections,
        rankedSections: sections,
        popularIds: popularIds,
        personalized: _personalizationEnabled,
      );
      _homeRails = built;
      notifyListeners();
    } catch (e) {
      debugPrint('[HomeProvider] rebuild rails failed: $e');
    } finally {
      _railsBuilding = false;
    }

    // تحديث معرّفات الشعبيّة من الشبكة مرّة واحدة لكلّ جلسة (تبقى في الذاكرة
    // بعدها) ثمّ إعادة بناء الرفوف فقط إن تغيّرت — دون أن نحجب أوّل عرض
    // للمحتوى، ودون إغراق السجلّ بمحاولات متكرّرة إن رُفضت القراءة.
    if (!_popularRefreshAttempted &&
        PopularityFeedService.instance.popularIds.isEmpty) {
      _popularRefreshAttempted = true;
      unawaited(_refreshPopularIdsThenRebuild());
    }
  }

  Future<void> _refreshPopularIdsThenRebuild() async {
    try {
      final updated = await PopularityFeedService.instance.loadPopularIds();
      if (updated.isEmpty || _firebaseSections.isEmpty) return;
      final built = await HomeRailBuilders.buildAll(
        sections: _firebaseSections,
        rankedSections: sections,
        popularIds: updated,
      );
      _homeRails = built;
      notifyListeners();
    } catch (e) {
      debugPrint('[HomeProvider] popular refresh failed: $e');
    }
  }

  /// يُستدعى من الواجهة عند تغيّر ملفّ الاهتمامات.
  Future<void> refreshHomeRails() => _rebuildHomeRails();

  // ── Pull-to-refresh ────────────────────────────────────────
  Future<void> refresh() async {
    // إن كنّا مشتركين بالـ live stream، أعد الاشتراك لإجبار Firestore على
    // إعادة الإرسال (مفيد عند استرجاع الشبكة بعد انقطاع).
    if (_hasLiveSubscription) {
      startWatching();
      return;
    }

    _errorMessage = null;
    _currentPage = 1;
    _hasMore = true;

    try {
      final result = await _getHomeDataUseCase(page: 1);
      _firebaseSections = result;
      _hasMore = result.isNotEmpty;
      _currentPage = 1;

      final totalItems = _firebaseSections.fold<int>(
        0,
        (prev, s) => prev + s.items.length,
      );
      debugPrint(
        '[HomeProvider] refresh sections: ${_firebaseSections.length}, total items: $totalItems',
      );

      unawaited(_rebuildHomeRails());
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  // ── Load more (pagination) ─────────────────────────────────
  Future<void> loadMore() async {
    final canFirebase = !_isFetchingMore && _hasMore;
    if (!canFirebase) return;

    _isFetchingMore = true;
    notifyListeners();

    try {
      final nextPage = _currentPage + 1;
      final result = await _getHomeDataUseCase(page: nextPage);
      if (result.isEmpty) {
        _hasMore = false;
      } else {
        _firebaseSections = _mergeSections(_firebaseSections, result);
        _currentPage = nextPage;
      }
    } catch (e) {
      debugPrint('Failed to load more (firebase): $e');
    }

    _isFetchingMore = false;
    notifyListeners();
  }

  Future<void> retry() async {
    startWatching();
  }

  List<HomeSection> _mergeSections(
    List<HomeSection> current,
    List<HomeSection> incoming,
  ) {
    final merged = <String, HomeSection>{};

    for (final section in current) {
      merged[section.id] = section;
    }

    for (final section in incoming) {
      final existing = merged[section.id];
      if (existing == null) {
        merged[section.id] = section;
        continue;
      }

      final itemsById = <String, Content>{};
      for (final item in existing.items) {
        itemsById[item.id] = item;
      }
      for (final item in section.items) {
        itemsById[item.id] = item;
      }

      merged[section.id] = HomeSection(
        id: section.id,
        title: section.title,
        type: section.type,
        parentId: section.parentId ?? existing.parentId,
        imageUrl: section.imageUrl ?? existing.imageUrl,
        archiveId: section.archiveId ?? existing.archiveId,
        remoteSourceApp: section.remoteSourceApp ?? existing.remoteSourceApp,
        remoteSourceLevel:
            section.remoteSourceLevel ?? existing.remoteSourceLevel,
        remoteSourceId: section.remoteSourceId ?? existing.remoteSourceId,
        items: itemsById.values.toList(),
      );
    }

    return merged.values.toList();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _idleTimer = null;
    _liveSub?.cancel();
    _liveSub = null;
    UserBehaviorTracker.instance.removeListener(_onTrackerChanged);
    super.dispose();
  }
}

class _ScoredSection {
  final HomeSection section;
  final int index;
  final double score;
  const _ScoredSection({
    required this.section,
    required this.index,
    required this.score,
  });
}
