import 'package:flutter/material.dart';

/// OmniShelf App Theme
/// Dark warehouse aesthetic with green accent — premium & modern.
class AppTheme {
  AppTheme._();

  // ── Palette ─────────────────────────────────────────────────────────────────
  static const Color primary      = Color(0xFF00D4AA);
  static const Color primaryDark  = Color(0xFF00A884);
  static const Color accent       = Color(0xFF7C4DFF);
  static const Color surface      = Color(0xFF1A1D2E);
  static const Color surfaceCard  = Color(0xFF242740);
  static const Color surfaceSheet = Color(0xFF2D3154);
  static const Color background   = Color(0xFF10121F);
  static const Color textPrimary  = Color(0xFFF1F3FF);
  static const Color textSecondary= Color(0xFF9497B3);
  static const Color textHint     = Color(0xFF5A5D7A);
  static const Color divider      = Color(0xFF2E3150);

  static const Color statusSafe     = Color(0xFF00D4AA);
  static const Color statusWarning  = Color(0xFFFFC107);
  static const Color statusCritical = Color(0xFFFF6B35);
  static const Color statusExpired  = Color(0xFFEF4444);

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF00D4AA), Color(0xFF7C4DFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient backgroundGradient = LinearGradient(
    colors: [Color(0xFF10121F), Color(0xFF1A1D2E)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // ── Dark Theme ───────────────────────────────────────────────────────────────
  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary:    Color(0xFF00D4AA),
          secondary:  Color(0xFF7C4DFF),
          surface:    Color(0xFF1A1D2E),
          onPrimary:  Colors.black,
          onSecondary:Colors.white,
          onSurface:  Color(0xFFF1F3FF),
          error:      Color(0xFFEF4444),
        ),
        scaffoldBackgroundColor: background,
        fontFamily: 'Roboto',

        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
          iconTheme: IconThemeData(color: textPrimary),
        ),

        cardTheme: const CardThemeData(
          color: surfaceCard,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
            side: BorderSide(color: divider),
          ),
          margin: EdgeInsets.zero,
        ),

        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.black,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ),

        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ),

        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surfaceCard,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: divider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: primary, width: 2),
          ),
          labelStyle: const TextStyle(color: textSecondary),
          hintStyle: const TextStyle(color: textHint),
        ),

        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: surface,
          selectedItemColor: primary,
          unselectedItemColor: textHint,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
        ),

        dividerTheme: const DividerThemeData(color: divider, thickness: 1, space: 1),

        chipTheme: ChipThemeData(
          backgroundColor: surfaceSheet,
          selectedColor: primary.withValues(alpha: 0.2),
          labelStyle: const TextStyle(color: textPrimary, fontSize: 12),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          side: const BorderSide(color: divider),
        ),

        snackBarTheme: SnackBarThemeData(
          backgroundColor: surfaceCard,
          contentTextStyle: const TextStyle(color: textPrimary),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          behavior: SnackBarBehavior.floating,
        ),

        textTheme: const TextTheme(
          displayLarge:  TextStyle(color: textPrimary, fontWeight: FontWeight.w800),
          displayMedium: TextStyle(color: textPrimary, fontWeight: FontWeight.w700),
          headlineLarge: TextStyle(color: textPrimary, fontWeight: FontWeight.w700),
          headlineMedium:TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
          titleLarge:    TextStyle(color: textPrimary, fontWeight: FontWeight.w700),
          titleMedium:   TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
          titleSmall:    TextStyle(color: textSecondary, fontWeight: FontWeight.w500),
          bodyLarge:     TextStyle(color: textPrimary),
          bodyMedium:    TextStyle(color: textSecondary),
          bodySmall:     TextStyle(color: textHint),
          labelLarge:    TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
          labelMedium:   TextStyle(color: textSecondary),
          labelSmall:    TextStyle(color: textHint),
        ),
      );
}

extension ExpiryStatusColor on Color {
  static Color fromDaysLeft(int days) {
    if (days < 0)  return AppTheme.statusExpired;
    if (days <= 3) return AppTheme.statusCritical;
    if (days <= 7) return AppTheme.statusWarning;
    return AppTheme.statusSafe;
  }
}