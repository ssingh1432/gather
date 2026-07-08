import 'package:flutter/material.dart';

/// Gather's brand palette and shared theme configuration.
///
/// Single source of truth for the app's teal brand color so every screen
/// (buttons, FAB, active nav icons, links, selection states) stays visually
/// consistent without each widget hardcoding its own color values.
class AppColors {
  AppColors._();

  /// Primary brand teal — used for the create-post FAB, active states,
  /// primary buttons, and links.
  static const Color brandTeal = Color(0xFF1D9E75);

  /// Darker teal for text/icons placed on top of [brandTeal] backgrounds.
  static const Color onBrandTeal = Color(0xFF04342C);

  /// Light teal tint, useful for selected chips, story rings, and subtle
  /// highlight backgrounds.
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
