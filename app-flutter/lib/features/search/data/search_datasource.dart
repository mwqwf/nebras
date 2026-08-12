import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:nebras_mobile_app/core/data/content_ordering.dart';
import 'package:nebras_mobile_app/core/data/rtdb_upload_normalizer.dart';
import 'package:nebras_mobile_app/core/error/error_handler.dart';
import 'package:nebras_mobile_app/core/services/hidden_content_service.dart';
import 'package:nebras_mobile_app/features/content/cache/content_metadata_cache.dart';
import 'package:nebras_mobile_app/features/content/model/content_model.dart';
import 'package:nebras_mobile_app/features/search/data/search_section_option.dart';

/// Search Remote Datasource
/// Handles all search-related API calls via Dio
/// Uses DioClient singleton — NO direct URL construction
class SearchDatasource {
  final FirebaseFirestore firestore;
  final ContentMetadataCache? metadataCache;

  SearchDatasource(this.firestore, {this.metadataCache});

  /// نفس تسميات المجموعات في [HomeDatasource] (توافق مع تصدير RTDB → Firestore).
  static const _pathSections = 'sections_unified';
  static const _pathUploads = 'dashboard_uploads';
  static const _pathContentFiles = 'content_unified_files';
  static const _pathContentYoutube = 'content_unified_youtube';

  static Map<String, dynamic> _docsToIdMap(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final map = <String, dynamic>{};
    for (final doc in snapshot.docs) {
      map[doc.id] = doc.data();
    }
    return map;
  }

  /// Search content by query with optional filters
  /// Uses /api/public/metadata/?search=term
  Future<List<Content>> search({
    required String query,
    ContentType? type,
    String? section,
    String? subSection,
  }) async {
    try {
      final items = await _loadAllContent();
      final normalizedQuery = query.trim().toLowerCase();

      final filtered = items.where((item) {
        if (normalizedQuery.isNotEmpty) {
          // كان البحث المباشر على Firebase يقتصر على title + description،
          // فعناصر تطابق المؤلّف أو اسم القسم لا تظهر إلّا عبر البحث المحلّي.
          // نوسّع المطابقة هنا حتى تظهر تلك العناصر حتى لو كانت أقسام
          // HomeProvider لم تُحمَّل بعد (مثل قبل توفّر بيانات الجسر).
          final inTitle = item.title.toLowerCase().contains(normalizedQuery);
          final inDesc = item.description.toLowerCase().contains(
            normalizedQuery,
          );
          final inAuthor = item.author.toLowerCase().contains(normalizedQuery);
          final inSectionName =
              (item.sectionName ?? '').toLowerCase().contains(normalizedQuery);
          if (!inTitle && !inDesc && !inAuthor && !inSectionName) return false;
        }
        if (type != null && item.type != type) return false;
        if (section != null && section.isNotEmpty && item.section != section) {
          return false;
        }
        if (subSection != null &&
            subSection.isNotEmpty &&
            item.subSection != subSection) {
          return false;
        }
        return true;
      }).toList();

      debugPrint('[SearchDatasource] firestore search results: ${filtered.length}');
      return filtered;
    } catch (e) {
      throw ErrorHandler.handleException(e);
    }
  }

  /// Get all main section options (Firestore: مستند `sections_unified/main`).
  ///
  /// لوحة التحكم تحفظ الأقسام الرئيسية تحت [sections_unified/main] بصيغة مسطّحة،
  /// لذا نقرأ من هذا المسار مباشرة. إن كان فارغًا نرجع للقراءة من الجذر
  /// للتوافق مع قواعد بيانات قديمة قد تكون بصيغة شجرية.
  Future<List<SearchSectionOption>> getSections() async {
    try {
      final rows = <SearchSectionOption>[];

      void addMainOption(String? keyHint, dynamic value) {
        if (value is List) {
          for (var i = 0; i < value.length; i++) {
            addMainOption(keyHint != null ? '$keyHint:$i' : '$i', value[i]);
          }
          return;
        }
        final map = _asMap(value);
        final listed = map['is_listed'];
        if (listed != null) {
          final asBool = listed is bool
              ? listed
              : listed.toString().toLowerCase() != 'false' &&
                    listed.toString() != '0';
          if (!asBool) return;
        }
        final id = _firstNonEmpty(
          map['id']?.toString(),
          map['slug']?.toString(),
          keyHint,
        );
        final name = _firstNonEmpty(
          map['name']?.toString(),
          map['title']?.toString(),
          id,
        );
        if (id.isNotEmpty) {
          rows.add(SearchSectionOption(id: id, name: name));
        }
      }

      final mainDoc =
          await firestore.collection(_pathSections).doc('main').get();
      final mainData = mainDoc.data();
      if (mainData != null) {
        mainData.forEach((k, v) => addMainOption(k.toString(), v));
      }

      if (rows.isEmpty) {
        final sectionsRoot = await _readSectionsRoot();
        sectionsRoot.forEach((key, value) {
          if (key == 'main' || key == 'sub' || key == 'secondary') return;
          addMainOption(key, value);
        });
      }

      return rows;
    } catch (e) {
      throw ErrorHandler.handleException(e);
    }
  }

  /// Get content by section key (Firestore: uploads + files + youtube).
  /// الأقدم أولاً — [sortContentOldestFirst] / content_ordering.dart.
  Future<List<Content>> getSectionContent(String sectionId) async {
    try {
      final items = await _loadAllContent();
      final filtered = items
          .where((item) => item.section == sectionId)
          .toList();
      sortContentOldestFirst(filtered);
      debugPrint(
        '[SearchDatasource] firestore section "$sectionId": ${filtered.length} items',
      );
      return filtered;
    } catch (e) {
      throw ErrorHandler.handleException(e);
    }
  }

  Future<List<Content>> _loadAllContent() async {
    final snapshots = await Future.wait([
      firestore.collection(_pathUploads).get(),
      firestore.collection(_pathContentFiles).get(),
      firestore.collection(_pathContentYoutube).get(),
    ]);
    final contentRoot = RtdbUploadNormalizer.combineDatabaseRoots({
      'dashboard_uploads': _docsToIdMap(snapshots[0]),
      'content_unified_files': _docsToIdMap(snapshots[1]),
      'content_unified_youtube': _docsToIdMap(snapshots[2]),
    });
    final rows = _extractContentRows(contentRoot)
        .map(
          (r) =>
              RtdbUploadNormalizer.normalizeRow(Map<String, dynamic>.from(r)),
        )
        .toList();
    // إزالة المكرّرات: نفس منطق home_datasource.
    final seenIds = <String>{};
    final items = rows
        .map(_mapContentFromRtdb)
        // ⛓️ حارس "No source available" — استبعاد أي محتوى بدون رابط فعلي
        //    أو بـ license_status=rejected (Google Play compliance).
        //    نمنع ظهور وثيقة لا يستطيع المستخدم تشغيلها أصلاً.
        .where(_isPlayableAndCompliant)
        // إزالة المكرّرات بالـ id (مرآة dashboard_uploads + content_unified_files)
        .where((item) => seenIds.add(item.id))
        .toList();
    await metadataCache?.cacheMany(items);
    return items;
  }

  /// يستبعد المحتوى الذي:
  ///   • لا يحوي sourceUrl صالحاً → سيُظهر "No source available" عند الضغط
  ///   • أو بـ __license_status: 'rejected' (وضعه فريق DMCA)
  /// راجع `core/data/rtdb_upload_normalizer.dart` لتفاصيل التطبيع.
  static bool _isPlayableAndCompliant(Content item) {
    final url = item.sourceUrl?.trim() ?? '';
    if (url.isEmpty) return false;
    if (!(url.startsWith('http://') || url.startsWith('https://'))) return false;
    // التطبيق لا يتصل بـ archive.org إطلاقاً (Content.fromJson يُلغيه أصلاً،
    // وهذا حارس ثانٍ صريح).
    if (url.toLowerCase().contains('archive.org')) return false;
    // امتثال الحقوق: محتوى وضعته اللوحة كـ rejected يُحجب عن الجميع.
    if (item.licenseStatus == 'rejected') return false;
    // احترام رأي المُبلِّغ: لا يظهر له المحتوى الذي أبلغ عنه.
    if (HiddenContentService.instance.isHidden(item.id)) return false;
    return true;
  }

  Future<Map<String, dynamic>> _readSectionsRoot() async {
    final snapshot = await firestore.collection(_pathSections).get();
    final map = <String, dynamic>{};
    for (final doc in snapshot.docs) {
      map[doc.id] = doc.data();
    }
    return map;
  }

  List<Map<String, dynamic>> _extractContentRows(Map<String, dynamic> root) {
    final rows = <Map<String, dynamic>>[];

    void walk(dynamic value, {String? keyHint}) {
      if (value is Map) {
        final map = value.map((key, val) => MapEntry(key.toString(), val));
        if (RtdbUploadNormalizer.shouldTreatAsContentNode(
          map,
          keyHint: keyHint,
        )) {
          rows.add({
            'id': _firstNonEmpty(map['id']?.toString(), keyHint ?? ''),
            ...map,
          });
        }
        map.forEach((k, v) => walk(v, keyHint: k));
      } else if (value is List) {
        for (var i = 0; i < value.length; i++) {
          walk(value[i], keyHint: '$i');
        }
      }
    }

    walk(root);
    return rows;
  }

  Content _mapContentFromRtdb(Map<String, dynamic> row) {
    return Content.fromJson({...row, 'id': row['id']?.toString() ?? ''});
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    return {};
  }

  String _firstNonEmpty(String? a, [String? b, String? c]) {
    for (final value in [a, b, c]) {
      final normalized = (value ?? '').trim();
      if (normalized.isNotEmpty) return normalized;
    }
    return '';
  }
}
