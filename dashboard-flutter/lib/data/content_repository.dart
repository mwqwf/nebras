import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../core/api_client.dart';
import '../core/search_util.dart';
import 'sections_repository.dart' show sameSectionId;
import 'storage_upload.dart';
import 'unified_firestore.dart';
import 'upload_schema.dart';

String contentTypeFromMime(String? mime) {
  if (mime == null || mime.isEmpty) return 'document';
  if (mime.startsWith('video/')) return 'video';
  if (mime.startsWith('audio/')) return 'audio';
  return 'document';
}

/// صفّ محتوى موحَّد بالشكل الذي تعرضه الواجهة (نظير ناتج `listMyFiles`).
class ContentRow {
  ContentRow(this.raw);
  final Map<String, dynamic> raw;

  String get id => '${raw['id']}';
  String get filename => '${raw['filename'] ?? 'untitled'}';
  String get fileUrl => '${raw['file_url'] ?? ''}';
  String get fileType => '${raw['file_type'] ?? ''}';
  String get uploadType => '${raw['upload_type'] ?? 'firebase'}';
  String get uploadStatus => '${raw['upload_status'] ?? 'completed'}';
  int get fileSize => (raw['file_size'] as num?)?.toInt() ?? 0;
  int get viewCount => (raw['view_count'] as num?)?.toInt() ?? 0;
  int get playCount => (raw['play_count'] as num?)?.toInt() ?? 0;
  int get completeCount => (raw['complete_count'] as num?)?.toInt() ?? 0;
  bool get hasEngagement => viewCount > 0 || playCount > 0 || completeCount > 0;
  dynamic get createdAt => metadata['created_at'];
  Map<String, dynamic> get metadata =>
      (raw['metadata'] as Map?)?.cast<String, dynamic>() ?? const {};
  String get title => '${metadata['title'] ?? filename}';
  String get author => '${metadata['author'] ?? ''}';
  String get description => '${metadata['description'] ?? ''}';
  String get contentType => '${metadata['content_type'] ?? 'document'}';
  String? get thumbnail {
    final t = metadata['thumbnail'] ?? raw['thumbnail'];
    final s = '${t ?? ''}'.trim();
    return s.isEmpty ? null : s;
  }

  bool get isListed => (metadata['is_listed'] ?? true) == true;
}

class ContentRepository {
  ContentRepository._();
  static final ContentRepository instance = ContentRepository._();

  final _fs = UnifiedFirestore.instance;

  // ─── قائمة المحتوى ──────────────────────────────────────

  Future<List<ContentRow>> listFiles({
    String search = '',
    dynamic mainSection,
    dynamic subsection,
    dynamic secondarySubsection,
    String? contentType,
    bool? isListed,
  }) async {
    final rows = await _fs.listFileRowsMerged();
    final subMap = await _fs.readSectionsSubMap();

    var list = rows.map((item) {
      final md = (item['metadata'] as Map?)?.cast<String, dynamic>() ?? {};
      final createdAt = md['created_at'] ?? item['createdAt'];
      int eng(String a, String b) {
        final v = item[a] ?? item[b] ?? md[a] ?? md[b];
        final n = (v is num) ? v.toInt() : int.tryParse('$v') ?? 0;
        return n > 0 ? n : 0;
      }

      return {
        'id': item['fileId'] ?? item['id'],
        'filename': item['filename'] ?? 'untitled',
        'file_type': item['fileType'] ?? item['file_type'] ?? '',
        'file_size': (item['fileSize'] ?? item['file_size'] ?? 0),
        'file_url': item['downloadUrl'] ?? item['file_url'] ?? '',
        'upload_type': item['upload_type'] ?? 'firebase',
        'upload_status': item['upload_status'] ?? item['uploadStatus'] ?? 'completed',
        'thumbnail': item['thumbnail'] ?? md['thumbnail'],
        'view_count': eng('view_count', 'viewCount'),
        'play_count': eng('play_count', 'playCount'),
        'complete_count': eng('complete_count', 'completeCount'),
        'metadata': {
          ...md,
          'created_at': createdAt,
        },
      };
    }).toList();

    final tokens = tokenize(search);
    if (tokens.isNotEmpty) {
      list = filterAndRank(list, tokens, (item) {
        final md = (item['metadata'] as Map);
        return [
          '${md['title'] ?? ''}',
          '${md['description'] ?? ''}',
          '${md['author'] ?? ''}',
          '${item['filename'] ?? ''}',
          '${item['file_url'] ?? ''}',
        ];
      });
    }

    if (subsection != null && '$subsection'.isNotEmpty) {
      list = list.where((i) => sameSectionId((i['metadata'] as Map)['subsection'], subsection)).toList();
    }
    if (secondarySubsection != null && '$secondarySubsection'.isNotEmpty) {
      list = list
          .where((i) => sameSectionId((i['metadata'] as Map)['secondary_subsection'], secondarySubsection))
          .toList();
    }
    if (mainSection != null && '$mainSection'.isNotEmpty) {
      list = list.where((i) {
        final subId = (i['metadata'] as Map)['subsection'];
        final sub = subMap['$subId'];
        return sub is Map && sameSectionId(sub['main_section'], mainSection);
      }).toList();
    }
    if (contentType != null && contentType.isNotEmpty) {
      list = list
          .where((i) => '${(i['metadata'] as Map)['content_type'] ?? ''}' == contentType)
          .toList();
    }
    if (isListed != null) {
      list = list
          .where((i) => ((i['metadata'] as Map)['is_listed'] ?? true) == isListed)
          .toList();
    }

    int ts(Map item) {
      final v = (item['metadata'] as Map)['created_at'];
      if (v is Timestamp) return v.millisecondsSinceEpoch;
      if (v is String) return DateTime.tryParse(v)?.millisecondsSinceEpoch ?? 0;
      if (v is num) return v.toInt();
      return 0;
    }

    list.sort((a, b) => ts(b).compareTo(ts(a)));
    return list.map(ContentRow.new).toList();
  }

  // ─── إنشاء محتوى جديد (رفع) ─────────────────────────────

  /// يرفع الملفّ إلى Storage ثم يكتب الوثيقة في المجموعتين (مرآة).
  /// [metadata] يجب أن يحوي: title, content_type, main_section/subsection… إلخ.
  Future<String> createContent({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
    required Map<String, dynamic> metadata,
    Uint8List? thumbBytes,
    String? thumbName,
    void Function(double pct)? onProgress,
    bool Function()? isAborted,
  }) async {
    final prepared = await prepareUpload(
      bytes: bytes,
      filename: filename,
      mimeType: mimeType,
      metadata: metadata,
      thumbBytes: thumbBytes,
      thumbName: thumbName,
      onProgress: onProgress,
      isAborted: isAborted,
    );
    await commitPrepared(prepared);
    return '${prepared['fileId']}';
  }

  /// المرحلة 1 من الرفع المتعدّد: رفع الملفّ (والصورة) إلى Storage فقط، وإرجاع
  /// الحمولة الجاهزة للكتابة — **دون** كتابة Firestore (تتمّ لاحقاً بترتيب
  /// الاختيار عبر [commitPrepared]). يطابق سلوك الويب: رفع متوازٍ + كتابة
  /// القاعدة بترتيب الاختيار حرفيّاً.
  Future<Map<String, dynamic>> prepareUpload({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
    required Map<String, dynamic> metadata,
    Uint8List? thumbBytes,
    String? thumbName,
    void Function(double pct)? onProgress,
    bool Function()? isAborted,
  }) async {
    final fileId = generateNebrasFileId();

    String? thumbUrl;
    if (thumbBytes != null) {
      final tRes = await smartUpload(
        bytes: thumbBytes,
        filename: 'thumbnail_${DateTime.now().millisecondsSinceEpoch}_${thumbName ?? 'thumb'}',
        folder: 'dashboard/content/$fileId',
        contentType: 'image/jpeg',
      );
      thumbUrl = tRes.url;
    }

    final res = await smartUpload(
      bytes: bytes,
      filename: filename,
      folder: 'dashboard/content/$fileId',
      contentType: mimeType.isEmpty ? 'application/octet-stream' : mimeType,
      onProgress: onProgress,
      isAborted: isAborted,
    );

    final meta = <String, dynamic>{...metadata};
    if (thumbUrl != null) meta['thumbnail'] = thumbUrl;
    meta['content_type'] = meta['content_type'] ?? contentTypeFromMime(mimeType);

    final compatible = buildMobileCompatibleFields(meta, res.url);
    return <String, dynamic>{
      'fileId': fileId,
      'id': fileId,
      'downloadUrl': res.url,
      'filename': filename,
      'fileType': mimeType,
      'fileSize': bytes.length,
      'metadata': meta,
      'storagePath': res.path,
      'createdAt': FieldValue.serverTimestamp(),
      ...compatible,
    };
  }

  /// مثل [prepareUpload] لكن يرفع من مسار ملفّ (بثّ) بدل بايتات في الذاكرة —
  /// آمن للملفّات الكبيرة (يتفادى OOM).
  Future<Map<String, dynamic>> prepareUploadPath({
    required String filePath,
    required String filename,
    required String mimeType,
    required Map<String, dynamic> metadata,
    Uint8List? thumbBytes,
    String? thumbName,
    void Function(double pct)? onProgress,
    bool Function()? isAborted,
  }) async {
    final fileId = generateNebrasFileId();

    String? thumbUrl;
    if (thumbBytes != null) {
      final tRes = await smartUpload(
        bytes: thumbBytes,
        filename: 'thumbnail_${DateTime.now().millisecondsSinceEpoch}_${thumbName ?? 'thumb'}',
        folder: 'dashboard/content/$fileId',
        contentType: 'image/jpeg',
      );
      thumbUrl = tRes.url;
    }

    final res = await smartUploadFile(
      file: File(filePath),
      filename: filename,
      folder: 'dashboard/content/$fileId',
      contentType: mimeType.isEmpty ? 'application/octet-stream' : mimeType,
      onProgress: onProgress,
      isAborted: isAborted,
    );

    final meta = <String, dynamic>{...metadata};
    if (thumbUrl != null) meta['thumbnail'] = thumbUrl;
    meta['content_type'] = meta['content_type'] ?? contentTypeFromMime(mimeType);

    final compatible = buildMobileCompatibleFields(meta, res.url);
    return <String, dynamic>{
      'fileId': fileId,
      'id': fileId,
      'downloadUrl': res.url,
      'filename': filename,
      'fileType': mimeType,
      'fileSize': res.size,
      'metadata': meta,
      'storagePath': res.path,
      'createdAt': FieldValue.serverTimestamp(),
      ...compatible,
    };
  }

  /// رفع ملفّ مفرد من المسار (بثّ) ثم كتابته — لشاشة «رفع ملف» في المحتوى.
  Future<String> createContentPath({
    required String filePath,
    required String filename,
    required String mimeType,
    required Map<String, dynamic> metadata,
    Uint8List? thumbBytes,
    String? thumbName,
    void Function(double pct)? onProgress,
  }) async {
    final prepared = await prepareUploadPath(
      filePath: filePath,
      filename: filename,
      mimeType: mimeType,
      metadata: metadata,
      thumbBytes: thumbBytes,
      thumbName: thumbName,
      onProgress: onProgress,
    );
    await commitPrepared(prepared);
    return '${prepared['fileId']}';
  }

  /// المرحلة 2: كتابة الحمولة المُعدّة في المجموعتين (مرآة).
  Future<void> commitPrepared(Map<String, dynamic> prepared) async {
    await _fs.writeFileMirrorBoth(prepared['fileId'], prepared);
  }

  // ─── تعديل ───────────────────────────────────────────────

  /// تعديل بيانات المحتوى. تمرير حقول null = لا تغيير.
  /// [move] إن صحّ يُعاد حساب المسار القانونيّ من الأقسام الممرَّرة.
  Future<void> updateContent(
    String fileId, {
    String? title,
    String? description,
    String? author,
    bool? isListed,
    String? contentType,
    bool move = false,
    dynamic mainSection,
    dynamic subsection,
    dynamic secondarySubsection,
    Uint8List? thumbBytes,
    String? thumbName,
  }) async {
    final current = await _fs.getFileRow(fileId);
    if (current == null || current.isEmpty) throw Exception('File not found');

    final currentMeta = (current['metadata'] as Map?)?.cast<String, dynamic>() ?? {};
    final nextMeta = <String, dynamic>{...currentMeta};
    if (title != null) nextMeta['title'] = title.trim();
    if (description != null) nextMeta['description'] = description.trim();
    if (author != null) nextMeta['author'] = author.trim();
    if (isListed != null) nextMeta['is_listed'] = isListed;
    if (contentType != null) nextMeta['content_type'] = contentType.trim();
    if (move) {
      nextMeta['main_section'] = mainSection;
      nextMeta['subsection'] = subsection;
      nextMeta['secondary_subsection'] = secondarySubsection;
    }

    final next = <String, dynamic>{...current, 'metadata': nextMeta};

    if (thumbBytes != null) {
      final tRes = await smartUpload(
        bytes: thumbBytes,
        filename: 'thumbnail_${DateTime.now().millisecondsSinceEpoch}_${thumbName ?? 'thumb'}',
        folder: 'dashboard/content/$fileId',
        contentType: 'image/jpeg',
      );
      nextMeta['thumbnail'] = tRes.url;
    }

    Map<String, dynamic>? trail;
    if (move) {
      trail = await _resolveTrail(
        mainSection: nextMeta['main_section'],
        subsection: nextMeta['subsection'],
        secondarySubsection: nextMeta['secondary_subsection'],
      );
      if (trail['subsection'] == null) {
        throw Exception(
            'اختر قسمًا فرعيًّا صالحًا قبل الحفظ — لا يمكن نقل المحتوى إلى قسم رئيسي بلا قسم فرعي.');
      }
      nextMeta.addAll(trail);
    }

    next.addAll(_buildUploadMirrorFields(next, nextMeta));
    if (trail != null) {
      for (final k in [
        'main_section',
        'main_section_id',
        'main_section_name',
        'subsection',
        'subsection_name',
        'secondary_subsection',
        'secondary_subsection_name',
      ]) {
        next[k] = trail[k];
      }
    }

    await _fs.writeFileMirrorBoth(fileId, next);
  }

  Map<String, dynamic> _buildUploadMirrorFields(
    Map<String, dynamic> current,
    Map<String, dynamic> metadata,
  ) {
    final contentType = '${metadata['content_type'] ?? current['content_type'] ?? ''}'
        .trim()
        .toLowerCase();
    final sourceUrl = '${current['downloadUrl'] ?? current['sourceUrl'] ?? current['file_url'] ?? current['audio_url'] ?? current['video_url'] ?? ''}'
        .trim();
    return {
      'id': current['fileId'] ?? current['id'],
      'title': metadata['title'] ?? current['title'],
      'description': metadata['description'] ?? current['description'],
      'author': metadata['author'] ?? current['author'],
      'thumbnail': metadata['thumbnail'] ?? current['thumbnail'],
      'content_type': metadata['content_type'] ?? current['content_type'],
      'subsection': metadata['subsection'] ?? current['subsection'],
      'subsection_name': metadata['subsection_name'] ?? current['subsection_name'],
      'secondary_subsection': metadata['secondary_subsection'] ?? current['secondary_subsection'],
      'secondary_subsection_name':
          metadata['secondary_subsection_name'] ?? current['secondary_subsection_name'],
      'main_section': metadata['main_section'] ?? current['main_section'],
      'main_section_id': metadata['main_section_id'] ?? current['main_section_id'],
      'main_section_name': metadata['main_section_name'] ?? current['main_section_name'],
      'sourceUrl': sourceUrl.isNotEmpty ? sourceUrl : current['sourceUrl'],
      'file_url': sourceUrl.isNotEmpty ? sourceUrl : current['file_url'],
      'audio_url': contentType == 'audio' ? sourceUrl : current['audio_url'],
      'video_url': contentType == 'video' ? sourceUrl : current['video_url'],
    };
  }

  String? _norm(dynamic v) {
    final s = '${v ?? ''}'.trim();
    return s.isEmpty ? null : s;
  }

  Future<Map<String, dynamic>> _resolveTrail({
    dynamic mainSection,
    dynamic subsection,
    dynamic secondarySubsection,
  }) async {
    var mainId = _norm(mainSection);
    var subId = _norm(subsection);
    var secId = _norm(secondarySubsection);
    String? mainName, subName, secName;

    if (secId != null) {
      final rec = await _fs.getSectionRecord('secondary', secId);
      if (rec != null) {
        secName = _norm(rec['name']);
        final parentSub = _norm(rec['sub_section']);
        if (parentSub != null) subId = parentSub;
      } else {
        secId = null;
      }
    }
    if (subId != null) {
      final rec = await _fs.getSectionRecord('sub', subId);
      if (rec != null) {
        subName = _norm(rec['name']);
        final parentMain = _norm(rec['main_section']);
        if (parentMain != null) mainId = parentMain;
      } else {
        subId = null;
        secId = null;
        secName = null;
      }
    } else {
      secId = null;
      secName = null;
    }
    if (mainId != null) {
      final rec = await _fs.getSectionRecord('main', mainId);
      if (rec != null) {
        mainName = _norm(rec['name']);
      } else {
        mainId = null;
      }
    }
    return {
      'main_section': mainId,
      'main_section_id': mainId,
      'main_section_name': mainName,
      'subsection': subId,
      'subsection_name': subName,
      'secondary_subsection': secId,
      'secondary_subsection_name': secName,
    };
  }

  // ─── حذف ─────────────────────────────────────────────────

  Future<void> removeFile(String fileId) async {
    final item = await _fs.getFileRow(fileId);
    if (item == null || item.isEmpty) return;

    final isIa = item['__provider'] == 'internet_archive' ||
        '${item['__iaIdentifier'] ?? ''}'.trim().isNotEmpty;
    if (isIa) {
      await ApiClient.instance.authedJson(
        '/api/admin/internet-archive/dmca',
        method: 'POST',
        body: {'fileId': fileId, 'reason': 'manual_delete_dashboard'},
      );
      return;
    }

    await _deleteAssets(_collectAssetUrls(item));
    final storagePath = '${item['storagePath'] ?? ''}'.trim();
    if (storagePath.isNotEmpty) {
      try {
        await FirebaseStorage.instance.ref(storagePath).delete();
      } catch (_) {}
    }
    await _fs.deleteFileMirrorBoth(fileId);
  }

  List<String> _collectAssetUrls(Map<String, dynamic> row) {
    final md = (row['metadata'] as Map?) ?? {};
    final raw = <dynamic>[
      row['thumbnail'],
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
      } catch (_) {}
    }
  }
}
