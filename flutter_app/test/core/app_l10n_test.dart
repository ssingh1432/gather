import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gather_app/core/l10n/app_l10n.dart';

void main() {
  final en = AppL10n.strings['en']!;
  final ne = AppL10n.strings['ne']!;

  test('English and Nepali define exactly the same keys', () {
    expect(ne.keys.toSet(), en.keys.toSet());
  });

  test('no translation is empty', () {
    for (final entry in {...en.entries, ...ne.entries}) {
      expect(entry.value.trim(), isNotEmpty, reason: entry.key);
    }
  });

  test('placeholders match between languages', () {
    final re = RegExp(r'\{(\w+)\}');
    for (final key in en.keys) {
      final a = re.allMatches(en[key]!).map((m) => m.group(1)).toSet();
      final b = re.allMatches(ne[key]!).map((m) => m.group(1)).toSet();
      expect(b, a, reason: 'placeholder mismatch for $key');
    }
  });

  test('Nepali strings are actually translated (contain Devanagari) unless they are brand names', () {
    final devanagari = RegExp(r'[\u0900-\u097F]');
    for (final key in ne.keys) {
      expect(devanagari.hasMatch(ne[key]!), isTrue, reason: '$key is not translated');
    }
  });

  test('lookup, placeholder substitution and fallbacks', () {
    const nepali = AppL10n(Locale('ne'));
    const english = AppL10n(Locale('en'));
    expect(nepali.navHome, 'गृहपृष्ठ');
    expect(english.navHome, 'Home');
    expect(english.postLikesCount(12), '12 likes');
    expect(nepali.postViewProfile('Sita'), contains('Sita'));
    // Unsupported language falls back to English; unknown key returns the key.
    expect(const AppL10n(Locale('fr')).navHome, 'Home');
    expect(english.t('does_not_exist'), 'does_not_exist');
  });

  test('delegate supports en and ne only', () {
    expect(AppL10n.delegate.isSupported(const Locale('ne')), isTrue);
    expect(AppL10n.delegate.isSupported(const Locale('en', 'US')), isTrue);
    expect(AppL10n.delegate.isSupported(const Locale('de')), isFalse);
  });

  testWidgets('resolves from the widget tree for the Nepali locale', (tester) async {
    String? home;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ne'),
        supportedLocales: AppL10n.supportedLocales,
        localizationsDelegates: const [
          AppL10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(builder: (context) {
          home = AppL10n.of(context).navHome;
          return const SizedBox();
        }),
      ),
    );
    expect(home, 'गृहपृष्ठ');
  });
}
