import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// يحتفظ محليّاً (على الجهاز فقط) بمعرّفات المحتوى الذي أبلغ عنه المستخدم
/// الحاليّ. الغرض: احترامًا لرأي المُبلِّغ، لا يظهر له ذلك المحتوى بعد الآن
/// — سواءٌ ثبتت مخالفته (وحُذف للجميع خلال 24 ساعة) أو لم تثبت (يبقى
/// للآخرين لكنه يختفي عنه هو).
///
/// التخزين محلّيّ بالكامل (صندوق Hive `hidden_content`) فيعمل للضيوف أيضاً
/// دون حاجة لحساب. القراءة `isHidden` متزامنة (مجموعة في الذاكرة) كي
/// تُستعمل داخل حُرّاس القوائم (`_isPlayableAndCompliant`) بلا تكلفة.
class HiddenContentService extends ChangeNotifier {
  HiddenContentService._();
  static final HiddenContentService instance = HiddenContentService._();

  static const String boxName = 'hidden_content';

  final Set<String> _ids = <String>{};
  Box? _box;

  /// يُستدعى بعد فتح صناديق Hive في الإقلاع. يحمّل المعرّفات إلى الذاكرة.
  /// آمن للاستدعاء أكثر من مرّة.
  Future<void> init() async {
    try {
      _box = Hive.isBoxOpen(boxName) ? Hive.box(boxName) : await Hive.openBox(boxName);
      _ids
        ..clear()
        ..addAll(_box!.keys.map((e) => e.toString()));
    } catch (e) {
      debugPrint('[HiddenContent] init failed: $e');
    }
  }

  /// متزامنة — تُستعمل داخل حُرّاس القوائم لكلّ عنصر.
  bool isHidden(String id) => id.isNotEmpty && _ids.contains(id);

  Set<String> get ids => Set<String>.unmodifiable(_ids);

  /// يُخفي محتوى عن المستخدم الحاليّ ويُبلّغ المستمعين فوراً (تحديث الواجهة)
  /// ثمّ يُثبّته على القرص.
  Future<void> hide(String id) async {
    final key = id.trim();
    if (key.isEmpty || _ids.contains(key)) return;
    _ids.add(key);
    notifyListeners();
    try {
      await _box?.put(key, true);
    } catch (e) {
      debugPrint('[HiddenContent] persist failed: $e');
    }
  }

  /// يمسح القائمة بالكامل — يُستعمل عند حذف الحساب لإزالة كلّ تفضيلات
  /// المستخدم المحليّة.
  Future<void> clearAll() async {
    if (_ids.isEmpty) return;
    _ids.clear();
    notifyListeners();
    try {
      await _box?.clear();
    } catch (_) {}
  }
}
