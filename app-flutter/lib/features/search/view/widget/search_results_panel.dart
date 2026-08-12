import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nebras_mobile_app/core/extensions/sized_boxextension.dart';
import 'package:nebras_mobile_app/core/media/content_context.dart';
import 'package:nebras_mobile_app/core/services/search_result_item.dart';
import 'package:nebras_mobile_app/core/services/search_service.dart';
import 'package:nebras_mobile_app/core/services/section_router.dart';
import 'package:nebras_mobile_app/core/theme/color_manager.dart';
import 'package:nebras_mobile_app/core/theme/text_styles.dart';
import 'package:nebras_mobile_app/core/widgets/fade_in_list_item.dart';
import 'package:nebras_mobile_app/core/widgets/smart_network_image.dart';
import 'package:nebras_mobile_app/features/content/view/content_router.dart.dart';
import 'package:nebras_mobile_app/features/search/data/search_section_option.dart';

/// لوحة سجلّ البحث على نمط YouTube/Google: قائمة عموديّة نظيفة، كلّ صفّ
/// يحوي أيقونة ساعة + الكلمة + زرّ إزالة (×). تظهر فقط حين يكون شريط
/// البحث في حالة تركيز والاستعلام فارغ — تماماً كاقتراحات YouTube عند
/// النقر على الشريط دون كتابة. لا توجد رؤوس "Recent searches" أو زرّ
/// "Clear" لأنّ التصميم يعتمد البساطة كما في التطبيقات الكبرى.
class RecentSearchesPanel extends StatelessWidget {
  const RecentSearchesPanel({
    super.key,
    required this.recentSearches,
    required this.onSelect,
    required this.onRemove,
  });

  final List<String> recentSearches;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    if (recentSearches.isEmpty) return const SizedBox.shrink();
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final term in recentSearches)
          InkWell(
            onTap: () => onSelect(term),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 10.h),
              child: Row(
                children: [
                  Icon(
                    Icons.history,
                    size: 22.sp,
                    color: onSurface.withValues(alpha: 0.55),
                  ),
                  16.sbw,
                  Expanded(
                    child: Text(
                      term,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyles.body(context),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      size: 18.sp,
                      color: onSurface.withValues(alpha: 0.55),
                    ),
                    splashRadius: 18,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: 'Remove'.tr(),
                    onPressed: () => onRemove(term),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class SearchResultsPanel extends StatelessWidget {
  const SearchResultsPanel({
    super.key,
    required this.hits,
    required this.suggestions,
    required this.fallbackReason,
  });

  final List<SearchResultItem> hits;
  final List<SearchResultItem> suggestions;
  final SearchFallbackReason fallbackReason;

  @override
  Widget build(BuildContext context) {
    final fallbackTitle = switch (fallbackReason) {
      SearchFallbackReason.none => null,
      SearchFallbackReason.closestSection => 'Closest matches'.tr(),
      SearchFallbackReason.popular => 'Popular picks'.tr(),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (fallbackTitle != null) ...[
          _SectionHeader(
            icon: Icons.auto_awesome_outlined,
            title: fallbackTitle,
          ),
          8.sbh,
        ],
        for (var i = 0; i < hits.length; i++)
          FadeInListItem(
            index: i,
            child: _SearchHitTile(hit: hits[i]),
          ),
        if (suggestions.isNotEmpty) ...[
          12.sbh,
          _SectionHeader(
            icon: Icons.recommend_outlined,
            title: 'You may also like'.tr(),
          ),
          8.sbh,
          for (var i = 0; i < suggestions.length; i++)
            FadeInListItem(
              index: hits.length + i,
              child: _SearchHitTile(hit: suggestions[i]),
            ),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18.sp, color: Theme.of(context).colorScheme.primary),
        8.sbw,
        Text(title, style: TextStyles.bodyBold(context)),
      ],
    );
  }
}

class _SearchHitTile extends StatelessWidget {
  const _SearchHitTile({required this.hit});
  final SearchResultItem hit;

  @override
  Widget build(BuildContext context) {
    final isSection = hit.type == SearchItemType.section;
    return Card(
      margin: EdgeInsets.only(bottom: 8.h),
      child: ListTile(
        leading: SizedBox(
          width: 48.w,
          height: 48.w,
          child: isSection || hit.imageUrl == null
              ? Icon(
                  isSection ? Icons.folder_outlined : Icons.play_circle_outline,
                  color: ColorsManager.primary,
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(8.r),
                  child: SmartNetworkImage(
                    imageUrl: hit.imageUrl!,
                    title: hit.title,
                  ),
                ),
        ),
        title: Text(hit.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          hit.subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () => _open(context),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    if (hit.type == SearchItemType.section && hit.section != null) {
      await SectionRouter.open(context, hit.section!);
      return;
    }
    final content = hit.content;
    if (content == null) return;
    await ContentRouter.open(
      context,
      content,
      contentContext: ContentContext.search,
    );
  }
}

class SearchSectionChipRow extends StatelessWidget {
  const SearchSectionChipRow({
    super.key,
    required this.sections,
    required this.onSelect,
  });

  final List<SearchSectionOption> sections;
  final ValueChanged<SearchSectionOption> onSelect;

  @override
  Widget build(BuildContext context) {
    if (sections.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 44.h,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: sections.length,
        separatorBuilder: (_, _) => 8.sbw,
        itemBuilder: (context, index) {
          final section = sections[index];
          return ActionChip(
            label: Text(section.name, style: TextStyles.smallText(context)),
            onPressed: () => onSelect(section),
          );
        },
      ),
    );
  }
}
