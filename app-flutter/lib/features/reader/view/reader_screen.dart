import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:nebras_mobile_app/features/reader/provider/reader_provider.dart';

/// PDF Reader Screen
///
/// ARCHITECTURE RULES:
/// ✅ Receives source (local path OR network URL) as input
/// ✅ Does NOT check download state
/// ✅ Does NOT access repository
/// ✅ Does NOT decide source type
/// ✅ Only renders what it receives
///
/// Reading Modes:
/// ✅ Vertical   → continuous scroll, top to bottom
/// ✅ Horizontal → single page layout, swipe left OR right
/// ✅ Mode persisted in SharedPreferences via ReaderProvider
/// ✅ Toggle icon lives in the top controls bar
class ReaderScreen extends StatefulWidget {
  final String source;
  final String bookId;
  final String bookTitle;

  const ReaderScreen({
    super.key,
    required this.source,
    required this.bookId,
    required this.bookTitle,
  });

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  late PdfViewerController _pdfController;
  late ReaderProvider _provider;

  @override
  void initState() {
    super.initState();
    _pdfController = PdfViewerController();
    _provider = context.read<ReaderProvider>();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeReader();
    });
  }

  Future<void> _initializeReader() async {
    await _provider.initializeReader(widget.bookId);
    // initializeReader now calls _loadReadingMode() internally ✅

    // Restore last saved page position
    // +1 because Syncfusion uses 1-based page indexing internally
    if (_provider.currentPage > 0 && !_provider.isLoading) {
      _pdfController.jumpToPage(_provider.currentPage + 1);
    }
  }

  @override
  void dispose() {
    _pdfController.dispose();
    _provider.reset();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ReaderProvider>(
      builder: (context, provider, child) {
        return Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surface,
          body: SafeArea(
            child: Stack(
              children: [
                // ── PDF Viewer ──────────────────────────────────────
                GestureDetector(
                  onTap: provider.toggleControls,
                  child: _buildPdfViewer(provider),
                ),

                // ── Top overlay: back + title + mode toggle ─────────
                if (provider.isControlsVisible) _buildTopControls(provider),

                // ── Bottom overlay: page indicator ──────────────────
                if (provider.isControlsVisible) _buildBottomControls(provider),

                // ── Loading spinner ──────────────────────────────────
                if (provider.isLoading)
                  const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
        );
      },
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // PDF VIEWER
  //
  // WHY ValueKey?
  // SfPdfViewer treats scrollDirection and pageLayoutMode as constructor
  // configs — it ignores updates after the widget is first built.
  // By embedding readingMode in the key, Flutter sees a "new" widget
  // when mode changes and fully remounts it with the correct config.
  //
  // WHY extract callbacks?
  // onPageChanged and onDocumentLoaded are identical for both network
  // and file sources — extracting them removes duplication and makes
  // future changes a one-line edit.
  // ───────────────────────────────────────────────────────────────────────
  Widget _buildPdfViewer(ReaderProvider provider) {
    final isNetwork = widget.source.startsWith('http');

    // Vertical  → continuous scroll (uninterrupted reading flow)
    // Horizontal → single page (one page at a time, swipe either direction)
    final scrollDirection = provider.readingMode == ReadingMode.horizontal
        ? PdfScrollDirection.horizontal
        : PdfScrollDirection.vertical;

    final pageLayoutMode = provider.readingMode == ReadingMode.horizontal
        ? PdfPageLayoutMode.single
        : PdfPageLayoutMode.continuous;

    // Key embeds both source and mode — changes to either force a rebuild
    final viewerKey = ValueKey('${widget.source}_${provider.readingMode.name}');

    // Callbacks extracted once — shared by both network and file viewers
    void onPageChanged(PdfPageChangedDetails details) {
      provider.onPageChanged(
        bookId: widget.bookId,
        newPage: details.newPageNumber - 1, // Syncfusion 1-based → our 0-based
        totalPages: _pdfController.pageCount,
      );
    }

    void onDocumentLoaded(PdfDocumentLoadedDetails details) {
      provider.setTotalPages(details.document.pages.count);
    }

    if (isNetwork) {
      return SfPdfViewer.network(
        key: viewerKey,
        widget.source,
        controller: _pdfController,
        scrollDirection: scrollDirection,
        pageLayoutMode: pageLayoutMode,
        onPageChanged: onPageChanged,
        onDocumentLoaded: onDocumentLoaded,
      );
    }

    return SfPdfViewer.file(
      key: viewerKey,
      File(widget.source),
      controller: _pdfController,
      scrollDirection: scrollDirection,
      pageLayoutMode: pageLayoutMode,
      onPageChanged: onPageChanged,
      onDocumentLoaded: onDocumentLoaded,
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // TOP CONTROLS
  //
  // Layout: [← Back]  [Title ............]  [mode toggle icon]
  //
  // Icon logic:
  //   Currently vertical   → show swap_horiz icon (tap to go horizontal)
  //   Currently horizontal → show swap_vert icon  (tap to go vertical)
  //
  // Page restore after toggle:
  //   We capture currentPage BEFORE the toggle (provider state changes
  //   on toggle), then restore it AFTER the new viewer mounts via
  //   addPostFrameCallback. Without the delay, jumpToPage fires on the
  //   old (disposing) controller and does nothing.
  // ───────────────────────────────────────────────────────────────────────
  Widget _buildTopControls(ReaderProvider provider) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
          ),
        ),
        child: Row(
          children: [
            // Back button
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),

            SizedBox(width: 8.w),

            // Title — fills remaining space, clips with ellipsis
            Expanded(
              child: Text(
                widget.bookTitle,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // ── Reading mode toggle ────────────────────────────────
            Tooltip(
              message: provider.readingMode == ReadingMode.vertical
                  ? 'Switch to horizontal'.tr()
                  : 'Switch to vertical'.tr(),
              child: IconButton(
                icon: AnimatedSwitcher(
                  // Smooth icon crossfade when mode changes
                  duration: const Duration(milliseconds: 250),
                  child: Icon(
                    provider.readingMode == ReadingMode.vertical
                        ? Icons.swap_horiz
                        : Icons.swap_vert,
                    color: Colors.white,
                    // Key makes AnimatedSwitcher detect the icon change
                    key: ValueKey(provider.readingMode),
                  ),
                ),
                onPressed: () async {
                  // 1. Capture page BEFORE toggle — provider state
                  //    changes immediately inside toggleReadingMode()
                  final pageBeforeSwitch = provider.currentPage;

                  // 2. Toggle mode + persist to SharedPreferences
                  await provider.toggleReadingMode();

                  // 3. Restore page position after new viewer mounts
                  //    addPostFrameCallback = "run after next frame render"
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (pageBeforeSwitch > 0) {
                      _pdfController.jumpToPage(pageBeforeSwitch + 1);
                    }
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // BOTTOM CONTROLS — page progress pill
  // ───────────────────────────────────────────────────────────────────────
  Widget _buildBottomControls(ReaderProvider provider) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(20.r),
              ),
              child: Text(
                provider.totalPages > 0
                    ? 'Page {} of {}'.tr(
                        args: [
                          '${provider.currentPage + 1}',
                          '${provider.totalPages}',
                        ],
                      )
                    : 'Loading...'.tr(),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
