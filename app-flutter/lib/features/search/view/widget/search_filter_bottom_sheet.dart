import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nebras_mobile_app/core/extensions/sized_boxextension.dart';
import 'package:nebras_mobile_app/core/theme/color_manager.dart';
import 'package:nebras_mobile_app/core/theme/text_styles.dart';
import 'package:nebras_mobile_app/features/content/model/content_model.dart';
import 'package:nebras_mobile_app/features/search/provider/search_provider.dart';
import 'package:provider/provider.dart';

/// Bottom sheet for search filters
/// Content type, section, subsection, clear filters
class SearchFilterBottomSheet extends StatelessWidget {
  const SearchFilterBottomSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<SearchProvider>(),
        child: const SearchFilterBottomSheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SearchProvider>(
      builder: (context, provider, _) {
        return Padding(
          padding: EdgeInsets.fromLTRB(24.w, 16.h, 24.w, 24.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40.w,
                  height: 4.h,
                  decoration: BoxDecoration(
                    color: Theme.of(context).dividerColor,
                    borderRadius: BorderRadius.circular(2.r),
                  ),
                ),
              ),
              16.sbh,

              // Title + clear
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Filters'.tr(), style: TextStyles.heading3(context)),
                  if (provider.hasActiveFilters)
                    TextButton(
                      onPressed: () {
                        provider.clearFilters();
                        Navigator.pop(context);
                      },
                      child: Text(
                        'Clear All'.tr(),
                        style: TextStyle(
                          color: ColorsManager.error,
                          fontSize: 14.sp,
                        ),
                      ),
                    ),
                ],
              ),
              16.sbh,

              // Content Type
              Text('Content Type'.tr(), style: TextStyles.bodyBold(context)),
              8.sbh,
              Wrap(
                spacing: 8.w,
                children: [
                  _buildTypeChip(context, provider, null, 'All'.tr()),
                  _buildTypeChip(
                    context,
                    provider,
                    ContentType.video,
                    'Video'.tr(),
                  ),
                  _buildTypeChip(
                    context,
                    provider,
                    ContentType.audio,
                    'Audio'.tr(),
                  ),
                  _buildTypeChip(
                    context,
                    provider,
                    ContentType.book,
                    'Book'.tr(),
                  ),
                ],
              ),
              16.sbh,

              // Sections
              if (provider.sections.isNotEmpty) ...[
                Text('Section'.tr(), style: TextStyles.bodyBold(context)),
                8.sbh,
                Wrap(
                  spacing: 8.w,
                  runSpacing: 8.h,
                  children: [
                    _buildSectionChip(context, provider, null, 'All'.tr()),
                    ...provider.sections.map(
                      (section) => _buildSectionChip(
                        context,
                        provider,
                        section.id,
                        section.name,
                      ),
                    ),
                  ],
                ),
                16.sbh,
              ],

              // Apply button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ColorsManager.primary,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 14.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                  ),
                  child: Text('Apply Filters'.tr()),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTypeChip(
    BuildContext context,
    SearchProvider provider,
    ContentType? type,
    String label,
  ) {
    final isSelected = provider.selectedType == type;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => provider.setTypeFilter(type),
      selectedColor: Theme.of(
        context,
      ).colorScheme.primary.withValues(alpha: 0.2),
      checkmarkColor: Theme.of(context).colorScheme.primary,
      backgroundColor: Theme.of(context).cardColor,
      side: BorderSide(
        color: isSelected
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).dividerColor,
      ),
    );
  }

  Widget _buildSectionChip(
    BuildContext context,
    SearchProvider provider,
    String? section,
    String label,
  ) {
    final isSelected = provider.selectedSection == section;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => provider.setSectionFilter(section),
      selectedColor: Theme.of(
        context,
      ).colorScheme.primary.withValues(alpha: 0.2),
      checkmarkColor: Theme.of(context).colorScheme.primary,
      backgroundColor: Theme.of(context).cardColor,
      side: BorderSide(
        color: isSelected
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).dividerColor,
      ),
    );
  }
}
