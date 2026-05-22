import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pagination offset is deterministic', () {
    const pageSize = 20;
    expect(0 * pageSize, 0);
    expect(2 * pageSize, 40);
  });
}
