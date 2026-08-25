import 'package:flutter/material.dart';

/// Gather's centralized semantic color tokens and shared theme configuration.
///
/// The semantic palette is intentionally defined separately from ThemeData so
/// visual styling can use semantic roles without scattering raw HEX values
/// throughout widgets.
class AppColors {
  AppColors._();

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

  static const Color darkBackground = Color(0xFF151820);
  static const Color darkSurface = Color(0xFF1D212B);
  static const Color darkSurfaceElevated = Color(0xFF252A35);
  static const Color darkPrimary = Color(0xFF91A5E0);
  static const Color darkPrimaryStrong = Color(0xFFAFC0F0);
  static const Color darkPrimaryContainer = Color(0xFF303A58);
  static const Color darkSecondary = Color(0xFFA8C4E0);
  static const Color darkSecondaryStrong = Color(0xFFC1D8EE);
  static const Color darkSecondaryContainer = Color(0xFF2B3A4A);
  static const Color darkAccent = Color(0xFFA59BE0);
  static const Color darkAccentStrong = Color(0xFFC0B9EF);
  static const Color darkSuccess = Color(0xFF70C990);
  static const Color darkSuccessStrong = Color(0xFF9BE0B4);
  static const Color darkWarning = Color(0xFFE3B85E);
  static const Color darkWarningStrong = Color(0xFFF0CE83);
  static const Color darkError = Color(0xFFE58A8A);
  static const Color darkErrorStrong = Color(0xFFF0AAAA);
  static const Color darkTextPrimary = Color(0xFFF1F3F7);
  static const Color darkTextSecondary = Color(0xFFB5BDCA);
  static const Color darkTextDisabled = Color(0xFF7E8795);
  static const Color darkBorder = Color(0xFF3A414E);
  static const Color darkDivider = Color(0xFF303641);
  static const Color darkIcon = Color(0xFFB5BDCA);

  // Compatibility aliases retained during the staged migration.
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primaryStrong,
          disabledForegroundColor: AppColors.textDisabled,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 1,
        shadowColor: AppColors.primary.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: EdgeInsets.zero,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: const TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w600),
        contentTextStyle: const TextStyle(color: AppColors.textSecondary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.secondaryContainer,
        selectedColor: AppColors.primaryContainer,
        disabledColor: AppColors.divider,
        side: const BorderSide(color: AppColors.border),
        labelStyle: const TextStyle(color: AppColors.textPrimary),
        secondaryLabelStyle: const TextStyle(color: AppColors.textSecondary),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: AppColors.secondaryContainer,
        circularTrackColor: AppColors.divider,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.textPrimary,
        contentTextStyle: const TextStyle(color: AppColors.surface),
        actionTextColor: AppColors.secondary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: AppColors.secondaryContainer,
        backgroundColor: AppColors.surface,
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>((states) {
          if (states.contains(WidgetState.selected)) return const IconThemeData(color: AppColors.primaryStrong);
          return const IconThemeData(color: AppColors.icon);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((states) {
          if (states.contains(WidgetState.selected)) return const TextStyle(color: AppColors.primaryStrong);
          return const TextStyle(color: AppColors.textSecondary);
        }),
      ),
      tabBarTheme: const TabBarThemeData(
        indicatorColor: AppColors.primary,
        labelColor: AppColors.primaryStrong,
        unselectedLabelColor: AppColors.textSecondary,
      ),
      dividerTheme: const DividerThemeData(color: AppColors.divider, thickness: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        hintStyle: const TextStyle(color: AppColors.textSecondary),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.errorStrong)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.errorStrong, width: 1.5)),
      ),
    );
  }

  static ThemeData get dark {
    final colorScheme = ColorScheme.dark(
      primary: AppColors.darkPrimary,
      onPrimary: AppColors.darkBackground,
      primaryContainer: AppColors.darkPrimaryContainer,
      onPrimaryContainer: AppColors.darkPrimaryStrong,
      secondary: AppColors.darkSecondary,
      onSecondary: AppColors.darkBackground,
      secondaryContainer: AppColors.darkSecondaryContainer,
      onSecondaryContainer: AppColors.darkTextPrimary,
      tertiary: AppColors.darkAccent,
      onTertiary: AppColors.darkBackground,
      tertiaryContainer: AppColors.darkPrimaryContainer,
      onTertiaryContainer: AppColors.darkAccentStrong,
      error: AppColors.darkError,
      onError: AppColors.darkBackground,
      errorContainer: const Color(0xFF482B30),
      onErrorContainer: AppColors.darkErrorStrong,
      surface: AppColors.darkSurface,
      onSurface: AppColors.darkTextPrimary,
      surfaceContainerHighest: AppColors.darkDivider,
      onSurfaceVariant: AppColors.darkTextSecondary,
      outline: AppColors.darkBorder,
      outlineVariant: AppColors.darkDivider,
      inverseSurface: AppColors.darkTextPrimary,
      onInverseSurface: AppColors.darkBackground,
      inversePrimary: AppColors.primary,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.darkBackground,
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: AppColors.darkTextPrimary),
        bodyMedium: TextStyle(color: AppColors.darkTextPrimary),
        bodySmall: TextStyle(color: AppColors.darkTextSecondary),
      ),
      appBarTheme: const AppBarTheme(backgroundColor: AppColors.darkSurface, foregroundColor: AppColors.darkTextPrimary, elevation: 0, centerTitle: false),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(backgroundColor: AppColors.darkPrimary, foregroundColor: AppColors.darkBackground),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.darkPrimary,
          foregroundColor: AppColors.darkBackground,
          disabledBackgroundColor: AppColors.darkDivider,
          disabledForegroundColor: AppColors.darkTextDisabled,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: AppColors.darkPrimaryStrong, disabledForegroundColor: AppColors.darkTextDisabled)),
      cardTheme: CardThemeData(
        color: AppColors.darkSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: EdgeInsets.zero,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.darkSurfaceElevated,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: const TextStyle(color: AppColors.darkTextPrimary, fontSize: 20, fontWeight: FontWeight.w600),
        contentTextStyle: const TextStyle(color: AppColors.darkTextSecondary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.darkSurface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: AppColors.darkSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.darkSecondaryContainer,
        selectedColor: AppColors.darkPrimaryContainer,
        disabledColor: AppColors.darkDivider,
        side: const BorderSide(color: AppColors.darkBorder),
        labelStyle: const TextStyle(color: AppColors.darkTextPrimary),
        secondaryLabelStyle: const TextStyle(color: AppColors.darkTextSecondary),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.darkPrimary,
        linearTrackColor: AppColors.darkSecondaryContainer,
        circularTrackColor: AppColors.darkDivider,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.darkSurfaceElevated,
        contentTextStyle: const TextStyle(color: AppColors.darkTextPrimary),
        actionTextColor: AppColors.darkSecondaryStrong,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: AppColors.darkSecondaryContainer,
        backgroundColor: AppColors.darkSurface,
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>((states) {
          if (states.contains(WidgetState.selected)) return const IconThemeData(color: AppColors.darkPrimaryStrong);
          return const IconThemeData(color: AppColors.darkIcon);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((states) {
          if (states.contains(WidgetState.selected)) return const TextStyle(color: AppColors.darkPrimaryStrong);
          return const TextStyle(color: AppColors.darkTextSecondary);
        }),
      ),
      tabBarTheme: const TabBarThemeData(indicatorColor: AppColors.darkPrimary, labelColor: AppColors.darkPrimaryStrong, unselectedLabelColor: AppColors.darkTextSecondary),
      dividerTheme: const DividerThemeData(color: AppColors.darkDivider, thickness: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkSurface,
        hintStyle: const TextStyle(color: AppColors.darkTextSecondary),
        labelStyle: const TextStyle(color: AppColors.darkTextSecondary),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.darkBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.darkBorder)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.darkPrimary, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.darkErrorStrong)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.darkErrorStrong, width: 1.5)),
      ),
    );
  }
}
