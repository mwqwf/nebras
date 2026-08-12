import 'package:cloud_firestore/cloud_firestore.dart';

class Content {
  final String id;

  final String title;
  final String author;
  final String description;

  final ContentType type;

  final String thumbnailUrl;

  // Media-related
  final String? sourceUrl; // video, audio, pdf, youtube link
  final int? sizeInBytes; // null for youtube

  // Organization
  final String section;
  final String? subSection;
  final String? sectionName;

  // Metadata
  final DateTime createdAt;
  final DateTime updatedAt;
  final String createdBy;
  final int selectionOrder;

  /// عدّاد مشاهدات مجهول من التطبيق (`view_count` في Firestore).
  final int viewCount;

  /// درجة شعبية أسبوعية — تُملأ من تجميع اللوحة أو ترتيب محلي.
  final double popularityScore7d;

  /// ── حقول الامتثال للحقوق (Google Play / DMCA) ──────────────────────
  /// حالة الترخيص كما تضبطها لوحة التحكّم بعد التحقّق اليدويّ/الآليّ:
  ///   ''         → غير محدَّد (يُعرَض، توافقاً مع السلوك القديم).
  ///   'approved' → تحقّقنا أنّه ملكيّة عامّة/مرخّص للتوزيع.
  ///   'rejected' → بلاغ حقوق صحيح أو محتوى غير مرخّص ⇒ يُحجب عن الجميع.
  /// الحجب الفعليّ يجري في حُرّاس القوائم (`_isPlayableAndCompliant`).
  final String licenseStatus;

  /// اسم المصدر المعروض للإسناد (مثل: "Internet Archive"، "مؤسسة هنداوي"،
  /// "مكتبة نور"). شفافيّة المصدر تُطمئن المراجع والمستخدم.
  final String sourceName;

  /// اسم الرخصة المقروء (مثل: "Public Domain"، "CC BY 4.0").
  final String licenseName;

  /// رابط نصّ الرخصة (مثل صفحة Creative Commons أو licenseurl من الأرشيف).
  final String licenseUrl;

  const Content({
    required this.id,
    required this.title,
    required this.author,
    required this.description,
    required this.type,
    required this.thumbnailUrl,
    required this.section,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    this.selectionOrder = 0,
    this.viewCount = 0,
    this.popularityScore7d = 0,
    this.licenseStatus = '',
    this.sourceName = '',
    this.licenseName = '',
    this.licenseUrl = '',
    this.sourceUrl,
    this.sizeInBytes,
    this.subSection,
    this.sectionName,
  });

  factory Content.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    data['id'] = doc.id;
    return Content.fromJson(data);
  }

  /// Create Content from /api/public/all/ JSON response
  ///
  /// Root-level fields: id, title, description, content_type, author, thumbnail,
  ///                    subsection, secondary_subsection, created_by, created_at, updated_at
  /// Nested objects (nullable): youtube_video { video_url }, r2_file { file_url, file_size }
  ///
  /// NOTE: youtube_video and r2_file may arrive as a nested Map (full object)
  /// or as a plain int (foreign-key ID only) depending on the endpoint.
  /// The `is` check handles both cases safely without crashing.
  factory Content.fromJson(Map<String, dynamic> json) {
    final metadata = _asMap(json['metadata']);

    // ✅ FIXED — safe cast: returns null if value is int or any non-Map type
    final youtubeVideo = _asMap(json['youtube_video']);

    // ✅ FIXED — same safe cast for r2_file
    final r2File = _asMap(json['r2_file']);

    // sourceUrl: youtube_video.video_url OR r2_file.file_url
    final rawUrl =
        youtubeVideo?['video_url'] ??
        youtubeVideo?['url'] ??
        youtubeVideo?['link'] ??
        r2File?['file_url'] ??
        r2File?['url'] ??
        json['sourceUrl'] ??
        json['source_url'] ??
        json['file_url'] ??
        json['downloadUrl'] ??
        json['video_url'] ??
        json['audio_url'] ??
        json['youtube_url'] ??
        json['youtube_link'] ??
        json['youtube'] ??
        json['url'] ??
        json['link'];

    String? sourceUrl;

    if (rawUrl is String && rawUrl.trim().isNotEmpty) {
      // التطبيق قارئ من قاعدة البيانات فقط — لا علاقة له بـ archive.org.
      // أي رابط يشير للأرشيف يُلغى هنا فلا يُرسَل أيّ طلب إليه، ويُسقَط
      // العنصر لاحقاً عبر حارس القوائم (مصدر فارغ = غير قابل للعرض).
      sourceUrl = _rejectArchiveOrg(rawUrl);
    }

    final rawType =
        _stringValue(json['content_type']) ??
        _stringValue(metadata?['content_type']) ??
        _stringValue(json['type']) ??
        _stringValue(metadata?['type']);
    final parsedType = _parseType(rawType ?? 'video');
    // ── إصلاح حاسم لتمييز الصوت/الفيديو ────────────────────────────
    // قبل هذا التغيير كان المنطق يثق فقط بـ `content_type` مع override
    // واحد لـ YouTube. الواقع: لوحة التحكّم أحياناً تكتب أصواتًا بـ
    // content_type='video' أو تتركها فارغة (والافتراضي السابق=video)،
    // فتُفتح ملفّات `.mp3` في مشغّل الفيديو وتفشل. نستنبط النوع من
    // امتداد الـ URL كحارس أمان: تعمل فقط حين يكون الامتداد
    // قاطعًا (mp3/m4a/...) ولا تلمس الفيديوهات الشرعيّة.
    final ContentType resolvedType;
    if (_looksLikeYouTubeUrl(sourceUrl)) {
      resolvedType = ContentType.youtube;
    } else if (_looksLikeBookUrl(sourceUrl) &&
        parsedType != ContentType.book &&
        parsedType != ContentType.audio &&
        parsedType != ContentType.article &&
        parsedType != ContentType.image) {
      resolvedType = ContentType.book;
    } else if (_looksLikeAudioUrl(sourceUrl) &&
        parsedType != ContentType.audio &&
        parsedType != ContentType.book &&
        parsedType != ContentType.article &&
        parsedType != ContentType.image) {
      // النوع المُعلَن = video أو غير محسوم، والامتداد قاطع للصوت ⇒ override.
      resolvedType = ContentType.audio;
    } else {
      resolvedType = parsedType;
    }

    // sizeInBytes: from r2_file.file_size
    final sizeInBytes =
        _intValue(r2File?['file_size']) ??
        _intValue(json['sizeInBytes']) ??
        _intValue(json['fileSize']);

    return Content(
      id: _stringValue(json['id']) ?? _stringValue(json['fileId']) ?? '',
      title:
          _stringValue(json['title']) ?? _stringValue(metadata?['title']) ?? '',
      author:
          _stringValue(json['author']) ??
          _stringValue(metadata?['author']) ??
          _stringValue(json['created_by']) ??
          '',
      description:
          _stringValue(json['description']) ??
          _stringValue(metadata?['description']) ??
          '',
      type: resolvedType,
      thumbnailUrl:
          _rejectArchiveOrg(
            _stringValue(json['thumbnail']) ??
                _stringValue(metadata?['thumbnail']),
          ) ??
          '',
      section:
          _stringValue(json['subsection']) ??
          _stringValue(metadata?['subsection']) ??
          '',
      subSection:
          _stringValue(json['secondary_subsection']) ??
          _stringValue(metadata?['secondary_subsection']),
      sectionName:
          _stringValue(json['subsection_name']) ??
          _stringValue(metadata?['subsection_name']),
      sourceUrl: sourceUrl,
      sizeInBytes: sizeInBytes,
      createdAt: _parseDate(
        json['created_at'],
        metadata?['created_at'],
        json['createdAt'],
      ),
      updatedAt: _parseDate(
        json['updated_at'],
        metadata?['updated_at'],
        json['updatedAt'],
      ),
      createdBy:
          _stringValue(json['created_by']) ??
          _stringValue(metadata?['author']) ??
          '',
      selectionOrder:
          _intValue(json['selectionOrder']) ??
          _intValue(metadata?['selectionOrder']) ??
          0,
      viewCount:
          _intValue(json['view_count']) ??
          _intValue(json['viewCount']) ??
          _intValue(metadata?['view_count']) ??
          0,
      popularityScore7d:
          _doubleValue(json['popularity_score_7d']) ??
          _doubleValue(json['popularityScore7d']) ??
          0.0,
      licenseStatus:
          (_stringValue(json['license_status']) ??
                  _stringValue(json['__license_status']) ??
                  _stringValue(metadata?['license_status']) ??
                  '')
              .toLowerCase(),
      sourceName: _friendlySource(
        _stringValue(json['source_name']) ??
            _stringValue(json['source']) ??
            _stringValue(json['__source_provider']) ??
            _stringValue(json['__provider']) ??
            _stringValue(metadata?['source_name']) ??
            '',
      ),
      licenseName: _friendlyLicense(
        _stringValue(json['license_name']) ??
            _stringValue(json['license']) ??
            _stringValue(json['__license']) ??
            _stringValue(metadata?['license_name']) ??
            '',
      ),
      licenseUrl:
          _stringValue(json['license_url']) ??
          _stringValue(json['licenseurl']) ??
          _stringValue(json['__license_url']) ??
          _stringValue(metadata?['license_url']) ??
          '',
    );
  }

  /// يحوّل رمز/اسم المصدر إلى اسم عرض ودود. archive.org تُعرَض كـ
  /// "Internet Archive" (لا يُرسَل أيّ طلب إليها — نصّ إسناد فقط).
  static String _friendlySource(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return '';
    switch (v.toLowerCase()) {
      case 'archive.org':
      case 'internet_archive':
      case 'internetarchive':
        return 'Internet Archive';
      case 'hindawi':
        return 'مؤسسة هنداوي';
      case 'noor-library':
      case 'noor':
      case 'noorlib':
        return 'مكتبة نور';
      default:
        return v;
    }
  }

  /// يحوّل رمز الرخصة إلى اسم مقروء. الروابط تبقى كما هي في [licenseUrl].
  static String _friendlyLicense(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return '';
    final lower = v.toLowerCase();
    if (lower.contains('publicdomain') || lower == 'cc0' || lower == 'pd') {
      return 'Public Domain';
    }
    if (lower.startsWith('creative_commons') || lower.startsWith('cc-') ||
        lower.startsWith('cc ') || lower.contains('creativecommons')) {
      return 'Creative Commons';
    }
    // قيمة وصفيّة جاهزة (مثل "Public Domain") تُعرَض كما هي.
    return v;
  }

  /// يقطع أي علاقة بين التطبيق وموقع archive.org. التطبيق "قارئ" من
  /// Firestore/Storage فقط؛ المحتوى السليم تعيد اللوحة استضافته على
  /// Firebase Storage قبل وصوله. أي رابط أرشيف (قديم/متبقٍّ) يُعاد كـ
  /// null فلا يُحمَّل إطلاقاً ولا يظهر العنصر.
  static String? _rejectArchiveOrg(String? url) {
    if (url == null) return null;
    final u = url.trim();
    if (u.isEmpty) return null;
    if (u.toLowerCase().contains('archive.org')) return null;
    return u;
  }

  static double? _doubleValue(dynamic value) {
    if (value is num) return value.toDouble();
    final s = value?.toString();
    if (s == null || s.trim().isEmpty) return null;
    return double.tryParse(s);
  }

  /// Parse content_type from backend to app ContentType
  /// Backend: video, audio, document, youtube, image, article/text
  /// App: video, audio, book, youtube, image, article
  static ContentType _parseType(String value) {
    switch (value.toLowerCase()) {
      case 'video':
        return ContentType.video;
      case 'youtube':
        return ContentType.youtube;
      case 'audio':
        return ContentType.audio;
      case 'document':
      case 'book':
        return ContentType.book;
      case 'image':
      case 'images':
      case 'photo':
      case 'photos':
        return ContentType.image;
      case 'article':
      case 'articles':
        return ContentType.article;
      default:
        return ContentType.video;
    }
  }

  static bool _looksLikeYouTubeUrl(String? value) {
    final lower = (value ?? '').trim().toLowerCase();
    if (lower.isEmpty) return false;
    return lower.contains('youtube.com') ||
        lower.contains('youtu.be') ||
        lower.contains('youtube');
  }

  /// يكتشف ما إذا كان رابط المصدر ملفّ صوت من امتداده. نحدّ بقائمة
  /// واضحة لتجنّب أيّ تخمين خاطئ على فيديوهات شرعيّة. نَفصِل الـ query
  /// string قبل الفحص لأنّ بعض روابط CDN تذيّل توقيعًا بعد الامتداد.
  static bool _looksLikeAudioUrl(String? value) {
    final raw = (value ?? '').trim().toLowerCase();
    if (raw.isEmpty) return false;
    final pathOnly = raw.split('?').first.split('#').first;
    const audioExt = <String>[
      '.mp3',
      '.m4a',
      '.aac',
      '.wav',
      '.ogg',
      '.opus',
      '.flac',
      '.wma',
    ];
    for (final ext in audioExt) {
      if (pathOnly.endsWith(ext)) return true;
    }
    return false;
  }

  static bool _looksLikeBookUrl(String? value) {
    final raw = (value ?? '').trim().toLowerCase();
    if (raw.isEmpty) return false;
    final pathOnly = raw.split('?').first.split('#').first;
    const bookExt = <String>[
      '.pdf',
      '.epub',
      '.doc',
      '.docx',
      '.txt',
      '.rtf',
    ];
    for (final ext in bookExt) {
      if (pathOnly.endsWith(ext)) return true;
    }
    return false;
  }

  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    return null;
  }

  static String? _stringValue(dynamic value) {
    if (value == null) return null;
    final normalized = value.toString().trim();
    return normalized.isEmpty ? null : normalized;
  }

  static int? _intValue(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  static DateTime _parseDate(dynamic a, [dynamic b, dynamic c]) {
    for (final value in [a, b, c]) {
      if (value == null) continue;
      // Handle Firestore Timestamp
      if (value.runtimeType.toString() == 'Timestamp' || value is Timestamp) {
        return (value as Timestamp).toDate();
      }
      // Firebase serverTimestamp() يُعيد قيمة عددية بالمللي ثانية؛
      // لذلك نقبل أي num قبل محاولة التحليل كنص ISO.
      if (value is num) {
        final ms = value.toInt();
        if (ms > 0) return DateTime.fromMillisecondsSinceEpoch(ms);
        continue;
      }
      final str = value.toString().trim();
      if (str.isEmpty) continue;
      final iso = DateTime.tryParse(str);
      if (iso != null) return iso;
      // نص رقمي صرف مثل "1713456789000" (ms since epoch).
      final ms = int.tryParse(str);
      if (ms != null && ms > 0) {
        return DateTime.fromMillisecondsSinceEpoch(ms);
      }
    }
    return DateTime.now();
  }
}

enum ContentType { video, audio, book, youtube, image, article }

ContentType parseContentType(String value) {
  return Content._parseType(value);
}
