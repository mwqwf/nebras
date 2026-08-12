import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// نمطا عرض الأقسام داخل الشاشات الرئيسية/الفرعية/الثانوية.
///
/// [list] : النمط التقليدي — قائمة عمودية، عنصر واحد لكلّ صفّ.
/// [grid] : شبكة ثلاث أعمدة — حسب طلب المستخدم لرؤية أكثر من قسم دفعة واحدة.
enum SectionsLayout { list, grid }

/// مزوّد حالة بسيط يحفظ تفضيل المستخدم لطريقة عرض الأقسام بين الجلسات.
///
/// الفكرة:
///  - تُحمَّل القيمة من [SharedPreferences] مرّة واحدة عند إقلاع التطبيق
///    (من [loadFromPrefs]) حتى لا تنتظر الواجهة عمليّة قراءة إضافيّة عند
///    أوّل عرض.
///  - [toggle] يبدّل النمط الحالي ويحفظ التغيير فوراً حتى يبقى التفضيل
///    بعد إعادة التشغيل.
///  - الاستهلاك من الواجهات يتمّ عبر `context.watch<SectionsLayoutProvider>()`
///    لإعادة البناء التلقائي عند التبديل.
class SectionsLayoutProvider extends ChangeNotifier {
  static const _prefsKey = 'sections_layout_v1';

  SectionsLayout _layout = SectionsLayout.list;

  SectionsLayout get layout => _layout;
  bool get isGrid => _layout == SectionsLayout.grid;
  bool get isList => _layout == SectionsLayout.list;

  /// تحميل القيمة المحفوظة (إن وُجدت). آمنة لأيّ فشل في SharedPreferences
  /// — نبقى على القيمة الافتراضية [SectionsLayout.list].
  Future<void> loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == SectionsLayout.grid.name) {
        _layout = SectionsLayout.grid;
        notifyListeners();
      }
    } catch (_) {
      // نتجاهل — القيم الافتراضيّة كافية.
    }
  }

  /// يقلب النمط بين قائمة وشبكة ويحفظ التفضيل.
  Future<void> toggle() async {
    _layout = isGrid ? SectionsLayout.list : SectionsLayout.grid;
    notifyListeners();
    _persist();
  }

  /// يضبط النمط صراحةً (قد يكون مفيداً مستقبلاً لإعدادات).
  Future<void> setLayout(SectionsLayout layout) async {
    if (_layout == layout) return;
    _layout = layout;
    notifyListeners();
    _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, _layout.name);
    } catch (_) {
      // نتجاهل — التبديل الجلسي يعمل حتى لو لم نتمكّن من الحفظ.
    }
  }
}
