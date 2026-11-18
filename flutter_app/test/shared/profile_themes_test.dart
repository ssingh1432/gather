import 'package:flutter_test/flutter_test.dart';
import 'package:gather_app/shared/utils/profile_themes.dart';

void main() {
  group('ProfileThemes', () {
    test('accents and labels cover exactly the same keys', () {
      expect(ProfileThemes.accents.keys.toSet(), ProfileThemes.labels.keys.toSet());
    });

    test('default theme keeps the app look (no override)', () {
      expect(ProfileThemes.accentFor('default'), isNull);
      expect(ProfileThemes.accentFor(null), isNull);
    });

    test('known themes resolve and unknown keys fall back safely', () {
      expect(ProfileThemes.accentFor('ocean'), ProfileThemes.accents['ocean']);
      expect(ProfileThemes.accentFor('does-not-exist'), isNull);
    });
  });
}
