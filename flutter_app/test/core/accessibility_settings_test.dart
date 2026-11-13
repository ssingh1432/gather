import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gather_app/core/accessibility/accessibility_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 60));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('defaults preserve the existing UI (light, 100% text)', () {
    const p = AccessibilityPrefs();
    expect(p.isDefault, isTrue);
    expect(p.themeMode, ThemeMode.light);
    expect(p.textScale, 1.0);
    expect(p.locale, isNull);
  });

  test('text scale is clamped and rounded', () {
    expect(AccessibilityPrefs.clampTextScale(0.1), AccessibilityPrefs.minTextScale);
    expect(AccessibilityPrefs.clampTextScale(9), AccessibilityPrefs.maxTextScale);
    expect(AccessibilityPrefs.clampTextScale(1.2345), 1.23);
  });

  test('copyWith can set and clear the locale', () {
    final ne = const AccessibilityPrefs().copyWith(localeCode: 'ne');
    expect(ne.locale, const Locale('ne'));
    expect(ne.copyWith(clearLocale: true).localeCode, isNull);
  });

  test('changes persist across provider containers', () async {
    final c1 = ProviderContainer();
    addTearDown(c1.dispose);
    c1.read(accessibilityProvider);
    await settle();
    final n = c1.read(accessibilityProvider.notifier);
    n.setTextScale(1.5);
    n.setHighContrast(true);
    n.setBoldText(true);
    n.setReduceMotion(true);
    n.setThemeMode(ThemeMode.dark);
    n.setLocale('ne');
    await settle();

    final c2 = ProviderContainer();
    addTearDown(c2.dispose);
    c2.read(accessibilityProvider);
    await settle();
    final p = c2.read(accessibilityProvider);
    expect(p.textScale, 1.5);
    expect(p.highContrast, isTrue);
    expect(p.boldText, isTrue);
    expect(p.reduceMotion, isTrue);
    expect(p.themeMode, ThemeMode.dark);
    expect(p.localeCode, 'ne');
  });

  test('reset restores defaults', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(accessibilityProvider);
    await settle();
    final n = c.read(accessibilityProvider.notifier);
    n.setHighContrast(true);
    n.setLocale('ne');
    n.reset();
    expect(c.read(accessibilityProvider).isDefault, isTrue);
  });

  test('an unsupported stored locale is ignored', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{'a11y.locale': 'xx'});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(accessibilityProvider);
    await settle();
    expect(c.read(accessibilityProvider).localeCode, isNull);
  });
}
