import 'package:nebras_mobile_app/features/content/model/content_model.dart';

/// Represents a section on the home screen
/// Each section has a title, a type for styling, and a list of content items.
///
/// Optional [archiveId]: رابط اختياري بمجموعة (Collection) من Internet
/// Archive. عند وجوده يُعرض محتوى الأرشيف تحت محتوى Firebase في شاشات
/// التصفّح المعنيّة (فرعي/ثانوي/قائمة محتوى). المحتوى المحلّي لا يُمسّ
/// أبداً — الأرشيف يُلحَق فقط بالذيل.
///
/// Optional [remoteSourceApp] / [remoteSourceLevel] / [remoteSourceId]:
/// حقول اختياريّة من لوحة التحكّم لربط قسم بمصدر بيانات خارجي عند الحاجة.
/// إن وُجدت تُقرأ من RTDB كما هي؛ غيابها يعني قسمًا نبراسيًّا عاديًّا.
class HomeSection {
  final String id;
  final String title;
  /// نوع العرض في اللوحة (مثل `videos`, `audios`, `books`).
  /// لا يُستخدم قسم Firestore `most_watched` بعد الآن — الشعبيّة من `view_count` والتجميع الأسبوعي.
  final String type;
  final String? parentId; // links sub/secondary to their parent section
  final String? imageUrl;
  final String? archiveId;
  final String? remoteSourceApp;
  final String? remoteSourceLevel; // 'main' | 'sub' | 'content'
  final String? remoteSourceId;
  final List<Content> items;
  final bool isOfflineCache;

  const HomeSection({
    required this.id,
    required this.title,
    required this.type,
    this.parentId,
    this.imageUrl,
    this.archiveId,
    this.remoteSourceApp,
    this.remoteSourceLevel,
    this.remoteSourceId,
    required this.items,
    this.isOfflineCache = false,
  });

  /// هل هذا القسم مرتبط بمصدر خارجي (مثل مشروع Firebase القديم)؟ يُستعمل
  /// من الجسر لتصفية الأقسام التي تحتاج إلى جلب محتوى إضافي.
  bool get hasRemoteSource {
    final app = remoteSourceApp?.trim();
    final id = remoteSourceId?.trim();
    return app != null && app.isNotEmpty && id != null && id.isNotEmpty;
  }

  HomeSection copyWith({
    String? id,
    String? title,
    String? type,
    String? parentId,
    String? imageUrl,
    String? archiveId,
    String? remoteSourceApp,
    String? remoteSourceLevel,
    String? remoteSourceId,
    List<Content>? items,
    bool? isOfflineCache,
  }) {
    return HomeSection(
      id: id ?? this.id,
      title: title ?? this.title,
      type: type ?? this.type,
      parentId: parentId ?? this.parentId,
      imageUrl: imageUrl ?? this.imageUrl,
      archiveId: archiveId ?? this.archiveId,
      remoteSourceApp: remoteSourceApp ?? this.remoteSourceApp,
      remoteSourceLevel: remoteSourceLevel ?? this.remoteSourceLevel,
      remoteSourceId: remoteSourceId ?? this.remoteSourceId,
      items: items ?? this.items,
      isOfflineCache: isOfflineCache ?? this.isOfflineCache,
    );
  }

  factory HomeSection.fromJson(Map<String, dynamic> json) {
    return HomeSection(
      id:
          json['id']?.toString() ??
          json['key']?.toString() ??
          '${json['type'] ?? ''}:${json['title'] ?? ''}',
      title: json['title'] as String? ?? '',
      type: json['type'] as String? ?? '',
      parentId: json['parent_id']?.toString(),
      imageUrl: json['image']?.toString() ?? json['image_url']?.toString(),
      archiveId: _normalize(
        json['archive_id']?.toString() ??
            json['archiveId']?.toString() ??
            json['ia_collection']?.toString(),
      ),
      remoteSourceApp: _normalize(
        json['remote_source_app']?.toString() ??
            json['remoteSourceApp']?.toString(),
      ),
      remoteSourceLevel: _normalize(
        json['remote_source_level']?.toString() ??
            json['remoteSourceLevel']?.toString(),
      ),
      remoteSourceId: _normalize(
        json['remote_source_id']?.toString() ??
            json['remoteSourceId']?.toString(),
      ),
      items:
          (json['items'] as List?)
              ?.map((e) => Content.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      isOfflineCache: json['is_offline_cache'] == true,
    );
  }

  static String? _normalize(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
