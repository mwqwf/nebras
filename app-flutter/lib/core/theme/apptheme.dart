import 'package:flutter/material.dart';
import 'package:nebras_mobile_app/core/theme/color_manager.dart';

/// سمة التطبيق — لوحة ألوان احترافية متناسقة للوضعين الفاتح والداكن.
///
/// المبدأ: نُعرّف `ColorScheme` كاملاً + سمات للمكوّنات (AppBar, Card,
/// Input, Buttons, BottomNav, Divider, Chip…) حتى ترث كلّ شاشات التطبيق
/// مظهراً موحَّداً تلقائياً دون تعديل أيّ منطق ميزة. لا صور ولا أنماط —
/// ألوان وتباعد وحوافّ منسجمة فقط.
class AppTheme {
  // نصف قطر موحَّد للحوافّ عبر التطبيق.
  static const double _radius = 14;

  // ── السمة الفاتحة ───────────────────────────────────────────
  static final ThemeData lightTheme = _build(
    brightness: Brightness.light,
    scaffold: ColorsManager.lightScaffold,
    primary: ColorsManager.primary,
    onPrimary: Colors.white,
    secondary: ColorsManager.secondary,
    surface: ColorsManager.lightSurface,
    surfaceVariant: ColorsManager.lightSurfaceVariant,
    onSurface: ColorsManager.textPrimary,
    onSurfaceMuted: ColorsManager.textSecondary,
    outline: ColorsManager.lightOutline,
  );

  // ── السمة الداكنة ───────────────────────────────────────────
  static final ThemeData darkTheme = _build(
    brightness: Brightness.dark,
    scaffold: ColorsManager.darkBackground,
    primary: ColorsManager.primaryOnDark,
    onPrimary: Colors.white,
    secondary: ColorsManager.accent,
    surface: ColorsManager.darkSurface,
    surfaceVariant: ColorsManager.darkSurfaceVariant,
    onSurface: ColorsManager.darkOnSurface,
    onSurfaceMuted: ColorsManager.darkOnSurfaceMuted,
    outline: ColorsManager.darkOutline,
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color scaffold,
    required Color primary,
    required Color onPrimary,
    required Color secondary,
    required Color surface,
    required Color surfaceVariant,
    required Color onSurface,
    required Color onSurfaceMuted,
    required Color outline,
  }) {
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: primary.withValues(alpha: 0.12),
      onPrimaryContainer: primary,
      secondary: secondary,
      onSecondary: Colors.white,
      tertiary: ColorsManager.accent,
      onTertiary: Colors.white,
      error: ColorsManager.error,
      onError: Colors.white,
      surface: surface,
      onSurface: onSurface,
      surfaceContainerHighest: surfaceVariant,
      onSurfaceVariant: onSurfaceMuted,
      outline: outline,
      outlineVariant: outline,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffold,
      canvasColor: surface,
      cardColor: surface,
      dividerColor: outline,
      hintColor: onSurfaceMuted,
      splashFactory: InkSparkle.splashFactory,

      appBarTheme: AppBarTheme(
        backgroundColor: scaffold,
        foregroundColor: onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        iconTheme: IconThemeData(color: onSurface),
        titleTextStyle: TextStyle(
          color: onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),

      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius),
          side: BorderSide(color: outline, width: 1),
        ),
      ),

      dividerTheme: DividerThemeData(
        color: outline,
        thickness: 1,
        space: 1,
      ),

      iconTheme: IconThemeData(color: onSurface),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceVariant,
        hintStyle: TextStyle(color: onSurfaceMuted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius),
          borderSide: BorderSide(color: outline, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius),
          borderSide: BorderSide(color: primary, width: 1.5),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: primary),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: outline, width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: onSurface),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: surfaceVariant,
        side: BorderSide(color: outline, width: 1),
        labelStyle: TextStyle(color: onSurface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: primary,
        unselectedItemColor: onSurfaceMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        showUnselectedLabels: true,
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: brightness == Brightness.dark
            ? surfaceVariant
            : ColorsManager.primaryDark,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(color: primary),

      drawerTheme: DrawerThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
      ),

      listTileTheme: ListTileThemeData(
        iconColor: onSurfaceMuted,
        textColor: onSurface,
      ),
    );
  }
}
