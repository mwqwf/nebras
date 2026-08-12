import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// يقنّن إظهار رسالة دعوة الضيف لإنشاء حساب: مرّتان إلى ثلاث مرّات يوميّاً
/// بحدٍّ أدنى من الفاصل الزمنيّ بين الرسائل، حتى لا تتحوّل إلى إزعاج.
///
/// **محليّ فقط** (SharedPreferences) — لا علاقة له بـ Firebase. يخصّ الضيف
/// (مستخدم بلا حساب حقيقيّ) وحده.
class GuestAccountPromptService {
  GuestAccountPromptService._();

  static final GuestAccountPromptService instance =
      GuestAccountPromptService._();

  static const _kShownTimes = 'guest_prompt_shown_ms_v1';
  static const int _maxPerDay = 3;
  static const Duration _minGap = Duration(hours: 3);

  SharedPreferences? _prefs;

  Future<void> _init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  List<int> _todayTimes() {
    final raw = _prefs?.getString(_kShownTimes);
    if (raw == null || raw.isEmpty) return <int>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <int>[];
      final now = DateTime.now();
      return decoded
          .whereType<num>()
          .map((e) => e.toInt())
          .where((ms) {
            final dt = DateTime.fromMillisecondsSinceEpoch(ms);
            return dt.year == now.year &&
                dt.month == now.month &&
                dt.day == now.day;
          })
          .toList();
    } catch (_) {
      return <int>[];
    }
  }

  /// هل نعرض الرسالة الآن؟ يُحترم الحدّ اليوميّ والفاصل الأدنى.
  Future<bool> shouldShow() async {
    await _init();
    final times = _todayTimes();
    if (times.length >= _maxPerDay) return false;
    if (times.isNotEmpty) {
      final last = times.reduce((a, b) => a > b ? a : b);
      final since = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(last),
      );
      if (since < _minGap) return false;
    }
    return true;
  }

  /// يسجّل أنّ الرسالة عُرضت الآن (يُستدعى بعد العرض الفعليّ فقط).
  Future<void> recordShown() async {
    await _init();
    final times = _todayTimes()..add(DateTime.now().millisecondsSinceEpoch);
    await _prefs!.setString(_kShownTimes, jsonEncode(times));
  }
}
