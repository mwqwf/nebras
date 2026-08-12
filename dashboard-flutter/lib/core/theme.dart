import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ألوان لوحة نبراس (مستخرجة من `app.css`): خلفية داكنة، أخضر زمرّدي رئيسي،
/// كهرماني ثانوي.
class NebrasColors {
  NebrasColors._();

  static const Color bg = Color(0xFF0D0D0F);
  static const Color surface = Color(0xFF1A1A1E);
  static const Color surfaceAlt = Color(0xFF27272A);
  static const Color sidebarBg = Color(0xFF0D0D0F);
  static const Color sidebarHover = Color(0xFF1A1A1E);
  static const Color sidebarActive = Color(0xFF0F2A1E);
  static const Color border = Color(0xFF27272A);

  static const Color emerald = Color(0xFF10B981);
  static const Color emeraldDark = Color(0xFF059669);
  static const Color amber = Color(0xFFF59E0B);
  static const Color amberLight = Color(0xFFFBBF24);
  static const Color rose = Color(0xFFF43F5E);
  static const Color textPrimary = Color(0xFFFAFAFA);
  static const Color textMuted = Color(0xFFA1A1AA);
}

ThemeData buildNebrasTheme() {
  const scheme = ColorScheme.dark(
    primary: NebrasColors.emerald,
    onPrimary: Colors.black,
    secondary: NebrasColors.amber,
    onSecondary: Colors.black,
    surface: NebrasColors.surface,
    onSurface: NebrasColors.textPrimary,
    error: NebrasColors.rose,
  );

  // الخط العربي IBM Plex Sans Arabic — يُجلب مرّة ويُخزَّن محليّاً.
  final baseText = ThemeData(brightness: Brightness.dark).textTheme;
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: NebrasColors.bg,
    textTheme: GoogleFonts.ibmPlexSansArabicTextTheme(baseText),
    fontFamily: GoogleFonts.ibmPlexSansArabic().fontFamily,
    appBarTheme: const AppBarTheme(
      backgroundColor: NebrasColors.surface,
      foregroundColor: NebrasColors.textPrimary,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: NebrasColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: NebrasColors.border),
      ),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: NebrasColors.bg,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: NebrasColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: NebrasColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: NebrasColors.emerald, width: 1.5),
      ),
      isDense: true,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: NebrasColors.emeraldDark,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: NebrasColors.surfaceAlt,
        foregroundColor: NebrasColors.textPrimary,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    dividerTheme: const DividerThemeData(color: NebrasColors.border, space: 1),
    chipTheme: const ChipThemeData(
      backgroundColor: NebrasColors.surfaceAlt,
      side: BorderSide(color: NebrasColors.border),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: NebrasColors.surfaceAlt,
      contentTextStyle: TextStyle(color: NebrasColors.textPrimary),
    ),
  );
}
