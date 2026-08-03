import 'package:flutter_test/flutter_test.dart';
import 'package:gather_app/shared/utils/time_ago.dart';

void main() {
  group('formatEventDateTime', () {
    test('formats a normal afternoon time', () {
      // Jan 7 2026 is a Wednesday.
      final result = formatEventDateTime(DateTime(2026, 1, 7, 18, 30));
      expect(result, 'Wed, Jan 7 · 6:30 PM');
    });

    test('formats midnight as 12:00 AM, not 0:00 AM', () {
      final result = formatEventDateTime(DateTime(2026, 1, 7, 0, 0));
      expect(result, contains('12:00 AM'));
    });

    test('formats noon as 12:00 PM, not 0:00 PM', () {
      final result = formatEventDateTime(DateTime(2026, 1, 7, 12, 0));
      expect(result, contains('12:00 PM'));
    });

    test('pads single-digit minutes with a leading zero', () {
      final result = formatEventDateTime(DateTime(2026, 1, 7, 9, 5));
      expect(result, contains('9:05 AM'));
    });

    test('uses the correct weekday and month abbreviations across the year', () {
      // Jan 1 2026 is a Thursday.
      expect(formatEventDateTime(DateTime(2026, 1, 1, 9, 0)), startsWith('Thu, Jan 1'));
      // Dec 25 2026 is a Friday.
      expect(formatEventDateTime(DateTime(2026, 12, 25, 9, 0)), startsWith('Fri, Dec 25'));
    });
  });
}
