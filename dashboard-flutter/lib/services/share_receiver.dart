import 'package:flutter/services.dart';

/// حمولة «مشاركة إلى نبراس»: ملفّ (مسار منسوخ إلى cache) أو نصّ/رابط.
class SharedPayload {
  const SharedPayload({this.path, this.text});
  final String? path;
  final String? text;

  bool get isEmpty => (path == null || path!.isEmpty) && (text == null || text!.isEmpty);

  static SharedPayload? fromMap(dynamic m) {
    if (m is! Map) return null;
    final p = SharedPayload(
      path: m['path'] as String?,
      text: m['text'] as String?,
    );
    return p.isEmpty ? null : p;
  }
}

/// جسر MethodChannel مع MainActivity — بديل أصلي خفيف عن حزمة
/// receive_sharing_intent (غير المتوافقة مع Gradle الحديث).
class ShareReceiver {
  ShareReceiver._();

  static const _channel = MethodChannel('nebras/share');
  static void Function(SharedPayload payload)? _onShare;
  static bool _inited = false;

  /// [onShare] يُستدعى لكلّ مشاركة: الأولى عند الإقلاع (إن وُجدت) وكلّ
  /// مشاركة لاحقة والتطبيق مفتوح.
  static Future<void> init(void Function(SharedPayload) onShare) async {
    _onShare = onShare;
    if (_inited) return;
    _inited = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onShare') {
        final p = SharedPayload.fromMap(call.arguments);
        if (p != null) _onShare?.call(p);
      }
    });
    try {
      final initial = await _channel.invokeMethod<dynamic>('getInitialShare');
      final p = SharedPayload.fromMap(initial);
      if (p != null) _onShare?.call(p);
    } catch (_) {}
  }
}
