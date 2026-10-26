import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Colors - User Specified
  static const Color primaryCyan = Color(0xFF00BCD4);
  static const Color darkCyan = Color(0xFF0097A7);
  static const Color lightCyan = Color(0xFFE0F7FA);
  static const Color accentBlue = Color(0xFF2563EB);
  static const Color accentPurple = Color(0xFF7C3AED);
  static const Color surfaceWhite = Color(0xFFFAFAFA);
  static const Color softSurface = Color(0xFFF2F7FF);
  static const Color cardWhite = Colors.white;
  static const Color textPrimary = Color(0xFF1A1A2E);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color divider = Color(0xFFE5E7EB);
  static const Color error = Color(0xFFE53E3E);
  static const Color success = Color(0xFF38A169);
  static const Color warning = Color(0xFFD69E2E);
  static const Color accentOrange = Color(0xFFF97316);
  static const Color orangeTint = Color(0xFFFFF1E6);

  // Display face for headings/numbers; body face for everything else.
  // Centralizing these two here is the fix for font sizes/weights having
  // drifted screen-to-screen — new/rewritten screens should pull from the
  // type scale below rather than writing their own TextStyle(fontSize: …).
  static TextStyle display({
    double fontSize = 20,
    FontWeight fontWeight = FontWeight.w800,
    Color color = textPrimary,
    double? letterSpacing,
    double? height,
  }) =>
      GoogleFonts.sora(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
      );

  static TextStyle body({
    double fontSize = 14,
    FontWeight fontWeight = FontWeight.w400,
    Color color = textPrimary,
    double? height,
  }) =>
      GoogleFonts.inter(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: height,
      );

  // Type scale — pick from this instead of inventing a new size.
  static TextStyle get scaleDisplay => display(fontSize: 26, height: 1.15);
  static TextStyle get scaleHeading => display(fontSize: 20);
  static TextStyle get scaleTitle => display(fontSize: 16);
  static TextStyle get scaleBodyLarge => body(fontSize: 15, fontWeight: FontWeight.w500);
  static TextStyle get scaleBody => body(fontSize: 14, fontWeight: FontWeight.w500);
  static TextStyle get scaleCaption => body(fontSize: 12, color: textSecondary, fontWeight: FontWeight.w500);
  static TextStyle get scaleLabel =>
      body(fontSize: 11, color: textSecondary, fontWeight: FontWeight.w700);

  // Light Theme
  static ThemeData get lightTheme {
    final baseTextTheme = GoogleFonts.interTextTheme();
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: surfaceWhite,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryCyan,
        brightness: Brightness.light,
        primary: primaryCyan,
        secondary: accentBlue,
        tertiary: accentPurple,
        surface: surfaceWhite,
        onSurface: textPrimary,
        error: error,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: softSurface,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.sora(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: const IconThemeData(color: textPrimary),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        color: cardWhite,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: divider.withValues(alpha: 0.5)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryCyan,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryCyan,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: darkCyan,
          side: const BorderSide(color: darkCyan),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: cardWhite,
        surfaceTintColor: Colors.transparent,
        height: 72,
        indicatorColor: lightCyan.withValues(alpha: 0.9),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: accentBlue,
            );
          }
          return const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: textSecondary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: accentBlue, size: 24);
          }
          return const IconThemeData(color: textSecondary, size: 24);
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: softSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: divider.withAlpha(128)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: divider.withAlpha(128)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primaryCyan.withAlpha(76)),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: error),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: textPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: softSurface,
        selectedColor: lightCyan,
        side: BorderSide(color: divider.withValues(alpha: 0.8)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        labelStyle: const TextStyle(
          color: textPrimary,
          fontWeight: FontWeight.w600,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      ),
      dividerTheme: const DividerThemeData(color: divider, thickness: 1),
      textTheme: baseTextTheme.copyWith(
        headlineSmall: GoogleFonts.sora(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          color: textPrimary,
        ),
        titleLarge: GoogleFonts.sora(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        titleMedium: GoogleFonts.sora(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        bodyLarge: const TextStyle(
          fontSize: 15,
          color: textPrimary,
        ),
        bodyMedium: const TextStyle(
          fontSize: 14,
          color: textPrimary,
        ),
        bodySmall: const TextStyle(
          fontSize: 12,
          color: textSecondary,
        ),
      ),
    );
  }

  // Text Styles
  static const TextStyle headline1 = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.bold,
    color: textPrimary,
  );

  static const TextStyle headline2 = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );

  static const TextStyle headline3 = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );

  static const TextStyle bodyLarge = TextStyle(fontSize: 16, color: textPrimary);

  static const TextStyle bodyMedium = TextStyle(fontSize: 14, color: textPrimary);

  static const TextStyle bodySmall = TextStyle(fontSize: 12, color: textSecondary);
}
