import 'package:flutter/material.dart';

class ColorsManager {
  // 🔵 Primary Colors
  static const Color primary = Color(0xFF1E3A8A); // Deep Indigo
  static const Color primaryLight = Color(0xFF3B82F6);
  static const Color primaryDark = Color(0xFF1E293B);
  static const Color primaryblue = Colors.blue; // Bright Blue

  // 🟢 Secondary / Accent
  static const Color secondary = Color(0xFF0F766E); // Muted Teal
  static const Color accent = Color(0xFF10B981); // Emerald Accent

  // ⚪ Backgrounds
  static const Color background = Colors.white; // Off White
  static const Color whiteColor = Color(0xFFFFFFFF);
  static const Color greycolor = Color(0xFF64748B);
  static const Color blackcolor = Color(0xFF000000);
  static const Color darkBackground = Color(0xFF121212);
  static const Color transparent = Colors.transparent;
  // Dark Navy

  // ⚫ Text Colors
  static const Color textPrimary = Color(0xFF0F172A); // Near Black
  static const Color textSecondary = Color(0xFF475569);
  static const Color textMuted = Color(0xFF94A3B8);
  static const Color textOnPrimary = Color(0xFFFFFFFF);
  static const Color white70 = Colors.white70;

  // 🔴 Status Colors
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFDC2626);
  static const Color info = Color(0xFF2563EB);

  // 🧱 Borders & Dividers
  static const Color border = Color(0xFFE2E8F0);
  static const Color divider = Color(0xFFCBD5E1);
  //neutrals

  static const Color textfieldcolor = Color(0xFFFDFDFF);
  static const Color textfieldbordercolor = Color(0xFFEDEDED);
  static const Color textlightgrey = Color(0xFFC2C2C2);

  // 🌫 Overlays
  static const Color overlay = Color(0x99000000);

  // 🔘 Disabled
  static const Color disabled = Color(0xFFCBD5E1);

  // ──────────────────────────────────────────────────────────────
  // 🎨 رموز سطح/خلفية احترافية للسمة (إضافيّة — لا تُزيل ما سبق)
  // تُستعمل في apptheme.dart لبناء ColorScheme متناسق للوضعين.
  // ──────────────────────────────────────────────────────────────
  // فاتح
  static const Color lightScaffold = Color(0xFFF5F6F9); // أبيض مائل للرمادي
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceVariant = Color(0xFFEDF0F5);
  static const Color lightOutline = Color(0xFFE2E6EC);

  // داكن (نِيلِيّ عميق راقٍ بدل الأسود الصريح)
  static const Color darkSurface = Color(0xFF181B21);
  static const Color darkSurfaceVariant = Color(0xFF232830);
  static const Color darkOutline = Color(0xFF323844);
  static const Color darkOnSurface = Color(0xFFE7EAF0);
  static const Color darkOnSurfaceMuted = Color(0xFF9AA3B2);

  // لون أساسيّ مُفتَّح للوضع الداكن (تباين أفضل من النِّيليّ العميق)
  static const Color primaryOnDark = Color(0xFF6691F4);
}
