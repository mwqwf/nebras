// نظائر `nebrasUnifiedSanitize.js`.

/// أقصى طول لحقل الوصف المخزَّن (بالأحرف) — يمنع تضخّم الوثيقة وانهيار قراءة
/// الجوال. مطابق لـ `MAX_CONTENT_DESCRIPTION_CHARS`.
const int kMaxContentDescriptionChars = 8000;

/// إزالة القيم `null` بعمق (نظير `stripUndefinedDeep` — في Dart نعامل `null`
/// كـ `undefined`: لا نكتبها إلى Firestore).
dynamic stripNullsDeep(dynamic value) {
  if (value is List) {
    return value
        .map(stripNullsDeep)
        .where((item) => item != null)
        .toList();
  }
  if (value is Map) {
    final out = <String, dynamic>{};
    value.forEach((k, v) {
      final cleaned = stripNullsDeep(v);
      if (cleaned != null) out['$k'] = cleaned;
    });
    return out;
  }
  return value;
}

String _clampString(String value, int max) {
  if (value.length <= max) return value;
  return '${value.substring(0, max).trimRight()}…';
}

/// يقصّ حقول الوصف الضخمة (`description` في الجذر وداخل `metadata`) قبل الكتابة.
Map<String, dynamic> clampContentTextFields(Map<String, dynamic> payload) {
  final out = Map<String, dynamic>.from(payload);
  final desc = out['description'];
  if (desc is String) {
    out['description'] = _clampString(desc, kMaxContentDescriptionChars);
  }
  final md = out['metadata'];
  if (md is Map) {
    final m = Map<String, dynamic>.from(md);
    final mdDesc = m['description'];
    if (mdDesc is String) {
      m['description'] = _clampString(mdDesc, kMaxContentDescriptionChars);
    }
    out['metadata'] = m;
  }
  return out;
}
