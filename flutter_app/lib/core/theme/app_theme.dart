import 'package:flutter/material.dart';

/// Gather's centralized semantic color tokens and shared theme configuration.
///
/// The semantic palette is intentionally defined separately from ThemeData so
/// later visual migrations can map the approved Gather palette into Flutter's
/// ColorScheme without scattering raw HEX values throughout widgets.
class AppColors {
  AppColors._();

  // -------------------------------------------------------------------------
  // Approved Gather semantic palette
  // -------------------------------------------------------------------------

  static const Color primary = Color(0xFF5268A8);
  static const Color primaryStrong = Color(0xFF40558F);
  static const Color primaryContainer = Color(0xFFE8ECF7);

  static const Color secondary = Color(0xFFA8C4E0);
  static const Color secondaryStrong = Color(0xFF6F95B8);
  static const Color secondaryContainer = Color(0xFFEAF3FA);

  static const Color accent = Color(0xFF8274C9);
  static const Color accentStrong = Color(0xFF6557AE);

  static const Color success = Color(0xFF4CAF72);
  static const Color successStrong = Color(0xFF2F7D50);

  static const Color warning = Color(0xFFD9A441);
  static const Color warningStrong = Color(0xFF8A650E);

  static const Color error = Color(0xFFD96B6B);
  static const Color errorStrong = Color(0xFFA94343);

  static const Color background = Color(0xFFF7F9FC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceElevated = Color(0xFFFFFFFF);

  static const Color textPrimary = Color(0xFF20242B);
  static const Color textSecondary = Color(0xFF667085);
  static const Color textDisabled = Color(0xFF98A2B3);

  static const Color border = Color(0xFFD8DEE8);
  static const Color divider = Color(0xFFE5E9F0);
  static const Color icon = Color(0xFF667085);

  // -------------------------------------------------------------------------
  // Existing compatibility aliases
  // -------------------------------------------------------------------------
  // These retain the current public AppColors API during the staged migration.
  // They are deliberately not removed until widget migration is complete.

  /// Legacy primary brand alias. Kept stable until the Light Theme stage.
  static const Color brandTeal = Color(0xFF1D9E75);

  /// Legacy foreground alias for content on the existing teal brand color.
  static const Color onBrandTeal = Color(0xFF04342C);

  /// Legacy light brand alias used by existing selected/highlight states.
  static const Color brandTealLight = Color(0xFF9FE1CB);
}

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.brandTeal,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        centerTitle: false,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.brandTeal,
        foregroundColor: AppColors.onBrandTeal,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brandTeal,
          foregroundColor: AppColors.onBrandTeal,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.brandTeal),
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: AppColors.brandTealLight,
        backgroundColor: colorScheme.surface,
      ),
      tabBarTheme: const TabBarThemeData(
        indicatorColor: AppColors.brandTeal,
        labelColor: AppColors.brandTeal,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.brandTeal, width: 1.5),
        ),
      ),
    );
  }
}
