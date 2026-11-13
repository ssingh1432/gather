import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gather_app/core/accessibility/accessible_theme.dart';
import 'package:gather_app/core/theme/app_theme.dart';

void main() {
  group('WCAG contrast of brand text colors', () {
    test('light theme body and secondary text meet AA (4.5:1)', () {
      expect(contrastRatio(AppColors.textPrimary, AppColors.surface), greaterThanOrEqualTo(4.5));
      expect(contrastRatio(AppColors.textPrimary, AppColors.background), greaterThanOrEqualTo(4.5));
      expect(contrastRatio(AppColors.textSecondary, AppColors.background), greaterThanOrEqualTo(4.5));
      expect(contrastRatio(AppColors.surface, AppColors.primary), greaterThanOrEqualTo(4.5));
    });

    test('dark theme body and secondary text meet AA (4.5:1)', () {
      expect(contrastRatio(AppColors.darkTextPrimary, AppColors.darkBackground), greaterThanOrEqualTo(4.5));
      expect(contrastRatio(AppColors.darkTextSecondary, AppColors.darkBackground), greaterThanOrEqualTo(4.5));
      expect(contrastRatio(AppColors.darkTextSecondary, AppColors.darkSurface), greaterThanOrEqualTo(4.5));
    });
  });

  group('high-contrast variants meet AAA (7:1)', () {
    test('light', () {
      expect(contrastRatio(AccessibleTheme.hcLightText, AccessibleTheme.hcLightSurface), greaterThanOrEqualTo(7));
      expect(contrastRatio(AccessibleTheme.hcLightPrimary, AccessibleTheme.hcLightSurface), greaterThanOrEqualTo(7));
      expect(contrastRatio(AccessibleTheme.hcLightError, AccessibleTheme.hcLightSurface), greaterThanOrEqualTo(7));
    });

    test('dark', () {
      expect(contrastRatio(AccessibleTheme.hcDarkText, AccessibleTheme.hcDarkSurface), greaterThanOrEqualTo(7));
      expect(contrastRatio(AccessibleTheme.hcDarkPrimary, AccessibleTheme.hcDarkSurface), greaterThanOrEqualTo(7));
      expect(contrastRatio(AccessibleTheme.hcDarkError, AccessibleTheme.hcDarkSurface), greaterThanOrEqualTo(7));
    });

    test('resolved themes actually use the high-contrast colors', () {
      final light = AccessibleTheme.resolve(AppTheme.light, highContrast: true, reduceMotion: false);
      final dark = AccessibleTheme.resolve(AppTheme.dark, highContrast: true, reduceMotion: false);
      expect(light.colorScheme.onSurface, AccessibleTheme.hcLightText);
      expect(light.colorScheme.surface, AccessibleTheme.hcLightSurface);
      expect(dark.colorScheme.onSurface, AccessibleTheme.hcDarkText);
      expect(dark.colorScheme.surface, AccessibleTheme.hcDarkSurface);
    });
  });

  test('brand theme is untouched when no accessibility option is on', () {
    final t = AccessibleTheme.resolve(AppTheme.light, highContrast: false, reduceMotion: false);
    expect(t.colorScheme.primary, AppTheme.light.colorScheme.primary);
  });

  test('reduce motion swaps every platform to instant transitions', () {
    final t = AccessibleTheme.resolve(AppTheme.light, highContrast: false, reduceMotion: true);
    for (final p in TargetPlatform.values) {
      expect(t.pageTransitionsTheme.builders[p], isA<InstantPageTransitionsBuilder>());
    }
  });
}
