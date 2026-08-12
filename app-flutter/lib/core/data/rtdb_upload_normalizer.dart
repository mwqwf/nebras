import 'package:easy_localization/easy_localization.dart';

/// يطابق حقول رفع لوحة التحكّم (`dashboard_uploads` ومرآة الملفات) مع ما يتوقعه [Content.fromJson].
class RtdbUploadNormalizer {
  RtdbUploadNormalizer._();

  static const String _implicitSecondaryPrefix = '__implicit__';
  static const Set<String> _nestedContentFragmentKeys = {
    'metadata',
    'youtube_video',
    'r2_file',
  };

  /// جذر عقدة RTDB قد يكون خريطة أو قائمة عناصر.
  static Map<String, dynamic> normalizeDatabaseRoot(dynamic value) {
    if (value is List) {
      return {'_root': value};
    }
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    return {};
  }

  /// يجمع عدة جذور RTDB في خريطة واحدة معزولة حتى نستطيع المرور عليها
  /// كوحدة واحدة بدون تعارض مفاتيح بين المسارات المختلفة.
  static Map<String, dynamic> combineDatabaseRoots(Map<String, dynamic> roots) {
    final combined = <String, dynamic>{};
    roots.forEach((key, value) {
      final normalized = normalizeDatabaseRoot(value);
      if (normalized.isNotEmpty) {
        combined[key] = normalized;
      }
    });
    return combined;
  }

  static bool looksLikeContentMap(Map<String, dynamic> map) {
    final metadata = _coerceMap(map['metadata']);
    final hasTitle =
        (map['title']?.toString().trim().isNotEmpty ?? false) ||
        (metadata?['title']?.toString().trim().isNotEmpty ?? false);
    final hasName =
        (map['name']?.toString().trim().isNotEmpty ?? false) ||
        (metadata?['name']?.toString().trim().isNotEmpty ?? false);
    final hasType =
        (map['content_type']?.toString().trim().isNotEmpty ?? false) ||
        (map['type']?.toString().trim().isNotEmpty ?? false) ||
        (metadata?['content_type']?.toString().trim().isNotEmpty ?? false) ||
        (metadata?['type']?.toString().trim().isNotEmpty ?? false);
    final hasSource =
        _nonEmpty(map['sourceUrl']) ||
        _nonEmpty(map['source_url']) ||
        _nonEmpty(map['file_url']) ||
        _nonEmpty(map['audio_url']) ||
        _nonEmpty(map['video_url']) ||
        _nonEmpty(map['downloadUrl']) ||
        _nonEmpty(map['youtube_url']) ||
        _nonEmpty(map['youtube_link']) ||
        _nonEmpty(map['youtube']) ||
        _nonEmpty(map['url']) ||
        _nonEmpty(map['link']) ||
        _nestedMediaUrl(map['youtube_video']) != null ||
        _nestedMediaUrl(map['r2_file']) != null;
    final hasSectionHints =
        _nonEmpty(map['subsection']) ||
        _nonEmpty(map['sub_section']) ||
        _nonEmpty(map['subsection_id']) ||
        _nonEmpty(map['secondary_subsection']) ||
        _nonEmpty(map['secondary_section']) ||
        _nonEmpty(map['secondary_subsection_id']) ||
        _nonEmpty(map['main_section']) ||
        _nonEmpty(map['main_section_id']) ||
        _nonEmpty(map['main_section_name']) ||
        _nonEmpty(metadata?['subsection']) ||
        _nonEmpty(metadata?['secondary_subsection']) ||
        _nonEmpty(metadata?['main_section']) ||
        _nonEmpty(metadata?['main_section_id']) ||
        _nonEmpty(metadata?['main_section_name']);
    final hasNestedMediaHints =
        map['r2_file'] is Map ||
        map['youtube_video'] is Map ||
        _nonEmpty(map['thumbnail']) ||
        _nonEmpty(metadata?['thumbnail']);
    final hasUploadIdentity =
        _nonEmpty(map['fileId']) ||
        _nonEmpty(map['filename']) ||
        _nonEmpty(map['storagePath']) ||
        _nonEmpty(map['downloadUrl']) ||
        map['fileSize'] != null;

    // Keep this intentionally permissive for RTDB variants:
    // some rows are missing explicit content_type/title but still valid media rows.
    return hasType ||
        hasSource ||
        (hasUploadIdentity && (hasTitle || hasType || hasSectionHints)) ||
        (hasSectionHints && (hasTitle || hasName || hasNestedMediaHints));
  }

  static bool shouldTreatAsContentNode(
    Map<String, dynamic> map, {
    String? keyHint,
  }) {
    final normalizedKey = (keyHint ?? '').trim().toLowerCase();
    // ── إصلاح: المتجزّآت المضمَّنة (metadata / youtube_video / r2_file) ليست
    // عقداً مستقلّة للمحتوى حتى لو كان فيها id/fileId (مثل مستندات IA التي
    // تضع id داخل metadata). استثناؤها دائماً يمنع إنشاء صفوف وهمية مزدوجة
    // تسبّب ظهور "مصدر غير متاح" عند الضغط على نسخة الشبح.
    if (_nestedContentFragmentKeys.contains(normalizedKey)) return false;
    return looksLikeContentMap(map);
  }

  /// يملأ `subsection` / `secondary_subsection` بأسماء بديلة شائعة في RTDB.
  /// إن وُجد فرعي فقط بدون ثانوي يُنشئ معرفًا ثابتًا حتى يمرّ فلتر التسلسل في الواجهة.
  static Map<String, dynamic> normalizeRow(Map<String, dynamic> row) {
    final out = Map<String, dynamic>.from(row);
    final metadata = _coerceMap(out['metadata']);

    out['id'] ??= _firstNonEmpty(
      _coerceString(out['fileId']),
      _coerceString(metadata?['id']),
    );
    out['title'] ??= metadata?['title'];
    out['description'] ??= metadata?['description'];
    out['author'] ??= metadata?['author'];
    out['thumbnail'] ??= metadata?['thumbnail'];
    out['content_type'] ??= metadata?['content_type'] ?? metadata?['type'];
    out['main_section'] ??= metadata?['main_section'];
    out['main_section_id'] ??= metadata?['main_section_id'];
    out['main_section_name'] ??= metadata?['main_section_name'];
    out['subsection'] ??= metadata?['subsection'];
    out['secondary_subsection'] ??= metadata?['secondary_subsection'];
    out['created_at'] ??= metadata?['created_at'] ?? out['createdAt'];
    out['updated_at'] ??= metadata?['updated_at'] ?? out['updatedAt'];
    out['selectionOrder'] ??=
        out['selectionIndex'] ?? metadata?['selectionOrder'] ?? metadata?['selectionIndex'];
    out['view_count'] ??= out['viewCount'] ?? metadata?['view_count'];
    out['popularity_score_7d'] ??=
        out['popularityScore7d'] ?? metadata?['popularity_score_7d'];
    out['created_by'] ??= metadata?['author'];
    out['sizeInBytes'] ??= out['fileSize'];

    var subsection = _firstNonEmpty(
      _coerceString(out['subsection']),
      _coerceString(out['sub_section']),
      _nestedId(out['subsection']),
      _coerceString(out['subsection_id']),
    );
    if (subsection.isNotEmpty) {
      out['subsection'] = subsection;
    }

    var secondary = _firstNonEmpty(
      _coerceString(out['secondary_subsection']),
      _coerceString(out['secondary_section']),
      _nestedId(out['secondary_subsection']),
      _coerceString(out['secondary_subsection_id']),
    );
    if (secondary.isNotEmpty) {
      out['secondary_subsection'] = secondary;
    }

    final subFinal = out['subsection']?.toString().trim() ?? '';
    var secFinal = out['secondary_subsection']?.toString().trim() ?? '';
    if (subFinal.isNotEmpty && secFinal.isEmpty) {
      secFinal = '$_implicitSecondaryPrefix$subFinal';
      out['secondary_subsection'] = secFinal;
    }

    final subName = _firstNonEmptyMany([
      _coerceString(out['subsection_name']),
      _coerceString(out['subsection_title']),
      _coerceString(out['subsection_label']),
      _coerceString(metadata?['subsection_name']),
      _coerceString(metadata?['subsection_title']),
    ]);
    if (subName.isNotEmpty &&
        (out['subsection_name'] == null ||
            out['subsection_name'].toString().trim().isEmpty)) {
      out['subsection_name'] = subName;
    }

    // Normalize media source URL variants used in RTDB rows.
    final sourceUrl = _firstNonEmptyMany([
      _coerceString(out['sourceUrl']),
      _coerceString(out['source_url']),
      _coerceString(out['file_url']),
      _coerceString(out['audio_url']),
      _coerceString(out['video_url']),
      _coerceString(out['downloadUrl']),
      _coerceString(out['youtube_url']),
      _coerceString(out['youtube_link']),
      _coerceString(out['youtube']),
      _coerceString(out['url']),
      _coerceString(out['link']),
      _nestedMediaUrl(out['youtube_video']),
      _nestedMediaUrl(out['r2_file']),
    ]);
    if (sourceUrl.isNotEmpty &&
        (out['sourceUrl'] == null ||
            out['sourceUrl'].toString().trim().isEmpty)) {
      out['sourceUrl'] = sourceUrl;
    }
    if (sourceUrl.isNotEmpty &&
        (out['file_url'] == null ||
            out['file_url'].toString().trim().isEmpty)) {
      out['file_url'] = sourceUrl;
    }

    final contentType = _coerceString(out['content_type'])?.toLowerCase() ?? '';
    if (sourceUrl.isNotEmpty &&
        contentType == 'audio' &&
        (out['audio_url'] == null ||
            out['audio_url'].toString().trim().isEmpty)) {
      out['audio_url'] = sourceUrl;
    }
    if (sourceUrl.isNotEmpty &&
        (contentType == 'video' || contentType == 'youtube') &&
        (out['video_url'] == null ||
            out['video_url'].toString().trim().isEmpty)) {
      out['video_url'] = sourceUrl;
    }

    return out;
  }

  /// تلميح لربط المحتوى بقسم رئيسي عند غياب شجرة فرعية كاملة في [sections_unified].
  static String mainSectionHint(Map<String, dynamic> row) {
    return _firstNonEmpty(
      _coerceString(row['main_section_id']),
      _coerceString(row['main_section']),
      _coerceString(row['main_section_slug']),
      _coerceString(row['main_section_name']),
    );
  }

  static bool isImplicitSecondaryId(String id) {
    return id.startsWith(_implicitSecondaryPrefix);
  }

  static String implicitSecondaryDisplayName(
    String id,
    String? subsectionName,
  ) {
    if (!isImplicitSecondaryId(id)) return id;
    final name = subsectionName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return 'Content'.tr();
  }

  static Map<String, String> mainIdLookup(
    Iterable<({String id, String name})> mains,
  ) {
    final map = <String, String>{};
    for (final m in mains) {
      final id = m.id.trim();
      if (id.isEmpty) continue;
      map[id] = id;
      final n = m.name.trim();
      if (n.isNotEmpty) {
        map[n] = id;
      }
    }
    return map;
  }

  static String? resolveMainId(String? hint, Map<String, String> lookup) {
    final k = (hint ?? '').trim();
    if (k.isEmpty) return null;
    return lookup[k];
  }

  static bool _nonEmpty(dynamic v) => _coerceString(v) != null;

  static String? _coerceString(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static String? _nestedId(dynamic v) {
    if (v is Map) {
      final m = v.map((key, val) => MapEntry(key.toString(), val));
      return _firstNonEmpty(_coerceString(m['id']), _coerceString(m['slug']));
    }
    return null;
  }

  static String? _nestedMediaUrl(dynamic v) {
    if (v is Map) {
      final m = v.map((key, val) => MapEntry(key.toString(), val));
      return _firstNonEmpty(
        _coerceString(m['video_url']),
        _coerceString(m['file_url']),
        _coerceString(m['url']),
        _coerceString(m['link']),
      );
    }
    return _coerceString(v);
  }

  static Map<String, dynamic>? _coerceMap(dynamic value) {
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    return null;
  }

  static String _firstNonEmpty(String? a, [String? b, String? c, String? d]) {
    for (final value in [a, b, c, d]) {
      final normalized = (value ?? '').trim();
      if (normalized.isNotEmpty) return normalized;
    }
    return '';
  }

  static String _firstNonEmptyMany(Iterable<String?> values) {
    for (final value in values) {
      final normalized = (value ?? '').trim();
      if (normalized.isNotEmpty) return normalized;
    }
    return '';
  }
}
