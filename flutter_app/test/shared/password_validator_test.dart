import 'package:flutter_test/flutter_test.dart';
import 'package:gather_app/shared/utils/password_validator.dart';

void main() {
  group('PasswordValidator', () {
    test('accepts passwords meeting every rule', () {
      for (final p in ['Abcdef12', 'Gather2026x', 'Zz9zzzzz', 'Aa1' * 10]) {
        expect(PasswordValidator.validate(p), isNull, reason: p);
        expect(PasswordValidator.isStrong(p), isTrue, reason: p);
      }
    });

    test('rejects too-short passwords first (boundary at minLength)', () {
      expect(PasswordValidator.validate('Abc1234'), contains('at least 8'));
      expect(PasswordValidator.validate('Abc12345'), isNull);
      expect(PasswordValidator.minLength, 8);
      expect(PasswordValidator.validate(''), isNotNull);
    });

    test('requires upper, lower and digit with specific messages', () {
      expect(PasswordValidator.validate('abcdefg1'), contains('uppercase'));
      expect(PasswordValidator.validate('ABCDEFG1'), contains('lowercase'));
      expect(PasswordValidator.validate('Abcdefgh'), contains('number'));
    });

    test('symbols and spaces alone do not satisfy character classes', () {
      expect(PasswordValidator.isStrong('!!!!!!!!!!'), isFalse);
      expect(PasswordValidator.isStrong('        '), isFalse);
    });

    test('non-Latin letters do not count as upper/lower case', () {
      // Devanagari has no case; a Nepali-only password must still be rejected.
      expect(PasswordValidator.isStrong('नमस्तेनेपाल1'), isFalse);
      expect(PasswordValidator.isStrong('नमस्तेAa1x'), isTrue);
    });
  });
}
