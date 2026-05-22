import 'package:flutter_test/flutter_test.dart';

bool isValidEmail(String value) => value.contains('@') && value.contains('.');

void main() {
  test('email validator works', () {
    expect(isValidEmail('user@example.com'), true);
    expect(isValidEmail('invalid'), false);
  });
}
