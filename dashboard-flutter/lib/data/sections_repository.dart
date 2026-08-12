import 'dart:math';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

import '../core/search_util.dart';
import 'storage_upload.dart';
import 'unified_firestore.dart';

/// مستوى القسم.
enum SectionLevel { main, sub, secondary }

String levelKey(SectionLevel l) => switch (l) {
      SectionLevel.main => 'main',
      SectionLevel.sub => 'sub',
      SectionLevel.secondary => 'secondary',
    };

bool sameSectionId(dynamic a, dynamic b) {
  if (a == null || b == null) return false;
  return a.toString() == b.toString();
}

int _makeSectionId() =>
    DateTime.now().millisecondsSinceEpoch + Random().nextInt(1000);

/// إدارة الأقسام (Nebras فقط) — نظير قسم الأقسام في `moderator.js`.
class SectionsRepository {
  SectionsRepository._();
  static final SectionsRepository instance = SectionsRepository._();

  final _fs = UnifiedFirestore.instance;

  // ─── قراءة ───────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> listMain({String search = ''}) async {
    final all = await _fs.readSectionsLevel('main');
    return _applyFilters(all, search: search);
  }

  Future<List<Map<String, dynamic>>> listSub({
    dynamic mainSection,
    String search = '',
  }) async {
    final all = await _fs.readSectionsLevel('sub');
    return _applyFilters(all, search: search, mainSection: mainSection);
  }

  Future<List<Map<String, dynamic>>> listSecondary({
    dynamic subSection,
    String search = '',
  }) async {
    final all = await _fs.readSectionsLevel('secondary');
    return _applyFilters(all, search: search, subSection: subSection);
  }

  List<Map<String, dynamic>> _applyFilters(
    List<Map<String, dynamic>> list, {
    String search = '',
    dynamic mainSection,
    dynamic subSection,
  }) {
    var out = List<Map<String, dynamic>>.from(list);
    final tokens = tokenize(search);
    if (tokens.isNotEmpty) {
      out = filterAndRank(out, tokens, (x) => [
            '${x['name'] ?? ''}',
            '${x['description'] ?? ''}',
            '${x['id'] ?? ''}',
          ]);
    }
    if (mainSection != null && '$mainSection'.isNotEmpty) {
      out = out.where((x) => sameSectionId(x['main_section'], mainSection)).toList();
    }
    if (subSection != null && '$subSection'.isNotEmpty) {
      out = out.where((x) => sameSectionId(x['sub_section'], subSection)).toList();
    }
    if (tokens.isEmpty) {
      out.sort((a, b) {
        final ao = (a['order_index'] as num?)?.toInt() ?? 0;
        final bo = (b['order_index'] as num?)?.toInt() ?? 0;
        if (ao != bo) return ao.compareTo(bo);
        final an = int.tryParse('${a['id']}');
        final bn = int.tryParse('${b['id']}');
        if (an != null && bn != null) return bn.compareTo(an);
        return '${b['id']}'.compareTo('${a['id']}');
      });
    }
    return out;
  }

  // ─── إنشاء/تعديل ─────────────────────────────────────────

  Future<String?> _uploadThumb(
    String level,
    dynamic id,
    Uint8List? bytes,
    String? filename,
  ) async {
    if (bytes == null) return null;
    final res = await smartUpload(
      bytes: bytes,
      filename: '${DateTime.now().millisecondsSinceEpoch}_${filename ?? 'thumb'}',
      folder: 'sections/$level/$id',
      contentType: 'image/jpeg',
    );
    return res.url;
  }

  Future<Map<String, dynamic>> createMain({
    required String name,
    int orderIndex = 0,
    bool isListed = true,
    Uint8List? thumbBytes,
    String? thumbName,
  }) async {
    final id = _makeSectionId();
    final thumbUrl = await _uploadThumb('main', id, thumbBytes, thumbName);
    final payload = {
      'id': id,
      'name': name.trim(),
      'order_index': orderIndex,
      'is_listed': isListed,
      'thumbnail': thumbUrl,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
    await _fs.setSectionRecord('main', id, payload);
    return payload;
  }

  Future<Map<String, dynamic>> createSub({
    required String name,
    required dynamic mainSection,
    bool isListed = true,
    Uint8List? thumbBytes,
    String? thumbName,
  }) async {
    final id = _makeSectionId();
    final thumbUrl = await _uploadThumb('sub', id, thumbBytes, thumbName);
    final payload = {
      'id': id,
      'name': name.trim(),
      'main_section': int.tryParse('$mainSection') ?? mainSection,
      'is_listed': isListed,
      'thumbnail': thumbUrl,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
    await _fs.setSectionRecord('sub', id, payload);
    return payload;
  }

  Future<Map<String, dynamic>> createSecondary({
    required String name,
    required dynamic subSection,
    bool isListed = true,
    Uint8List? thumbBytes,
    String? thumbName,
  }) async {
    final id = _makeSectionId();
    final thumbUrl = await _uploadThumb('secondary', id, thumbBytes, thumbName);
    final payload = {
      'id': id,
      'name': name.trim(),
      'sub_section': int.tryParse('$subSection') ?? subSection,
      'is_listed': isListed,
      'thumbnail': thumbUrl,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
    await _fs.setSectionRecord('secondary', id, payload);
    return payload;
  }

  /// تعديل قسم. الحقول الممرَّرة فقط تُحدَّث (null = لا تغيّر).
  Future<Map<String, dynamic>> update(
    SectionLevel level,
    dynamic id, {
    String? name,
    String? description,
    int? orderIndex,
    bool? isListed,
    dynamic parentSection, // main_section (sub) أو sub_section (secondary)
    Uint8List? thumbBytes,
    String? thumbName,
  }) async {
    final lk = levelKey(level);
    final current = await _fs.getSectionRecord(lk, id);
    if (current == null) throw Exception('Section not found');
    final patch = <String, dynamic>{};
    if (name != null) patch['name'] = name.trim();
    if (description != null) patch['description'] = description.trim();
    if (orderIndex != null) patch['order_index'] = orderIndex;
    if (isListed != null) patch['is_listed'] = isListed;
    if (parentSection != null) {
      if (level == SectionLevel.sub) patch['main_section'] = parentSection;
      if (level == SectionLevel.secondary) patch['sub_section'] = parentSection;
    }
    if (thumbBytes != null) {
      patch['thumbnail'] = await _uploadThumb(lk, id, thumbBytes, thumbName);
    }
    final next = {...current, ...patch};
    await _fs.setSectionRecord(lk, id, next);
    return next;
  }

  // ─── حذف تعاقبي (يطابق removeMain/Sub/Secondary) ──────────

  Future<void> removeMain(dynamic id) async {
    final mainRow = await _fs.getSectionRecord('main', id);
    final subItems = await _fs.readSectionsLevel('sub');
    final secItems = await _fs.readSectionsLevel('secondary');
    final fileRows = await _fs.listFileRowsMerged();
    final videos = await _fs.listYoutubeRecords();

    final subRows = subItems.where((s) => sameSectionId(s['main_section'], id)).toList();
    final subIds = subRows.map((s) => s['id']).toList();
    final secondaryRows = secItems
        .where((sec) => subIds.any((subId) => sameSectionId(sec['sub_section'], subId)))
        .toList();
    final secondaryIds = secondaryRows.map((sec) => sec['id']).toList();

    bool belongs(Map<String, dynamic> row) {
      final md = (row['metadata'] as Map?) ?? {};
      final mainMatch = sameSectionId(md['main_section'], id) ||
          sameSectionId(md['main_section_id'], id) ||
          sameSectionId(row['main_section'], id) ||
          sameSectionId(row['main_section_id'], id);
      final subMatch = subIds.any((subId) =>
          sameSectionId(md['subsection'], subId) || sameSectionId(row['subsection'], subId));
      final secMatch = secondaryIds.any((secId) =>
          sameSectionId(md['secondary_subsection'], secId) ||
          sameSectionId(row['secondary_subsection'], secId));
      return mainMatch || subMatch || secMatch;
    }

    final filesToDelete = fileRows.where(belongs).toList();
    final videosToDelete = videos.where(belongs).toList();
    await _deleteAssets([
      ..._collectAssetUrls(mainRow ?? {}),
      ...subRows.expand(_collectAssetUrls),
      ...secondaryRows.expand(_collectAssetUrls),
      ...filesToDelete.expand(_collectAssetUrls),
      ...videosToDelete.expand(_collectAssetUrls),
    ]);
    for (final row in filesToDelete) {
      await _fs.deleteFileMirrorBoth(row['fileId'] ?? row['id']);
    }
    for (final row in videosToDelete) {
      await _fs.deleteYoutubeRecord(row['id']);
    }
    for (final sec in secondaryRows) {
      await _fs.deleteSectionRecord('secondary', sec['id']);
    }
    for (final sub in subRows) {
      await _fs.deleteSectionRecord('sub', sub['id']);
    }
    await _fs.deleteSectionRecord('main', id);
  }

  Future<void> removeSub(dynamic id) async {
    final subRow = await _fs.getSectionRecord('sub', id);
    final secItems = await _fs.readSectionsLevel('secondary');
    final secondaryRows = secItems.where((sec) => sameSectionId(sec['sub_section'], id)).toList();
    final secondaryIds = secondaryRows.map((sec) => sec['id']).toList();
    final fileRows = await _fs.listFileRowsMerged();
    final videos = await _fs.listYoutubeRecords();

    bool belongs(Map<String, dynamic> row) {
      final md = (row['metadata'] as Map?) ?? {};
      final subMatch =
          sameSectionId(md['subsection'], id) || sameSectionId(row['subsection'], id);
      final secMatch = secondaryIds.any((secId) =>
          sameSectionId(md['secondary_subsection'], secId) ||
          sameSectionId(row['secondary_subsection'], secId));
      return subMatch || secMatch;
    }

    final filesToDelete = fileRows.where(belongs).toList();
    final videosToDelete = videos.where(belongs).toList();
    await _deleteAssets([
      ..._collectAssetUrls(subRow ?? {}),
      ...secondaryRows.expand(_collectAssetUrls),
      ...filesToDelete.expand(_collectAssetUrls),
      ...videosToDelete.expand(_collectAssetUrls),
    ]);
    for (final row in filesToDelete) {
      await _fs.deleteFileMirrorBoth(row['fileId'] ?? row['id']);
    }
    for (final row in videosToDelete) {
      await _fs.deleteYoutubeRecord(row['id']);
    }
    for (final sec in secondaryRows) {
      await _fs.deleteSectionRecord('secondary', sec['id']);
    }
    await _fs.deleteSectionRecord('sub', id);
  }

  Future<void> removeSecondary(dynamic id) async {
    final secRow = await _fs.getSectionRecord('secondary', id);
    final fileRows = await _fs.listFileRowsMerged();
    final videos = await _fs.listYoutubeRecords();

    bool belongs(Map<String, dynamic> row) {
      final md = (row['metadata'] as Map?) ?? {};
      return sameSectionId(md['secondary_subsection'], id) ||
          sameSectionId(row['secondary_subsection'], id);
    }

    final filesToDelete = fileRows.where(belongs).toList();
    final videosToDelete = videos.where(belongs).toList();
    await _deleteAssets([
      ..._collectAssetUrls(secRow ?? {}),
      ...filesToDelete.expand(_collectAssetUrls),
      ...videosToDelete.expand(_collectAssetUrls),
    ]);
    for (final row in filesToDelete) {
      await _fs.deleteFileMirrorBoth(row['fileId'] ?? row['id']);
    }
    for (final row in videosToDelete) {
      await _fs.deleteYoutubeRecord(row['id']);
    }
    await _fs.deleteSectionRecord('secondary', id);
  }

  Future<void> remove(SectionLevel level, dynamic id) => switch (level) {
        SectionLevel.main => removeMain(id),
        SectionLevel.sub => removeSub(id),
        SectionLevel.secondary => removeSecondary(id),
      };

  List<String> _collectAssetUrls(Map<String, dynamic> row) {
    final md = (row['metadata'] as Map?) ?? {};
    final raw = <dynamic>[
      row['thumbnail'],
      row['image'],
      row['imageUrl'],
      row['thumbnailUrl'],
      md['thumbnail'],
      row['file_url'],
      row['audio_url'],
      row['video_url'],
      row['downloadUrl'],
      row['sourceUrl'],
      row['url'],
    ];
    final seen = <String>{};
    for (final v in raw) {
      final s = '${v ?? ''}'.trim();
      if (s.isNotEmpty) seen.add(s);
    }
    return seen.toList();
  }

  Future<void> _deleteAssets(List<String> urls) async {
    final storage = FirebaseStorage.instance;
    for (final url in urls.toSet()) {
      try {
        await storage.refFromURL(url).delete();
      } catch (_) {
        // لا نوقف الحذف الجذري بسبب ملف مفقود.
      }
    }
  }
}
