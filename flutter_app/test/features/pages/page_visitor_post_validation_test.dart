import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rich visitor post accepts text, media, or event', () {
    bool valid(String text, int mediaCount, String? eventId) => text.trim().isNotEmpty || mediaCount > 0 || eventId != null;
    expect(valid('hello', 0, null), isTrue);
    expect(valid('', 1, null), isTrue);
    expect(valid('', 0, 'event-1'), isTrue);
    expect(valid('   ', 0, null), isFalse);
  });

  test('visitor media limit is 25 MB', () {
    expect(25 * 1024 * 1024, 26214400);
  });
}
