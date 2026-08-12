import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nebras_mobile_app/core/widgets/search_baar_widget.dart';
import 'package:nebras_mobile_app/core/widgets/skeleton_loader.dart';
import 'package:nebras_mobile_app/features/home/providers/home_provider.dart';
import 'package:nebras_mobile_app/features/search/provider/search_provider.dart';
import 'package:nebras_mobile_app/features/search/view/widget/search_filter_bottom_sheet.dart';
import 'package:nebras_mobile_app/features/search/view/widget/search_results_panel.dart';
import 'package:provider/provider.dart';

/// صفحة البحث المخصّصة — تُفتح عند الضغط على أيقونة البحث في الشريط
/// العلويّ (نمط YouTube). نُقلت هنا حرفياً كلّ وظائف البحث التي كانت
/// مدمجة سابقاً داخل شريط البحث في الرئيسية، **دون أيّ فقدان للوظائف**:
///   • شريط بحث مع تركيز تلقائيّ.
///   • سجلّ عمليات البحث الأخيرة (يظهر عند فراغ الاستعلام والتركيز).
///   • النتائج الحيّة + الاقتراحات + سبب الاحتياط (fallback).
///   • هيكل تحميل أثناء الجلب.
/// نعيد استخدام نفس [SearchProvider] العموميّ، فالسجلّ والحالة محفوظان.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
    // مزامنة قيمة الحقل مع الاستعلام الحاليّ في الـ provider (إن وُجد).
    final search = context.read<SearchProvider>();
    if (search.query.isNotEmpty) {
      _controller.text = search.query;
      _controller.selection = TextSelection.collapsed(
        offset: search.query.length,
      );
    }
    // نضمن وصول أقسام البحث للـ provider (نفس ما كان يفعله شريط الرئيسية).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final home = context.read<HomeProvider>();
      context.read<SearchProvider>().setSectionsForSearch(home.sectionsRaw);
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final search = context.watch<SearchProvider>();
    final hasQuery = search.query.trim().isNotEmpty;
    final showRecent =
        !hasQuery && search.recentSearches.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: EdgeInsets.only(right: 12.w),
          child: SearchBarWidget(
            controller: _controller,
            focusNode: _focusNode,
            searchQuery: search.query,
            hintText: 'Search content...'.tr(),
            onChanged: (value) {
              context.read<HomeProvider>().resetIdleTimer();
              search.onQueryChanged(value);
            },
            onSubmitted: (value) {
              search.submitCurrentQuery(value);
              _focusNode.unfocus();
            },
            onClear: () {
              _controller.clear();
              search.clearAll();
              _focusNode.requestFocus();
            },
          ),
        ),
        actions: [
          // أيقونة الفلاتر — تفتح SearchFilterBottomSheet الجاهزة.
          // نقطة صغيرة تظهر عند وجود فلاتر فعّالة.
          Padding(
            padding: EdgeInsets.only(left: 4.w, right: 4.w),
            child: Stack(
              alignment: Alignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.tune_rounded),
                  tooltip: 'Filters'.tr(),
                  onPressed: () => SearchFilterBottomSheet.show(context),
                ),
                if (search.hasActiveFilters)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 24.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasQuery)
                search.isLoading
                    ? const SearchSkeletonLoader()
                    : SearchResultsPanel(
                        hits: search.hits,
                        suggestions: search.suggestions,
                        fallbackReason: search.fallbackReason,
                      )
              else if (showRecent)
                RecentSearchesPanel(
                  recentSearches: search.recentSearches,
                  onSelect: (term) {
                    _controller.text = term;
                    _controller.selection = TextSelection.collapsed(
                      offset: term.length,
                    );
                    search.submitRecentSearch(term);
                    _focusNode.unfocus();
                  },
                  onRemove: search.removeRecentSearch,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
