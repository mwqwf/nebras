import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nebras_mobile_app/core/extensions/sized_boxextension.dart';
import 'package:nebras_mobile_app/core/media/content_context.dart';
import 'package:nebras_mobile_app/core/theme/color_manager.dart';
import 'package:nebras_mobile_app/core/theme/text_styles.dart';
import 'package:nebras_mobile_app/core/widgets/app_bar_widget.dart';
import 'package:nebras_mobile_app/core/widgets/empty_state_widget.dart';
import 'package:nebras_mobile_app/core/widgets/smart_network_image.dart';
import 'package:nebras_mobile_app/core/data/content_ordering.dart';
import 'package:nebras_mobile_app/features/content/model/content_model.dart';
import 'package:nebras_mobile_app/features/content/view/content_router.dart.dart';
import 'package:nebras_mobile_app/features/search/provider/search_provider.dart';
import 'package:provider/provider.dart';

/// Search Result Screen
/// Shows content for a specific section
/// Navigated to when user taps a section chip
class SearchResultScreen extends StatefulWidget {
  final String sectionId;
  final String title;

  const SearchResultScreen({
    super.key,
    required this.sectionId,
    required this.title,
  });

  @override
  State<SearchResultScreen> createState() => _SearchResultScreenState();
}

class _SearchResultScreenState extends State<SearchResultScreen> {
  List<Content> _items = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  Future<void> _loadContent() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final provider = context.read<SearchProvider>();
      final items = await provider.loadSectionContent(widget.sectionId);
      // الأقدم أولاً — انظر lib/core/data/content_ordering.dart
      final sorted = List<Content>.of(items)..sort(compareContentOldestFirst);
      if (mounted) {
        setState(() {
          _items = sorted;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  IconData _typeIcon(ContentType type) {
    switch (type) {
      case ContentType.video:
      case ContentType.youtube:
        return Icons.play_circle_outline;
      case ContentType.audio:
        return Icons.headphones;
      case ContentType.book:
        return Icons.menu_book;
      case ContentType.image:
        return Icons.image_outlined;
      case ContentType.article:
        return Icons.article_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBarWidget(title: widget.title),
      body: SafeArea(child: _buildContent()),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48.sp, color: ColorsManager.error),
            12.sbh,
            Text(
              _error!,
              style: TextStyles.body(context),
              textAlign: TextAlign.center,
            ),
            12.sbh,
            TextButton(onPressed: _loadContent, child: Text('Retry'.tr())),
          ],
        ),
      );
    }

    if (_items.isEmpty) {
      return Center(
        child: EmptyStateWidget(message: 'No content in this section'.tr()),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final content = _items[index];
        return GestureDetector(
          onTap: () => ContentRouter.open(
            context,
            content,
            contentContext: ContentContext.search,
          ),
          child: Container(
            margin: EdgeInsets.only(bottom: 12.h),
            padding: EdgeInsets.all(12.w),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12.r),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8.r),
                  child: SmartNetworkImage(
                    imageUrl: content.thumbnailUrl,
                    title: content.title,
                    iconOverride: _typeIcon(content.type),
                    width: 64.w,
                    height: 64.w,
                  ),
                ),
                12.sbw,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        content.title,
                        style: TextStyles.bodyBold(context),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      4.sbh,
                      Text(
                        content.type.name.tr(),
                        style: TextStyles.greysmallText(context),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 24.sp,
                  color: ColorsManager.greycolor,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
