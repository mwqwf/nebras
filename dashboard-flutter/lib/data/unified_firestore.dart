import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/firestore_refs.dart';
import 'sanitize.dart';

/// قراءات/كتابات Firestore للمحتوى الموحّد — نظير
/// `nebrasUnifiedFirestoreClient.js` (لكن بصلاحيّات المستخدم عبر Firebase SDK).
class UnifiedFirestore {
  UnifiedFirestore._();
  static final UnifiedFirestore instance = UnifiedFirestore._();

  FirebaseFirestore get _db => nebrasFirestore();

  // ─── الأقسام (sections_unified: 3 وثائق main/sub/secondary) ───────────────
  //
  // الأقسام تتغيّر نادراً وتُقرأ كثيراً (منتقيات الرفع/التعديل). نُخزّنها مؤقتاً
  // لتفادي ضرب Firestore عند كل فتح، ونُبطل الكاش عند أي كتابة/حذف قسم.
  final Map<String, Map<String, dynamic>> _sectionDocCache = {};
  final Map<String, DateTime> _sectionDocCacheAt = {};
  static const _sectionTtl = Duration(seconds: 30);

  void _invalidateSectionsCache() {
    _sectionDocCache.clear();
    _sectionDocCacheAt.clear();
  }

  Future<Map<String, dynamic>> _readSectionDoc(String level) async {
    final at = _sectionDocCacheAt[level];
    if (at != null && DateTime.now().difference(at) < _sectionTtl) {
      return _sectionDocCache[level] ?? {};
    }
    final snap = await _db.collection(FsPaths.sections).doc(level).get();
    final data = snap.exists ? Map<String, dynamic>.from(snap.data() ?? {}) : <String, dynamic>{};
    _sectionDocCache[level] = data;
    _sectionDocCacheAt[level] = DateTime.now();
    return data;
  }

  /// قراءة مستوى أقسام كاملاً كقائمة سجلّات.
  Future<List<Map<String, dynamic>>> readSectionsLevel(String level) async {
    final data = await _readSectionDoc(level);
    return data.values
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<Map<String, dynamic>> readSectionsSubMap() => _readSectionDoc('sub');

  Future<Map<String, dynamic>?> getSectionRecord(String level, dynamic id) async {
    final data = await _readSectionDoc(level);
    final v = data['$id'];
    return v is Map ? Map<String, dynamic>.from(v) : null;
  }

  Future<void> setSectionRecord(String level, dynamic id, Map<String, dynamic> value) async {
    final key = '$id';
    await _db.collection(FsPaths.sections).doc(level).set(
      {key: stripNullsDeep(value)},
      SetOptions(merge: true),
    );
    _invalidateSectionsCache();
  }

  Future<void> deleteSectionRecord(String level, dynamic id) async {
    final ref = _db.collection(FsPaths.sections).doc(level);
    final s = await ref.get();
    if (!s.exists) return;
    await ref.update({'$id': FieldValue.delete()});
    _invalidateSectionsCache();
  }

  // ─── يوتيوب (قراءة/حذف فقط — لتنظيف السجلّات القديمة عند حذف الأقسام) ──────

  Future<List<Map<String, dynamic>>> listYoutubeRecords() async {
    final snap = await _db.collection(FsPaths.contentYoutube).get();
    return snap.docs.map((d) {
      final data = Map<String, dynamic>.from(d.data());
      data['id'] = data['id'] ?? d.id;
      return data;
    }).toList();
  }

  Future<void> deleteYoutubeRecord(dynamic id) async {
    await _db.collection(FsPaths.contentYoutube).doc('$id').delete();
  }

  // ─── ملفّات المحتوى (dashboard_uploads + content_unified_files) ────────────

  // كاش قصير لصفوف الملفّات — مجموعة المحتوى ضخمة (آلاف الوثائق)، فلا نُعيد
  // قراءتها عند كل بحث/فلتر/تنقّل صفحات. يُبطَل عند أي كتابة/حذف محتوى.
  List<Map<String, dynamic>>? _fileRowsCache;
  DateTime? _fileRowsCacheAt;
  static const _fileRowsTtl = Duration(seconds: 60);

  void _invalidateFileRowsCache() {
    _fileRowsCache = null;
    _fileRowsCacheAt = null;
  }

  /// دمج صفوف الملفّات من المجموعتين (كما يفعل التطبيق عند القراءة).
  Future<List<Map<String, dynamic>>> listFileRowsMerged({bool force = false}) async {
    final at = _fileRowsCacheAt;
    if (!force &&
        _fileRowsCache != null &&
        at != null &&
        DateTime.now().difference(at) < _fileRowsTtl) {
      return _fileRowsCache!;
    }
    final results = await Future.wait([
      _db.collection(FsPaths.uploads).get(),
      _db.collection(FsPaths.contentFiles).get(),
    ]);
    final rows = <Map<String, dynamic>>[];
    for (final snap in results) {
      for (final d in snap.docs) {
        final data = Map<String, dynamic>.from(d.data());
        data['id'] = data['id'] ?? d.id;
        data['fileId'] = data['fileId'] ?? d.id;
        rows.add(data);
      }
    }
    _fileRowsCache = rows;
    _fileRowsCacheAt = DateTime.now();
    return rows;
  }

  Future<Map<String, dynamic>?> getFileRow(dynamic fileId) async {
    final id = '$fileId';
    final primary = await _db.collection(FsPaths.uploads).doc(id).get();
    if (primary.exists) return Map<String, dynamic>.from(primary.data() ?? {});
    final fallback = await _db.collection(FsPaths.contentFiles).doc(id).get();
    return fallback.exists ? Map<String, dynamic>.from(fallback.data() ?? {}) : null;
  }

  /// كتابة وثيقة الملفّ في المجموعتين معاً (writeBatch) — نفس حركة الويب.
  Future<void> writeFileMirrorBoth(dynamic fileId, Map<String, dynamic> payload) async {
    final id = '$fileId';
    final data = stripNullsDeep(clampContentTextFields(payload)) as Map<String, dynamic>;
    final batch = _db.batch();
    batch.set(_db.collection(FsPaths.uploads).doc(id), data);
    batch.set(_db.collection(FsPaths.contentFiles).doc(id), data);
    await batch.commit();
    _invalidateFileRowsCache();
  }

  Future<void> deleteFileMirrorBoth(dynamic fileId) async {
    final id = '$fileId';
    final batch = _db.batch();
    batch.delete(_db.collection(FsPaths.uploads).doc(id));
    batch.delete(_db.collection(FsPaths.contentFiles).doc(id));
    await batch.commit();
    _invalidateFileRowsCache();
  }
}
