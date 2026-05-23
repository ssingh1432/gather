import 'package:flutter_test/flutter_test.dart';

bool isValidEmail(String value) => value.contains('@') && value.contains('.');
bool isValidPassword(String value) => value.trim().length >= 8;
bool isNonEmptyPost(String value) => value.trim().isNotEmpty;

void main() {
  test('password validation works', () {
    expect(isValidPassword('12345678'), true);
    expect(isValidPassword('short'), false);
  });

  test('post content validation works', () {
    expect(isNonEmptyPost('hello world'), true);
    expect(isNonEmptyPost('   '), false);
  });

  test('email validation works', () {
    expect(isValidEmail('user@example.com'), true);
    expect(isValidEmail('invalid'), false);
  });
}
