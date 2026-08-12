import 'package:nebras_mobile_app/features/content/model/content_model.dart';

/// ترتيب عرض المحتوى داخل الأقسام (فرعية / ثانوية / رئيسية).
///
/// **القاعدة الثابتة:** الأقدم أولاً، الأحدث في الأسفل.
///
/// 1. [Content.createdAt] تصاعدياً (المفتاح الأساسي).
/// 2. عند تساوي التاريخ (مثلاً دفعة رفع متعدد من لوحة التحكم):
///    [Content.selectionOrder] تصاعدياً — يعكس ترتيب اختيار الملف في الطابور.
/// 3. الطابع الزمني المضمّن في المعرّف `fb_<epoch>_…` ثم المعرّف النصي.
///
/// يُستخدم في [HomeDatasource] عند تجميع `bySecondary` و`bySub`،
/// وفي [SearchDatasource] لنتائج القسم، وفي شاشات عرض القسم.
final RegExp contentIdEpochPattern = RegExp(r'^fb_(\d{10,})');

int contentIdEmbeddedEpoch(String id) {
  final match = contentIdEpochPattern.firstMatch(id);
  if (match == null) return 0;
  return int.tryParse(match.group(1)!) ?? 0;
}

/// مقارن موحّد: الأقدم أولاً (تصاعدي).
int compareContentOldestFirst(Content a, Content b) {
  final byDate = a.createdAt.compareTo(b.createdAt);
  if (byDate != 0) return byDate;

  final aOrd = a.selectionOrder;
  final bOrd = b.selectionOrder;
  if (aOrd != bOrd && (aOrd > 0 || bOrd > 0)) {
    return aOrd.compareTo(bOrd);
  }

  final byIdEpoch =
      contentIdEmbeddedEpoch(a.id).compareTo(contentIdEmbeddedEpoch(b.id));
  if (byIdEpoch != 0) return byIdEpoch;

  return a.id.compareTo(b.id);
}

/// يفرز قائمة المحتوى في المكان: الأقدم أولاً.
void sortContentOldestFirst(List<Content> items) {
  items.sort(compareContentOldestFirst);
}
