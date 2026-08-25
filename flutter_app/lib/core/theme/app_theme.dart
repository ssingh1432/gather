import 'package:flutter/material.dart';

/// Gather's centralized semantic color tokens and shared theme configuration.
///
/// The semantic palette is intentionally defined separately from ThemeData so
/// visual styling can use semantic roles without scattering raw HEX values
/// throughout widgets.
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
  // They will be removed only after dependent widget migrations are complete.

  static const Color brandTeal = Color(0xFF1D9E75);
  static const Color onBrandTeal = Color(0xFF04342C);
  static const Color brandTealLight = Color(0xFF9FE1CB);
}

class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final colorScheme = ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: AppColors.surface,
      primaryContainer: AppColors.primaryContainer,
      onPrimaryContainer: AppColors.primaryStrong,
      secondary: AppColors.secondary,
      onSecondary: AppColors.textPrimary,
      secondaryContainer: AppColors.secondaryContainer,
      onSecondaryContainer: AppColors.textPrimary,
      tertiary: AppColors.accent,
      onTertiary: AppColors.surface,
      tertiaryContainer: AppColors.primaryContainer,
      onTertiaryContainer: AppColors.accentStrong,
      error: AppColors.errorStrong,
      onError: AppColors.surface,
      errorContainer: AppColors.error.withValues(alpha: 0.14),
      onErrorContainer: AppColors.errorStrong,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      surfaceContainerHighest: AppColors.divider,
      onSurfaceVariant: AppColors.textSecondary,
      outline: AppColors.border,
      outlineVariant: AppColors.divider,
      inverseSurface: AppColors.textPrimary,
      onInverseSurface: AppColors.surface,
      inversePrimary: AppColors.primaryContainer,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: AppColors.textPrimary),
        bodyMedium: TextStyle(color: AppColors.textPrimary),
        bodySmall: TextStyle(color: AppColors.textSecondary),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: false,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.surface,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.surface,
          disabledBackgroundColor: AppColors.divider,
          disabledForegroundColor: AppColors.textDisabled,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primaryStrong,
          disabledForegroundColor: AppColors.textDisabled,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: AppColors.secondaryContainer,
        backgroundColor: AppColors.surface,
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColors.primaryStrong);
          }
          return const IconThemeData(color: AppColors.icon);
        }),
        labelTextStyle:
            WidgetStateProperty.resolveWith<TextStyle?>((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(color: AppColors.primaryStrong);
          }
          return const TextStyle(color: AppColors.textSecondary);
        }),
      ),
      tabBarTheme: const TabBarThemeData(
        indicatorColor: AppColors.primary,
        labelColor: AppColors.primaryStrong,
        unselectedLabelColor: AppColors.textSecondary,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        hintStyle: const TextStyle(color: AppColors.textSecondary),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.errorStrong),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.errorStrong, width: 1.5),
        ),
      ),
    );
  }
}
