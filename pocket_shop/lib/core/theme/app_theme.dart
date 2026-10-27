import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Brand
  static const Color primaryCyan = Color(0xFF00BCD4);
  static const Color darkCyan = Color(0xFF0097A7);
  static const Color accentOrange = Color(0xFFF97316);
  static const Color textPrimary = Color(0xFF1A1A2E); // "ink"
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color placeholder = Color(0xFF9CA3AF);

  // Surfaces — neutral, never hue-tinted.
  static const Color surfaceWhite = Color(0xFFF7F8FA); // page background
  static const Color cardWhite = Colors.white;
  static const Color softSurface = Color(0xFFF1F3F5); // inset panels
  static const Color divider = Color(0xFFECEEF2); // hairlines + card borders
  static const Color strongLine = Color(0xFFD9DCE1); // outlined controls

  // Status
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFD97706);
  static const Color error = Color(0xFFDC2626);

  // Legacy names still referenced by older screens.
  static const Color lightCyan = Color(0xFFE0F7FA);
  static const Color orangeTint = Color(0xFFFFF1E6);
  static const Color accentBlue = Color(0xFF2563EB);
  static const Color accentPurple = Color(0xFF7C3AED);

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

  static ThemeData get lightTheme {
    final base = GoogleFonts.interTextTheme();
    final r14 = BorderRadius.circular(14);

    OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: r14,
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: surfaceWhite,
      // Material 3 derives its container/surface tones from the seed, which
      // washes dialogs, sheets and menus in pale cyan. Pin them to neutrals.
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryCyan,
        brightness: Brightness.light,
      ).copyWith(
        primary: primaryCyan,
        onPrimary: Colors.white,
        primaryContainer: primaryCyan,
        onPrimaryContainer: Colors.white,
        secondary: accentOrange,
        onSecondary: Colors.white,
        secondaryContainer: textPrimary,
        onSecondaryContainer: Colors.white,
        tertiary: darkCyan,
        onTertiary: Colors.white,
        surface: Colors.white,
        onSurface: textPrimary,
        onSurfaceVariant: textSecondary,
        surfaceTint: Colors.transparent,
        surfaceContainerLowest: Colors.white,
        surfaceContainerLow: const Color(0xFFFAFBFC),
        surfaceContainer: const Color(0xFFF5F6F8),
        surfaceContainerHigh: softSurface,
        surfaceContainerHighest: divider,
        outline: strongLine,
        outlineVariant: divider,
        error: error,
        onError: Colors.white,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: primaryCyan,
        selectionHandleColor: primaryCyan,
        selectionColor: primaryCyan.withValues(alpha: 0.25),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surfaceWhite,
        foregroundColor: textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.sora(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: const IconThemeData(color: textPrimary),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        color: cardWhite,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: divider),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryCyan,
          foregroundColor: Colors.white,
          disabledBackgroundColor: divider,
          disabledForegroundColor: placeholder,
          shape: RoundedRectangleBorder(borderRadius: r14),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryCyan,
          foregroundColor: Colors.white,
          disabledBackgroundColor: divider,
          disabledForegroundColor: placeholder,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: r14),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          backgroundColor: Colors.white,
          side: const BorderSide(color: strongLine),
          shape: RoundedRectangleBorder(borderRadius: r14),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: darkCyan,
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accentOrange,
        foregroundColor: Colors.white,
        elevation: 2,
        highlightElevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        extendedTextStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? textPrimary : Colors.white,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Colors.white : textPrimary,
          ),
          side: const WidgetStatePropertyAll(BorderSide(color: strongLine)),
          textStyle: WidgetStatePropertyAll(
            GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: cardWhite,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 66,
        indicatorColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return GoogleFonts.inter(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: selected ? primaryCyan : textSecondary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected) ? primaryCyan : textSecondary,
            size: 24,
          );
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        hintStyle: GoogleFonts.inter(fontSize: 14.5, color: placeholder),
        labelStyle: GoogleFonts.inter(fontSize: 14, color: textSecondary),
        floatingLabelStyle: GoogleFonts.inter(
          fontSize: 14,
          color: darkCyan,
          fontWeight: FontWeight.w600,
        ),
        prefixIconColor: textSecondary,
        suffixIconColor: textSecondary,
        border: inputBorder(divider),
        enabledBorder: inputBorder(divider),
        disabledBorder: inputBorder(divider),
        focusedBorder: inputBorder(primaryCyan, 1.5),
        errorBorder: inputBorder(error, 1.2),
        focusedErrorBorder: inputBorder(error, 1.5),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        selectedColor: primaryCyan,
        disabledColor: softSurface,
        surfaceTintColor: Colors.transparent,
        side: const BorderSide(color: divider),
        shape: const StadiumBorder(),
        showCheckmark: false,
        checkmarkColor: Colors.white,
        labelStyle: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: WidgetStateColor.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Colors.white : textPrimary,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? success : strongLine,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? primaryCyan : Colors.transparent,
        ),
        checkColor: const WidgetStatePropertyAll(Colors.white),
        side: const BorderSide(color: strongLine, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? primaryCyan : strongLine,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: primaryCyan,
        linearTrackColor: divider,
        circularTrackColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: GoogleFonts.sora(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        contentTextStyle: GoogleFonts.inter(fontSize: 14, color: textSecondary, height: 1.45),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        modalBackgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: strongLine,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: divider),
        ),
        textStyle: GoogleFonts.inter(fontSize: 14, color: textPrimary),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: textPrimary,
        unselectedLabelColor: textSecondary,
        indicatorColor: primaryCyan,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: divider,
        labelStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700),
        unselectedLabelStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: textSecondary,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        subtitleTextStyle: GoogleFonts.inter(fontSize: 12.5, color: textSecondary),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: textPrimary,
        contentTextStyle: GoogleFonts.inter(fontSize: 14, color: Colors.white),
        actionTextColor: primaryCyan,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dividerTheme: const DividerThemeData(color: divider, thickness: 1, space: 1),
      // Derive body styles from the Inter base; a bare TextStyle here would
      // drop the family and fall back to Roboto.
      textTheme: base.copyWith(
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
        bodyLarge: base.bodyLarge!.copyWith(fontSize: 15, color: textPrimary),
        bodyMedium: base.bodyMedium!.copyWith(fontSize: 14, color: textPrimary),
        bodySmall: base.bodySmall!.copyWith(fontSize: 12, color: textSecondary),
        labelLarge: base.labelLarge!.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }

  // Legacy text styles (older screens).
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
