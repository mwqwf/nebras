import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:nebras_mobile_app/core/services/search_result_item.dart';
import 'package:nebras_mobile_app/core/services/search_service.dart';
import 'package:nebras_mobile_app/core/services/interest_profile_service.dart';
import 'package:nebras_mobile_app/core/services/user_behavior_tracker.dart';
import 'package:nebras_mobile_app/features/content/model/content_model.dart';
import 'package:nebras_mobile_app/features/home/data/home_section_model.dart';
import 'package:nebras_mobile_app/features/search/data/search_section_option.dart';
import 'package:nebras_mobile_app/features/search/domain/usecase/search_content_usecase.dart';
import 'package:nebras_mobile_app/features/search/domain/usecase/get_sections_usecase.dart';
import 'package:nebras_mobile_app/features/search/domain/usecase/get_section_content_usecase.dart';

/// SearchProvider — يدير حالة شاشة البحث وفق المتطلبات الجديدة:
///   * البحث في **الأقسام والمحتوى** معًا.
///   * عرض نتائج مدموجة ومرتّبة بـ Relevance Scoring.
///   * توجيه ذكيّ: المستهلك (UI) يقرأ `SearchHit.kind` ليعرف هل يفتح
///     شاشة تصفّح القسم أم مشغّل الميديا.
class SearchProvider extends ChangeNotifier {
  final SearchContentUseCase _searchContentUseCase;
  final GetSectionsUseCase _getSectionsUseCase;
  final GetSectionContentUseCase _getSectionContentUseCase;

  late final SearchService _searchService;

  SearchProvider(
    this._searchContentUseCase,
    this._getSectionsUseCase,
    this._getSectionContentUseCase, {
    SearchService? searchService,
  }) {
    _searchService = searchService ??
        SearchService(
          firebaseUseCase: _searchContentUseCase,
        );
    // سجلّ البحث يعيش داخل UserBehaviorTracker (singleton)؛ نستمع إليه
    // لكي تُعاد رسم شاشة البحث تلقائيًّا عند إضافة/حذف كلمة سجل.
    UserBehaviorTracker.instance.addListener(_onBehaviorChanged);
  }

  void _onBehaviorChanged() {
    notifyListeners();
  }

  // ── State ──────────────────────────────────────────────────
  String _query = '';
  ContentType? _selectedType;
  String? _selectedSection;
  String? _selectedSubSection;
  List<SearchSectionOption> _sections = [];

  /// نتائج موحَّدة (أقسام + محتوى) قابلة للعرض مباشرةً في الـ UI.
  List<SearchResultItem> _hits = const [];

  /// اقتراحات جانبيّة — تُعرَض أسفل النتائج بعنوان "قد يعجبك أيضاً".
  List<SearchResultItem> _suggestions = const [];

  /// سبب ملء النتائج من fallback — تقرؤها الواجهة لعرض ترويسة توضيحيّة
  SearchFallbackReason _fallbackReason = SearchFallbackReason.none;

  /// الأقسام الحاليّة المتاحة للبحث المحلّيّ.
  List<HomeSection> _sectionsForSearch = const [];

  bool _isLoading = false;
  String? _errorMessage;
  Timer? _debounceTimer;
  bool _disposed = false;

  // ── Getters ────────────────────────────────────────────────
  String get query => _query;
  ContentType? get selectedType => _selectedType;
  String? get selectedSection => _selectedSection;
  String? get selectedSubSection => _selectedSubSection;

  /// النتائج المدمجة (أقسام أوّلاً ثمّ محتوى).
  List<SearchResultItem> get hits => _hits;

  /// اقتراحات جانبيّة — "قد يعجبك أيضاً".
  List<SearchResultItem> get suggestions => _suggestions;

  /// سبب ملء القائمة من fallback (إن وُجد).
  SearchFallbackReason get fallbackReason => _fallbackReason;

  /// هل النتائج المعروضة ليست تطابقات حقيقيّة بل أقرب ما وجدناه؟
  bool get usedFallback => _fallbackReason != SearchFallbackReason.none;

  /// توافقيّة خلفيّة — نُعيد المحتوى فقط لمن يعتمد على القائمة القديمة.
  List<Content> get results => [
        for (final h in _hits)
          if (h.type == SearchItemType.item && h.content != null) h.content!,
      ];

  List<SearchSectionOption> get sections => _sections;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasActiveFilters =>
      _selectedType != null ||
      _selectedSection != null ||
      _selectedSubSection != null;

  // ── سجلّ البحث (Search History) ────────────────────────────
  List<String> get recentSearches =>
      UserBehaviorTracker.instance.lastSearches;

  Future<void> removeRecentSearch(String query) {
    return UserBehaviorTracker.instance.removeSearch(query);
  }

  Future<void> clearSearchHistory() {
    return UserBehaviorTracker.instance.clearSearchHistory();
  }

  void submitRecentSearch(String query) {
    final q = query.trim();
    if (q.isEmpty) return;
    _debounceTimer?.cancel();
    _query = q;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    unawaited(_executeSearch());
  }

  void submitCurrentQuery([String? override]) {
    final q = (override ?? _query).trim();
    if (q.isEmpty) return;
    _debounceTimer?.cancel();
    _query = q;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    unawaited(_executeSearch());
  }

  void setSectionsForSearch(List<HomeSection> sections) {
    final hadSections = _sectionsForSearch.isNotEmpty;
    _sectionsForSearch = sections;
    final hasSectionsNow = _sectionsForSearch.isNotEmpty;
    if (!hadSections && hasSectionsNow && _query.trim().isNotEmpty) {
      Future.microtask(() => _executeSearch());
    }
  }

  // ── Query with 400ms debounce ──────────────────────────────
  void onQueryChanged(String value) {
    _query = value;
    _debounceTimer?.cancel();

    if (value.trim().isEmpty) {
      _hits = const [];
      _suggestions = const [];
      _fallbackReason = SearchFallbackReason.none;
      _isLoading = false;
      _errorMessage = null;
      notifyListeners();
      return;
    }

    if (!_isLoading) {
      _isLoading = true;
      notifyListeners();
    }

    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      _executeSearch();
    });
  }

  // ── Filters ────────────────────────────────────────────────
  void setTypeFilter(ContentType? type) {
    _selectedType = type;
    notifyListeners();
    if (_query.trim().isNotEmpty) _executeSearch();
  }

  void setSectionFilter(String? section) {
    _selectedSection = section;
    _selectedSubSection = null;
    notifyListeners();
    if (_query.trim().isNotEmpty) _executeSearch();
  }

  void setSubSectionFilter(String? subSection) {
    _selectedSubSection = subSection;
    notifyListeners();
    if (_query.trim().isNotEmpty) _executeSearch();
  }

  void clearFilters() {
    _selectedType = null;
    _selectedSection = null;
    _selectedSubSection = null;
    notifyListeners();
    if (_query.trim().isNotEmpty) _executeSearch();
  }

  void clearAll() {
    _query = '';
    _selectedType = null;
    _selectedSection = null;
    _selectedSubSection = null;
    _hits = const [];
    _suggestions = const [];
    _fallbackReason = SearchFallbackReason.none;
    _errorMessage = null;
    _debounceTimer?.cancel();
    notifyListeners();
  }

  // ── Load sections ──────────────────────────────────────────
  Future<void> loadSections() async {
    try {
      _sections = await _getSectionsUseCase();
      debugPrint('[SearchProvider] sections loaded: ${_sections.length}');
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load sections: $e');
    }
  }

  Future<List<Content>> loadSectionContent(String sectionId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final items = await _getSectionContentUseCase(sectionId);
      debugPrint(
        '[SearchProvider] section "$sectionId" content count: ${items.length}',
      );
      _isLoading = false;
      notifyListeners();
      return items;
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString();
      notifyListeners();
      return [];
    }
  }

  // ── Execute search (internal) ──────────────────────────────
  Future<void> _executeSearch() async {
    if (_query.trim().isEmpty) return;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final String currentQuery = _query.trim();
    // لقطة من الفلاتر وقت إطلاق البحث. عمليّات `_executeSearch` المتتالية
    // (تغيير النوع/القسم بسرعة) تحمل نفس الاستعلام، فالاكتفاء بفحص
    // الاستعلام كان يسمح لنتيجة فلتر قديمة بالكتابة فوق نتيجة أحدث.
    final ContentType? reqType = _selectedType;
    final String? reqSection = _selectedSection;
    final String? reqSubSection = _selectedSubSection;

    try {
      final result = await _searchService.search(
        query: currentQuery,
        sections: _effectiveSectionsForSearch(),
        type: reqType,
        section: reqSection,
        subSection: reqSubSection,
      );

      if (_query.trim() != currentQuery ||
          _selectedType != reqType ||
          _selectedSection != reqSection ||
          _selectedSubSection != reqSubSection) {
        _isLoading = false;
        notifyListeners();
        return;
      }

      _hits = result.items;
      _suggestions = result.suggestions;
      _fallbackReason = result.fallbackReason;
      _isLoading = false;
      notifyListeners();

      debugPrint(
        '[SearchProvider] unified search: results=${_hits.length}, '
        'suggestions=${_suggestions.length}, fallback=${_fallbackReason.name}, '
        'query="$currentQuery", sectionsForSearch=${_effectiveSectionsForSearch().length}',
      );

      final realMatch = result.isNotEmpty && !result.usedFallback;
      if (realMatch) {
        unawaited(UserBehaviorTracker.instance.recordSearch(currentQuery));
        unawaited(InterestProfileService.instance.onSearchQuery(currentQuery));
      }
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  /// يمنع `notifyListeners` من العمل بعد التخلّص — عمليّات البحث
  /// (أو سجلّ السلوك) قد تكتمل بعد إغلاق الشاشة فتستدعي notify على
  /// notifier متخلَّص منه ⇒ "used after being disposed".
  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    UserBehaviorTracker.instance.removeListener(_onBehaviorChanged);
    super.dispose();
  }

  List<HomeSection> _effectiveSectionsForSearch() {
    if (_sectionsForSearch.isNotEmpty) return _sectionsForSearch;
    if (_sections.isEmpty) return const [];
    return _sections
        .map(
          (e) => HomeSection(
            id: 'main:${e.id}',
            title: e.name,
            type: 'main_section',
            items: const [],
          ),
        )
        .toList(growable: false);
  }
}
