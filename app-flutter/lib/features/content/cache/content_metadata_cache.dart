import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:nebras_mobile_app/core/data/content_ordering.dart';
import 'package:nebras_mobile_app/features/content/model/content_model.dart';

part 'content_metadata_cache.g.dart';

/// نسخة Hive خفيفة من ميتادات المحتوى فقط. لا نخزن ملفات التشغيل هنا؛
/// الهدف أن تبقى العناوين والأوصاف والصور المصغّرة متاحة عند انقطاع الشبكة.
@HiveType(typeId: 3)
class ContentMetadataCacheEntry {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String title;
  @HiveField(2)
  final String author;
  @HiveField(3)
  final String description;
  @HiveField(4)
  final String type;
  @HiveField(5)
  final String thumbnailUrl;
  @HiveField(6)
  final String? sourceUrl;
  @HiveField(7)
  final int? sizeInBytes;
  @HiveField(8)
  final String section;
  @HiveField(9)
  final String? subSection;
  @HiveField(10)
  final String? sectionName;
  @HiveField(11)
  final int createdAtMs;
  @HiveField(12)
  final int updatedAtMs;
  @HiveField(13)
  final String createdBy;
  @HiveField(14)
  final int cachedAtMs;

  const ContentMetadataCacheEntry({
    required this.id,
    required this.title,
    required this.author,
    required this.description,
    required this.type,
    required this.thumbnailUrl,
    required this.section,
    required this.createdAtMs,
    required this.updatedAtMs,
    required this.createdBy,
    required this.cachedAtMs,
    this.sourceUrl,
    this.sizeInBytes,
    this.subSection,
    this.sectionName,
  });

  factory ContentMetadataCacheEntry.fromContent(Content content) {
    return ContentMetadataCacheEntry(
      id: content.id,
      title: content.title,
      author: content.author,
      description: content.description,
      type: content.type.name,
      thumbnailUrl: content.thumbnailUrl,
      sourceUrl: content.sourceUrl,
      sizeInBytes: content.sizeInBytes,
      section: content.section,
      subSection: content.subSection,
      sectionName: content.sectionName,
      createdAtMs: content.createdAt.millisecondsSinceEpoch,
      updatedAtMs: content.updatedAt.millisecondsSinceEpoch,
      createdBy: content.createdBy,
      cachedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Content toContent() {
    return Content(
      id: id,
      title: title,
      author: author,
      description: description,
      type: parseContentType(type),
      thumbnailUrl: thumbnailUrl,
      sourceUrl: sourceUrl,
      sizeInBytes: sizeInBytes,
      section: section,
      subSection: subSection,
      sectionName: sectionName,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMs),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAtMs),
      createdBy: createdBy,
    );
  }
}

class ContentMetadataCache extends ChangeNotifier {
  ContentMetadataCache(this._box);

  final Box<ContentMetadataCacheEntry> _box;
  final Set<String> _offlinePreviewIds = <String>{};

  List<Content> getAll() {
    final items = _box.values.map((entry) => entry.toContent()).toList();
    sortContentOldestFirst(items);
    return items;
  }

  Content? getById(String id) => _box.get(id)?.toContent();

  bool isOfflinePreview(String id) => _offlinePreviewIds.contains(id);

  Future<void> upsertAll(Iterable<Content> contents) async {
    final rows = <String, ContentMetadataCacheEntry>{};
    for (final content in contents) {
      final id = content.id.trim();
      if (id.isEmpty) continue;
      rows[id] = ContentMetadataCacheEntry.fromContent(content);
    }
    if (rows.isEmpty) return;
    await _box.putAll(rows);
    notifyListeners();
  }

  /// نخزن لقطة حيّة ونزيل عنها وسم "معاينة أوفلاين". لا نحذف كل الكاش هنا
  /// لأن الصفحة قد تكون محدودة pagination؛ واجهة المستخدم الحية نفسها هي
  /// التي تنظف المحذوفات فور عودة الاتصال.
  Future<void> cacheLiveItems(Iterable<Content> contents) async {
    final ids = contents
        .map((content) => content.id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    await upsertAll(contents);
    _offlinePreviewIds.removeAll(ids);
    notifyListeners();
  }

  Future<void> reconcileWithLiveIds(Iterable<String> liveIds) async {
    final keep = liveIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    final staleKeys = _box.keys
        .whereType<String>()
        .where((id) => !keep.contains(id))
        .toList(growable: false);
    if (staleKeys.isNotEmpty) {
      await _box.deleteAll(staleKeys);
      notifyListeners();
    }
  }

  bool hasMetadata(String id) => _box.containsKey(id);

  bool has(String id) => hasMetadata(id);

  Future<void> cacheMany(Iterable<Content> contents) => upsertAll(contents);

  /// عند فشل الشبكة نعرض الميتادات المحفوظة فقط، ونوسمها كي تُعطّل أزرار
  /// تشغيل الوسائط غير المحمّلة مع بقاء النص والصورة المصغرة قابلين للتصفح.
  List<Content> offlineContents() {
    final contents = getAll();
    _offlinePreviewIds
      ..clear()
      ..addAll(contents.map((content) => content.id));
    return contents;
  }

  static bool isOfflinePreviewId(String id) {
    return id.startsWith('offline_preview:');
  }

  Content markOfflinePreview(Content content) {
    final id = content.id.trim();
    _offlinePreviewIds.add(id);
    return Content(
      id: isOfflinePreviewId(id) ? id : 'offline_preview:$id',
      title: content.title,
      author: content.author,
      description: content.description,
      type: content.type,
      thumbnailUrl: content.thumbnailUrl,
      sourceUrl: content.sourceUrl,
      sizeInBytes: content.sizeInBytes,
      section: content.section,
      subSection: content.subSection,
      sectionName: content.sectionName,
      createdAt: content.createdAt,
      updatedAt: content.updatedAt,
      createdBy: content.createdBy,
    );
  }

  List<HomeSectionCacheGroup> offlineGroups() {
    final grouped = <String, List<Content>>{};
    for (final content in offlineContents()) {
      final key = content.section.trim().isNotEmpty
          ? content.section.trim()
          : 'offline_metadata';
      grouped.putIfAbsent(key, () => <Content>[]).add(content);
    }
    return grouped.entries
        .map((entry) {
          final first = entry.value.first;
          final title = (first.sectionName ?? '').trim().isNotEmpty
              ? first.sectionName!.trim()
              : entry.key;
          return HomeSectionCacheGroup(
            id: 'offline:${entry.key}',
            title: title,
            items: entry.value,
          );
        })
        .toList(growable: false);
  }

  static List<HomeSectionCacheGroup> offlineSectionsFromEntries(
    Iterable<ContentMetadataCacheEntry> entries,
  ) {
    final grouped = <String, List<Content>>{};
    for (final entry in entries) {
      final content = entry.toContent();
      final key = content.section.trim().isNotEmpty
          ? content.section.trim()
          : 'offline_metadata';
      grouped.putIfAbsent(key, () => <Content>[]).add(content);
    }
    return grouped.entries
        .map((entry) {
          final first = entry.value.first;
          final title = (first.sectionName ?? '').trim().isNotEmpty
              ? first.sectionName!.trim()
              : entry.key;
          return HomeSectionCacheGroup(
            id: 'offline:${entry.key}',
            title: title,
            items: entry.value,
          );
        })
        .toList(growable: false);
  }
}

extension OfflineContentPreview on Content {
  Content asOfflinePreview() {
    final previewId = ContentMetadataCache.isOfflinePreviewId(id)
        ? id
        : 'offline_preview:$id';
    return Content(
      id: previewId,
      title: title,
      author: author,
      description: description,
      type: type,
      thumbnailUrl: thumbnailUrl,
      sourceUrl: sourceUrl,
      sizeInBytes: sizeInBytes,
      section: section,
      subSection: subSection,
      sectionName: sectionName,
      createdAt: createdAt,
      updatedAt: updatedAt,
      createdBy: createdBy,
    );
  }
}

class OfflineContentPolicy {
  const OfflineContentPolicy._();

  static bool canOpen(Content content, {required bool hasLocalFile}) {
    if (!ContentMetadataCache.isOfflinePreviewId(content.id)) return true;
    if (content.type != ContentType.video &&
        content.type != ContentType.youtube &&
        content.type != ContentType.audio) {
      return true;
    }
    return hasLocalFile;
  }
}

class HomeSectionCacheGroup {
  final String id;
  final String title;
  final List<Content> items;

  const HomeSectionCacheGroup({
    required this.id,
    required this.title,
    required this.items,
  });
}
