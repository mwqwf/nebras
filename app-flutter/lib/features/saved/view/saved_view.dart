import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nebras_mobile_app/core/extensions/sized_boxextension.dart';
import 'package:nebras_mobile_app/core/media/content_context.dart';
import 'package:nebras_mobile_app/core/services/hidden_content_service.dart';
import 'package:nebras_mobile_app/core/widgets/app_bar_widget.dart';
import 'package:nebras_mobile_app/core/widgets/empty_state_widget.dart';
import 'package:nebras_mobile_app/core/widgets/fade_in_list_item.dart';
import 'package:nebras_mobile_app/core/widgets/skeleton_loader.dart';
import 'package:nebras_mobile_app/features/content/model/content_model.dart';
import 'package:nebras_mobile_app/features/content/view/content_router.dart.dart';
import 'package:nebras_mobile_app/features/download/provider/media_download_provider.dart';
import 'package:nebras_mobile_app/features/saved/model/saved_item_model.dart';
import 'package:nebras_mobile_app/features/saved/provider/saved_provider.dart';
import 'package:nebras_mobile_app/features/saved/view/widget/saved_card_widget.dart';
import 'package:provider/provider.dart';

/// Saved Screen — shows all saved items with filter tabs
class SavedScreen extends StatefulWidget {
  const SavedScreen({super.key});

  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen>
    with AutomaticKeepAliveClientMixin {
  SavedContentType? _selectedFilter;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Load saved items when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SavedProvider>().loadSaved();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // إعادة بناء القائمة فور إخفاء محتوى مُبلَّغ عنه (التصفية في
    // SavedProvider.getFiltered تعتمد على HiddenContentService).
    context.watch<HiddenContentService>();
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBarWidget(title: 'Downloads'.tr()),
      body: SafeArea(
        child: Column(
          children: [
            // Filter tabs
            _buildFilterTabs(context),
            12.sbh,

            // Content
            Expanded(
              child: Consumer<SavedProvider>(
                builder: (context, provider, _) {
                  if (provider.isLoading) {
                    return const SavedSkeletonLoader();
                  }

                  final items = provider.getFiltered(_selectedFilter);

                  if (items.isEmpty) {
                    return Center(
                      child: EmptyStateWidget(
                        message: 'No saved content yet'.tr(),
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: EdgeInsets.symmetric(horizontal: 24.w),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return FadeInListItem(
                        index: index,
                        child: Dismissible(
                          key: Key(item.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: EdgeInsets.only(right: 24.w),
                            margin: EdgeInsets.only(bottom: 12.h),
                            decoration: BoxDecoration(
                              color: Colors.red.shade100,
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                            child: Icon(
                              Icons.delete_outline,
                              color: Colors.red,
                              size: 28.sp,
                            ),
                          ),
                          onDismissed: (_) {
                            HapticFeedback.mediumImpact();
                            final removed = item;
                            final downloadProvider =
                                context.read<MediaDownloadProvider>();
                            provider.remove(removed.id);
                            // احذف ملفّ التنزيل فقط إن كان له سجلّ تحميل
                            if (downloadProvider.hasDownload(removed.id)) {
                              downloadProvider.delete(removed.id);
                            }
                            final messenger = ScaffoldMessenger.of(context);
                            messenger.clearSnackBars();
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text('Removed from saved'.tr()),
                                duration: const Duration(seconds: 3),
                                action: SnackBarAction(
                                  label: 'Undo'.tr(),
                                  onPressed: () =>
                                      provider.restoreSaved(removed),
                                ),
                              ),
                            );
                          },
                          child: SavedCardWidget(
                            item: item,
                            isDownloaded: context
                                .read<MediaDownloadProvider>()
                                .getLocalPath(item.id) !=
                                null,
                            onTap: () => _openContent(context, item),
                            onRemove: () {
                              final downloadProvider =
                                  context.read<MediaDownloadProvider>();
                              provider.remove(item.id);
                              if (downloadProvider.hasDownload(item.id)) {
                                downloadProvider.delete(item.id);
                              }
                            },
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterTabs(BuildContext context) {
    final filters = <MapEntry<SavedContentType?, String>>[
      MapEntry(null, 'All'.tr()),
      MapEntry(SavedContentType.video, 'Video'.tr()),
      MapEntry(SavedContentType.audio, 'Audio'.tr()),
      MapEntry(SavedContentType.book, 'Book'.tr()),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 8.h),
      child: Row(
        children: filters.map((filter) {
          final isSelected = _selectedFilter == filter.key;
          return Padding(
            padding: EdgeInsets.only(right: 8.w),
            child: FilterChip(
              label: Text(filter.value),
              selected: isSelected,
              onSelected: (_) {
                setState(() => _selectedFilter = filter.key);
              },
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
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Convert SavedItemModel to Content and navigate via ContentRouter
  void _openContent(BuildContext context, SavedItemModel item) {
    // Map saved content type string to ContentType enum
    ContentType contentType;
    switch (item.contentType) {
      case 'audio':
        contentType = ContentType.audio;
        break;
      case 'book':
      case 'document':
        contentType = ContentType.book;
        break;
      case 'youtube':
        contentType = ContentType.youtube;
        break;
      case 'video':
      default:
        contentType = ContentType.video;
        break;
    }

    // Build a lightweight Content for ContentRouter
    final content = Content(
      id: item.id,
      title: item.title,
      author: '',
      description: '',
      type: contentType,
      thumbnailUrl: item.imageUrl ?? '',
      section: '',
      createdAt: item.savedAt,
      updatedAt: item.savedAt,
      createdBy: '',
      // For saved/downloaded content, resolve URL from download provider
      sourceUrl: _resolveSourceUrl(context, item),
    );

    ContentRouter.open(context, content, contentContext: ContentContext.saved);
  }

  /// Get source URL — prefer local path, fallback to download record URL
  String? _resolveSourceUrl(BuildContext context, SavedItemModel item) {
    final downloadProvider = context.read<MediaDownloadProvider>();
    // Try local path first (already downloaded)
    final localPath = downloadProvider.getLocalPath(item.id);
    if (localPath != null) return localPath;
    // Fallback: get URL from download record
    final download = downloadProvider.downloads[item.id];
    return download?.url;
  }
}
