import 'package:flutter/material.dart';

/// WCAG 2.x contrast ratio between two opaque colors (1.0 – 21.0).
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// Page transition that shows the destination immediately (reduce-motion).
class InstantPageTransitionsBuilder extends PageTransitionsBuilder {
  const InstantPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      child;
}

/// Derives accessibility variants from the brand themes without changing the
/// brand palette used for the default experience.
class AccessibleTheme {
  AccessibleTheme._();

  // High-contrast palettes: >= 7:1 (WCAG AAA) for text on surface.
  static const Color hcLightSurface = Color(0xFFFFFFFF);
  static const Color hcLightText = Color(0xFF000000);
  static const Color hcLightPrimary = Color(0xFF1B2330);
  static const Color hcLightError = Color(0xFF8A0000);
  static const Color hcLightOutline = Color(0xFF000000);

  static const Color hcDarkSurface = Color(0xFF000000);
  static const Color hcDarkText = Color(0xFFFFFFFF);
  static const Color hcDarkPrimary = Color(0xFFE6EDF7);
  static const Color hcDarkError = Color(0xFFFFB3B3);
  static const Color hcDarkOutline = Color(0xFFFFFFFF);

  static ThemeData highContrast(ThemeData base) {
    final dark = base.brightness == Brightness.dark;
    final surface = dark ? hcDarkSurface : hcLightSurface;
    final text = dark ? hcDarkText : hcLightText;
    final primary = dark ? hcDarkPrimary : hcLightPrimary;
    final error = dark ? hcDarkError : hcLightError;
    final outline = dark ? hcDarkOutline : hcLightOutline;

    final scheme = base.colorScheme.copyWith(
      primary: primary,
      onPrimary: surface,
      surface: surface,
      onSurface: text,
      onSurfaceVariant: text,
      outline: outline,
      outlineVariant: outline,
      error: error,
      onError: surface,
    );

    final outlinedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: outline, width: 1.5),
    );

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: surface,
      canvasColor: surface,
      cardColor: surface,
      dividerColor: outline,
      focusColor: primary.withValues(alpha: 0.28),
      iconTheme: IconThemeData(color: text),
      textTheme: base.textTheme.apply(bodyColor: text, displayColor: text),
      dividerTheme: DividerThemeData(color: outline, thickness: 1),
      cardTheme: base.cardTheme.copyWith(
        color: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: outline, width: 1),
        ),
      ),
      appBarTheme: base.appBarTheme.copyWith(backgroundColor: surface, foregroundColor: text),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        border: outlinedBorder,
        enabledBorder: outlinedBorder,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: outline, width: 3),
        ),
      ),
    );
  }

  /// Removes animated page transitions on every platform.
  static ThemeData reduceMotion(ThemeData base) => base.copyWith(
        pageTransitionsTheme: PageTransitionsTheme(
          builders: <TargetPlatform, PageTransitionsBuilder>{
            for (final p in TargetPlatform.values) p: const InstantPageTransitionsBuilder(),
          },
        ),
      );

  /// Applies the user's accessibility choices to a base brand theme.
  static ThemeData resolve(ThemeData base, {required bool highContrast, required bool reduceMotion}) {
    var t = base;
    if (highContrast) t = AccessibleTheme.highContrast(t);
    if (reduceMotion) t = AccessibleTheme.reduceMotion(t);
    return t;
  }
}
