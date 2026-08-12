import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:nebras_mobile_app/core/widgets/horizental_contentlist_widget.dart';
import 'package:nebras_mobile_app/features/content/cache/content_metadata_cache.dart';
import 'package:nebras_mobile_app/features/content/model/content_model.dart';
import 'package:nebras_mobile_app/features/download/provider/media_download_provider.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('cached offline media shows snackbar and does not open', (
    tester,
  ) async {
    final content = _content('offline').asOfflinePreview();
    var opened = false;

    await tester.pumpWidget(
      _TestHarness(content: content, onOpen: () => opened = true),
    );

    await tester.tap(find.text('Video offline'));
    await tester.pump();

    expect(opened, isFalse);
    expect(find.text('هذا المحتوى غير متوفر بدون إنترنت'), findsOneWidget);
  });

  testWidgets('live media still opens even if not downloaded locally', (
    tester,
  ) async {
    final content = _content('live');
    var opened = false;

    await tester.pumpWidget(
      _TestHarness(content: content, onOpen: () => opened = true),
    );

    await tester.tap(find.text('Video live'));
    await tester.pump();

    expect(opened, isTrue);
    expect(find.text('هذا المحتوى غير متوفر بدون إنترنت'), findsNothing);
  });
}

class _TestHarness extends StatelessWidget {
  const _TestHarness({required this.content, required this.onOpen});

  final Content content;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ContentMetadataCache>.value(
          value: _FakeMetadataCache(),
        ),
        ChangeNotifierProvider<MediaDownloadProvider>.value(
          value: _FakeMediaDownloadProvider(),
        ),
      ],
      child: ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (context, child) => MaterialApp(
          home: Scaffold(
            body: HorizontalContentList(
              storageKey: 'test',
              icon: Icons.play_circle_outline,
              title: 'test',
              height: 260,
              itemCount: 1,
              padding: EdgeInsets.zero,
              items: [content],
              onItemTap: (_) => onOpen(),
            ),
          ),
        ),
      ),
    );
  }
}

Content _content(String id) {
  return Content(
    id: id,
    title: 'Video $id',
    author: '',
    description: '',
    type: ContentType.video,
    thumbnailUrl: '',
    section: 'section',
    sourceUrl: 'https://example.com/$id.mp4',
    createdAt: DateTime(2024),
    updatedAt: DateTime(2024),
    createdBy: '',
  );
}

class _FakeMetadataCache extends ContentMetadataCache {
  _FakeMetadataCache() : super(_UnreachableBox());

  @override
  bool has(String id) => true;
}

class _FakeMediaDownloadProvider extends ChangeNotifier
    implements MediaDownloadProvider {
  @override
  String? getLocalPath(String contentId) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnreachableBox extends Box<ContentMetadataCacheEntry> {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
