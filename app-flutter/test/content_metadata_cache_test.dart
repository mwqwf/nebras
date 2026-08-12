import 'package:flutter_test/flutter_test.dart';
import 'package:nebras_mobile_app/features/content/cache/content_metadata_cache.dart';
import 'package:nebras_mobile_app/features/content/model/content_model.dart';

void main() {
  test('metadata cache entry round-trips content metadata', () {
    final content = Content(
      id: 'video-1',
      title: 'عنوان',
      author: 'author',
      description: 'description',
      type: ContentType.video,
      thumbnailUrl: 'https://example.com/thumb.jpg',
      section: 'section',
      subSection: 'sub',
      sectionName: 'Section name',
      sourceUrl: 'https://example.com/video.mp4',
      sizeInBytes: 42,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
      createdBy: 'admin',
    );

    final restored = ContentMetadataCacheEntry.fromContent(content).toContent();

    expect(restored.id, content.id);
    expect(restored.title, content.title);
    expect(restored.description, content.description);
    expect(restored.type, content.type);
    expect(restored.sourceUrl, content.sourceUrl);
    expect(restored.createdAt, content.createdAt);
    expect(restored.updatedAt, content.updatedAt);
  });

  test('offline snapshot groups cached items without source URLs', () {
    final first = _content('video-1', section: 'section-a');
    final second = _content(
      'book-1',
      section: 'section-a',
      type: ContentType.book,
    );

    final sections = ContentMetadataCache.offlineSectionsFromEntries([
      ContentMetadataCacheEntry.fromContent(first),
      ContentMetadataCacheEntry.fromContent(second),
    ]);

    expect(sections.single.id, 'offline:section-a');
    expect(sections.single.items.map((item) => item.id), ['video-1', 'book-1']);
    expect(sections.single.items.first.sourceUrl, first.sourceUrl);
  });

  test('media availability policy blocks only offline preview media', () {
    final liveVideo = _content('live');
    final offlineVideo = _content('offline').asOfflinePreview();
    final offlineBook = _content(
      'book',
      type: ContentType.book,
    ).asOfflinePreview();

    expect(
      OfflineContentPolicy.canOpen(liveVideo, hasLocalFile: false),
      isTrue,
    );
    expect(
      OfflineContentPolicy.canOpen(offlineVideo, hasLocalFile: false),
      isFalse,
    );
    expect(
      OfflineContentPolicy.canOpen(offlineVideo, hasLocalFile: true),
      isTrue,
    );
    expect(
      OfflineContentPolicy.canOpen(offlineBook, hasLocalFile: false),
      isTrue,
    );
  });
}

Content _content(
  String id, {
  String section = 'section',
  ContentType type = ContentType.video,
}) {
  return Content(
    id: id,
    title: id,
    author: 'author',
    description: 'description',
    type: type,
    thumbnailUrl: 'https://example.com/$id.jpg',
    section: section,
    sourceUrl: type == ContentType.book
        ? 'https://example.com/$id.pdf'
        : 'https://example.com/$id.mp4',
    createdAt: DateTime.fromMillisecondsSinceEpoch(id.hashCode.abs()),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(id.hashCode.abs() + 1),
    createdBy: 'admin',
  );
}
