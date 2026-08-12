import 'package:flutter/foundation.dart';

/// التحكم في استدعاءات الـ HTTP القديمة (Render / nebras-backend).
///
/// - في **التطوير (debug)** لا تُستدعى افتراضيًا حتى لا تعلق التطبيق على timeouts.
/// - في **الإصدار (release/profile)** تبقى مفعّلة كالسابق.
///
/// لتجربة Render أثناء التطوير:
/// `flutter run --dart-define=USE_RENDER_BACKEND=true`
///
/// لتعطيل Render حتى في الإصدار (نادر):
/// `flutter run --dart-define=USE_RENDER_BACKEND=false`
/// أو عند البناء: `--dart-define=USE_RENDER_BACKEND=false`
bool get isLegacyRenderBackendEnabled {
  const v = String.fromEnvironment('USE_RENDER_BACKEND', defaultValue: '');
  if (v == 'true' || v == '1') return true;
  if (v == 'false' || v == '0') return false;
  return !kDebugMode;
}
