import 'dart:math';

/// نظائر `nebrasMobileUploadSchema.js` — حقول مرآة Firestore المتوافقة مع
/// تطبيق Flutter (Content.fromJson) وترتيب «الأقدم أوّلاً».

/// معرّف ملفّ بصيغة `fb_<epoch>_…` ليتوافق ترتيب التطبيق (الأقدم أولاً).
String generateNebrasFileId() {
  final rnd = Random();
  final suffix = List.generate(8, (_) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return chars[rnd.nextInt(chars.length)];
  }).join();
  return 'fb_${DateTime.now().millisecondsSinceEpoch}_$suffix';
}

/// يبني الحقول المتوافقة مع الجوال من الميتاداتا ورابط التنزيل.
/// المفاتيح ذات القيمة null تُحذف لاحقاً عبر [stripNullsDeep].
Map<String, dynamic> buildMobileCompatibleFields(
  Map<String, dynamic> metadata,
  String downloadUrl,
) {
  final contentTypeRaw =
      (metadata['content_type'] ?? 'document').toString().trim().toLowerCase();
  final contentType = contentTypeRaw.isEmpty ? 'document' : contentTypeRaw;

  final sourceFields = <String, dynamic>{
    'sourceUrl': downloadUrl,
    'source_url': downloadUrl,
    'file_url': downloadUrl,
  };
  if (contentType == 'audio') sourceFields['audio_url'] = downloadUrl;
  if (contentType == 'video') sourceFields['video_url'] = downloadUrl;

  return {
    'id': metadata['id'],
    'title': metadata['title'],
    'description': metadata['description'],
    'author': metadata['author'],
    'thumbnail': metadata['thumbnail'],
    'content_type': metadata['content_type'],
    'subsection': metadata['subsection'],
    'subsection_name':
        metadata['subsection_name'] ?? metadata['subsection_title'],
    'secondary_subsection': metadata['secondary_subsection'],
    'secondary_subsection_name': metadata['secondary_subsection_name'] ??
        metadata['secondary_subsection_title'],
    'main_section': metadata['main_section'],
    'main_section_id': metadata['main_section_id'],
    'main_section_name': metadata['main_section_name'],
    ...sourceFields,
  };
}
