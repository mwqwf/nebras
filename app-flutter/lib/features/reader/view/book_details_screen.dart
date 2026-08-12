import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nebras_mobile_app/core/di/setup_locator.dart';
import 'package:nebras_mobile_app/core/extensions/sized_boxextension.dart';
import 'package:nebras_mobile_app/core/theme/text_styles.dart';
import 'package:nebras_mobile_app/core/widgets/app_bar_widget.dart';
import 'package:nebras_mobile_app/core/widgets/content_section_breadcrumb_nav.dart';
import 'package:nebras_mobile_app/core/widgets/horizental_contentlist_widget.dart';
import 'package:nebras_mobile_app/core/widgets/related_content_list.dart';
import 'package:nebras_mobile_app/features/content/model/content_model.dart';
import 'package:nebras_mobile_app/features/download/provider/media_download_provider.dart';
import 'package:nebras_mobile_app/features/reader/provider/reader_provider.dart';
import 'package:nebras_mobile_app/features/reader/view/reader_screen.dart';
import 'package:nebras_mobile_app/features/reader/view/widgets/boook_header.dart';
import 'package:nebras_mobile_app/features/reader/view/widgets/descripetion_widget.dart';
import 'package:nebras_mobile_app/features/reader/view/widgets/download_section.dart';
import 'package:nebras_mobile_app/features/search/domain/usecase/get_section_content_usecase.dart';
import 'package:provider/provider.dart';

class BookDetailsScreen extends StatefulWidget {
  const BookDetailsScreen({super.key, required this.content});

  final Content content;

  @override
  State<BookDetailsScreen> createState() => _BookDetailsScreenState();
}

class _BookDetailsScreenState extends State<BookDetailsScreen> {
  List<Content> _relatedBooks = [];

  @override
  void initState() {
    super.initState();
    _loadRelatedBooks();
  }

  Future<void> _loadRelatedBooks() async {
    if (widget.content.section.isEmpty) return;
    try {
      final useCase = locator<GetSectionContentUseCase>();
      final sectionId = widget.content.subSection ?? widget.content.section;
      final allContent = await useCase(sectionId);
      final related = allContent
          .where((c) => c.type == ContentType.book && c.id != widget.content.id)
          .toList();
      if (mounted && related.isNotEmpty) {
        setState(() => _relatedBooks = related);
      }
    } catch (_) {
      // Silently fail — related content is optional
    }
  }

  void _handleRead(BuildContext context) {
    final downloadProvider = context.read<MediaDownloadProvider>();
    final localPath = downloadProvider.getLocalPath(widget.content.id);

    // Prefer local file if downloaded, otherwise stream from network
    final source = localPath ?? widget.content.sourceUrl;

    if (source != null && source.isNotEmpty) {
      final readerProvider = locator<ReaderProvider>();
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChangeNotifierProvider.value(
            value: readerProvider,
            child: ReaderScreen(
              source: source,
              bookId: widget.content.id,
              bookTitle: widget.content.title,
            ),
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No source available'.tr())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBarWidget(title: 'Book Details'.tr()),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 16.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with book cover + info
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.92, end: 1.0),
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOut,
                builder: (_, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: BoookHeaderWidget(content: widget.content),
              ),

              24.sbh,

              // Description
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.92, end: 1.0),
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                builder: (_, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: DescriptionSection(
                  description: widget.content.description,
                ),
              ),

              24.sbh,

              // Download / Read actions
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.92, end: 1.0),
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOut,
                builder: (_, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: DownloadSection(
                  onRead: () => _handleRead(context),
                  contentId: widget.content.id,
                  url: widget.content.sourceUrl ?? '',
                  title: widget.content.title,
                  imageUrl: widget.content.thumbnailUrl,
                ),
              ),

              16.sbh,
              ContentSectionBreadcrumbNav(content: widget.content),
              8.sbh,

              // "You May Also Read" — نفس القسم فقط (سريع وموثوق).
              if (_relatedBooks.isNotEmpty) ...[
                32.sbh,
                Text(
                  'You May Also Read'.tr(),
                  style: TextStyles.heading3(context),
                ),
                12.sbh,
                HorizontalContentList(
                  storageKey: 'related_books',
                  icon: Icons.menu_book_outlined,
                  title: 'You May Also Read'.tr(),
                  height: 190.h,
                  itemCount: _relatedBooks.length,
                  padding: EdgeInsets.zero,
                  items: _relatedBooks,
                ),
              ],
              // اقتراحات ذكيّة شاملة — من محرّك التوصيات + الأرشيف.
              24.sbh,
              RelatedContentList(reference: widget.content),
              24.sbh,
            ],
          ),
        ),
      ),
    );
  }
}
