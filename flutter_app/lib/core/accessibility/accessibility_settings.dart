import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_l10n.dart';
import '../supabase_client.dart';

/// User-controlled accessibility and language preferences.
///
/// Persisted on-device (SharedPreferences) so they apply before sign-in and on
/// every platform, and mirrored best-effort to `users.language_preference` so
/// server-generated content (emails, push) can follow the chosen language.
@immutable
class AccessibilityPrefs {
  const AccessibilityPrefs({
    this.textScale = defaultTextScale,
    this.highContrast = false,
    this.boldText = false,
    this.reduceMotion = false,
    this.themeMode = defaultThemeMode,
    this.localeCode,
  });

  static const double minTextScale = 0.85;
  static const double maxTextScale = 2.0;
  static const double defaultTextScale = 1.0;

  /// Gather has always shipped light-only; dark/system are opt-in so nobody's
  /// UI changes unexpectedly when their phone is in dark mode.
  static const ThemeMode defaultThemeMode = ThemeMode.light;

  /// Extra multiplier applied on top of the operating-system text scale.
  final double textScale;
  final bool highContrast;
  final bool boldText;
  final bool reduceMotion;
  final ThemeMode themeMode;

  /// `null` follows the device language; otherwise a supported language code.
  final String? localeCode;

  Locale? get locale => localeCode == null ? null : Locale(localeCode!);

  bool get isDefault =>
      textScale == defaultTextScale &&
      !highContrast &&
      !boldText &&
      !reduceMotion &&
      themeMode == defaultThemeMode &&
      localeCode == null;

  AccessibilityPrefs copyWith({
    double? textScale,
    bool? highContrast,
    bool? boldText,
    bool? reduceMotion,
    ThemeMode? themeMode,
    String? localeCode,
    bool clearLocale = false,
  }) =>
      AccessibilityPrefs(
        textScale: clampTextScale(textScale ?? this.textScale),
        highContrast: highContrast ?? this.highContrast,
        boldText: boldText ?? this.boldText,
        reduceMotion: reduceMotion ?? this.reduceMotion,
        themeMode: themeMode ?? this.themeMode,
        localeCode: clearLocale ? null : (localeCode ?? this.localeCode),
      );

  static double clampTextScale(double v) {
    final clamped = v.clamp(minTextScale, maxTextScale).toDouble();
    return (clamped * 100).round() / 100;
  }

  @override
  bool operator ==(Object other) =>
      other is AccessibilityPrefs &&
      other.textScale == textScale &&
      other.highContrast == highContrast &&
      other.boldText == boldText &&
      other.reduceMotion == reduceMotion &&
      other.themeMode == themeMode &&
      other.localeCode == localeCode;

  @override
  int get hashCode => Object.hash(textScale, highContrast, boldText, reduceMotion, themeMode, localeCode);
}

class AccessibilityNotifier extends Notifier<AccessibilityPrefs> {
  static const _kTextScale = 'a11y.text_scale';
  static const _kHighContrast = 'a11y.high_contrast';
  static const _kBoldText = 'a11y.bold_text';
  static const _kReduceMotion = 'a11y.reduce_motion';
  static const _kThemeMode = 'a11y.theme_mode';
  static const _kLocale = 'a11y.locale';

  bool _disposed = false;

  @override
  AccessibilityPrefs build() {
    ref.onDispose(() => _disposed = true);
    unawaited(_load());
    return const AccessibilityPrefs();
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (_disposed) return;
      final storedLocale = p.getString(_kLocale);
      final modeName = p.getString(_kThemeMode);
      state = AccessibilityPrefs(
        textScale: AccessibilityPrefs.clampTextScale(p.getDouble(_kTextScale) ?? AccessibilityPrefs.defaultTextScale),
        highContrast: p.getBool(_kHighContrast) ?? false,
        boldText: p.getBool(_kBoldText) ?? false,
        reduceMotion: p.getBool(_kReduceMotion) ?? false,
        themeMode: ThemeMode.values.firstWhere((m) => m.name == modeName, orElse: () => AccessibilityPrefs.defaultThemeMode),
        localeCode: AppL10n.isSupportedCode(storedLocale) ? storedLocale : null,
      );
    } catch (e) {
      debugPrint('Accessibility prefs load failed: $e');
    }
  }

  Future<void> _save() async {
    final s = state; // capture before awaiting; the notifier may be disposed meanwhile
    try {
      final p = await SharedPreferences.getInstance();
      await p.setDouble(_kTextScale, s.textScale);
      await p.setBool(_kHighContrast, s.highContrast);
      await p.setBool(_kBoldText, s.boldText);
      await p.setBool(_kReduceMotion, s.reduceMotion);
      await p.setString(_kThemeMode, s.themeMode.name);
      if (s.localeCode == null) {
        await p.remove(_kLocale);
      } else {
        await p.setString(_kLocale, s.localeCode!);
      }
    } catch (e) {
      debugPrint('Accessibility prefs save failed: $e');
    }
  }

  void _update(AccessibilityPrefs next) {
    if (next == state) return;
    state = next;
    unawaited(_save());
  }

  void setTextScale(double v) => _update(state.copyWith(textScale: v));
  void setHighContrast(bool v) => _update(state.copyWith(highContrast: v));
  void setBoldText(bool v) => _update(state.copyWith(boldText: v));
  void setReduceMotion(bool v) => _update(state.copyWith(reduceMotion: v));
  void setThemeMode(ThemeMode v) => _update(state.copyWith(themeMode: v));

  /// `null` means "follow the device language".
  void setLocale(String? code) {
    _update(code == null ? state.copyWith(clearLocale: true) : state.copyWith(localeCode: code));
    unawaited(_syncServerLanguage(code));
  }

  void reset() {
    _update(const AccessibilityPrefs());
    unawaited(_syncServerLanguage(null));
  }

  Future<void> _syncServerLanguage(String? code) async {
    final client = SupabaseConfig.maybeClient;
    final uid = client?.auth.currentUser?.id;
    if (client == null || uid == null || code == null) return;
    try {
      await client.from('users').update({'language_preference': code}).eq('id', uid);
    } catch (e) {
      debugPrint('language_preference sync skipped: $e');
    }
  }
}

final accessibilityProvider =
    NotifierProvider<AccessibilityNotifier, AccessibilityPrefs>(AccessibilityNotifier.new);
