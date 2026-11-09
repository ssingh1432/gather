import 'package:flutter_test/flutter_test.dart';
import 'package:gather_app/shared/utils/username_validator.dart';

void main() {
  test('accepts valid usernames', () {
    for (final u in ['sita_01', 'ram.sharma', 'abc', 'a1b2c3']) {
      expect(UsernameValidator.validate(u), isNull, reason: u);
    }
  });

  test('rejects invalid usernames', () {
    for (final u in ['ab', 'UPPER', 'has space', '_lead', 'trail.', 'a..b', '12345', 'admin', 'x' * 31, 'né']) {
      expect(UsernameValidator.validate(u), isNotNull, reason: u);
    }
  });
}
