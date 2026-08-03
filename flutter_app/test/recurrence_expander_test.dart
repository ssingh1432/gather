import 'package:flutter_test/flutter_test.dart';
import 'package:gather_app/shared/utils/recurrence_expander.dart';

void main() {
  group('RecurrenceExpander.expand — DAILY', () {
    test('generates consecutive days up to COUNT', () {
      final first = DateTime(2026, 1, 1, 9, 0);
      final dates = RecurrenceExpander.expand(firstStart: first, rule: 'FREQ=DAILY;COUNT=5');
      expect(dates.length, 5);
      for (var i = 0; i < 5; i++) {
        expect(dates[i], DateTime(2026, 1, 1 + i, 9, 0));
      }
    });

    test('respects INTERVAL', () {
      final first = DateTime(2026, 1, 1, 9, 0);
      final dates = RecurrenceExpander.expand(firstStart: first, rule: 'FREQ=DAILY;INTERVAL=3;COUNT=3');
      expect(dates, [DateTime(2026, 1, 1, 9, 0), DateTime(2026, 1, 4, 9, 0), DateTime(2026, 1, 7, 9, 0)]);
    });

    test('stops at UNTIL even if COUNT would allow more', () {
      final first = DateTime(2026, 1, 1, 9, 0);
      final dates = RecurrenceExpander.expand(firstStart: first, rule: 'FREQ=DAILY;COUNT=100;UNTIL=2026-01-03T09:00:00.000');
      expect(dates.length, 3);
      expect(dates.last, DateTime(2026, 1, 3, 9, 0));
    });
  });

  group('RecurrenceExpander.expand — WEEKLY (default weekday)', () {
    test('repeats on the same weekday as firstStart when BYDAY is omitted', () {
      final first = DateTime(2026, 1, 7, 18, 30); // a Wednesday
      final dates = RecurrenceExpander.expand(firstStart: first, rule: 'FREQ=WEEKLY;COUNT=4');
      expect(dates.length, 4);
      for (final d in dates) {
        expect(d.weekday, DateTime.wednesday);
        expect(d.hour, 18);
        expect(d.minute, 30);
      }
      expect(dates[1].difference(dates[0]).inDays, 7);
      expect(dates[3].difference(dates[0]).inDays, 21);
    });

    test('every-2-weeks interval doubles the spacing', () {
      final first = DateTime(2026, 1, 7, 9, 0); // Wednesday
      final dates = RecurrenceExpander.expand(firstStart: first, rule: 'FREQ=WEEKLY;INTERVAL=2;COUNT=3');
      expect(dates.length, 3);
      expect(dates[1].difference(dates[0]).inDays, 14);
      expect(dates[2].difference(dates[0]).inDays, 28);
    });
  });

  group('RecurrenceExpander.expand — WEEKLY with BYDAY (weekday mapping)', () {
    // Regression tests for a bug where every BYDAY code mapped to the
    // wrong Dart weekday (SU..SA indexed from 0 was treated as if Dart's
    // weekday numbering started at SU=1, but DateTime.weekday is
    // Monday=1..Sunday=7 — every single day code was off by one, and SU
    // wrapped incorrectly to 1 instead of 7).
    test('BYDAY=SU produces Sunday occurrences, not Monday', () {
      final first = DateTime(2026, 1, 4, 10, 0); // a Sunday
      final dates = RecurrenceExpander.expand(firstStart: first, rule: 'FREQ=WEEKLY;BYDAY=SU;COUNT=3');
      for (final d in dates) {
        expect(d.weekday, DateTime.sunday);
      }
    });

    test('BYDAY=SA produces Saturday occurrences, not Sunday', () {
      final first = DateTime(2026, 1, 3, 10, 0); // a Saturday
      final dates = RecurrenceExpander.expand(firstStart: first, rule: 'FREQ=WEEKLY;BYDAY=SA;COUNT=3');
      for (final d in dates) {
        expect(d.weekday, DateTime.saturday);
      }
    });

    test('BYDAY=MO,WE,FR produces three occurrences per week on the correct days', () {
      final first = DateTime(2026, 1, 5, 7, 0); // a Monday
      final dates = RecurrenceExpander.expand(firstStart: first, rule: 'FREQ=WEEKLY;BYDAY=MO,WE,FR;COUNT=6');
      expect(dates.length, 6);
      final weekdays = dates.map((d) => d.weekday).toList();
      expect(weekdays, [DateTime.monday, DateTime.wednesday, DateTime.friday, DateTime.monday, DateTime.wednesday, DateTime.friday]);
      // First three fall in week 1, next three in week 2.
      expect(dates[3].difference(dates[0]).inDays, 7);
    });

    test('BYDAY candidates before firstStart in its own week are excluded', () {
      // firstStart is Wednesday; BYDAY includes Monday, which already
      // passed this week — the first Monday occurrence should be next week.
      final first = DateTime(2026, 1, 7, 9, 0); // Wednesday
      final dates = RecurrenceExpander.expand(firstStart: first, rule: 'FREQ=WEEKLY;BYDAY=MO,WE;COUNT=3');
      expect(dates[0].weekday, DateTime.wednesday);
      expect(dates[0], first);
      expect(dates[1].weekday, DateTime.monday);
      expect(dates[1].isAfter(first), isTrue);
    });
  });

  group('RecurrenceExpander.expand — MONTHLY', () {
    test('repeats on the same day of month', () {
      final first = DateTime(2026, 1, 15, 12, 0);
      final dates = RecurrenceExpander.expand(firstStart: first, rule: 'FREQ=MONTHLY;COUNT=3');
      expect(dates, [DateTime(2026, 1, 15, 12, 0), DateTime(2026, 2, 15, 12, 0), DateTime(2026, 3, 15, 12, 0)]);
    });

    test('clamps to the last day of shorter months instead of overflowing', () {
      final first = DateTime(2026, 1, 31, 8, 0);
      final dates = RecurrenceExpander.expand(firstStart: first, rule: 'FREQ=MONTHLY;COUNT=3');
      expect(dates[0], DateTime(2026, 1, 31, 8, 0));
      expect(dates[1], DateTime(2026, 2, 28, 8, 0)); // Feb 2026 has 28 days
      expect(dates[2], DateTime(2026, 3, 31, 8, 0));
    });

    test('rolls over the year boundary correctly', () {
      final first = DateTime(2026, 11, 30, 9, 0);
      final dates = RecurrenceExpander.expand(firstStart: first, rule: 'FREQ=MONTHLY;COUNT=3');
      expect(dates[0].month, 11);
      expect(dates[1], DateTime(2026, 12, 30, 9, 0));
      expect(dates[2], DateTime(2027, 1, 30, 9, 0));
    });
  });

  group('RecurrenceExpander.expand — safety limits and fallbacks', () {
    test('applies a hard cap of 104 occurrences when neither COUNT nor UNTIL is given', () {
      final first = DateTime(2026, 1, 1, 9, 0);
      final dates = RecurrenceExpander.expand(firstStart: first, rule: 'FREQ=DAILY');
      expect(dates.length, 104);
    });

    test('clamps an absurdly large COUNT to the hard cap', () {
      final first = DateTime(2026, 1, 1, 9, 0);
      final dates = RecurrenceExpander.expand(firstStart: first, rule: 'FREQ=DAILY;COUNT=999999');
      expect(dates.length, 104);
    });

    test('falls back to a single occurrence when FREQ is missing', () {
      final first = DateTime(2026, 1, 1, 9, 0);
      final dates = RecurrenceExpander.expand(firstStart: first, rule: 'INTERVAL=2');
      expect(dates, [first]);
    });

    test('falls back to a single occurrence for an unrecognized FREQ', () {
      final first = DateTime(2026, 1, 1, 9, 0);
      final dates = RecurrenceExpander.expand(firstStart: first, rule: 'FREQ=YEARLY;COUNT=5');
      expect(dates, [first]);
    });

    test('falls back to a single occurrence for a zero or negative INTERVAL', () {
      final first = DateTime(2026, 1, 1, 9, 0);
      final dates = RecurrenceExpander.expand(firstStart: first, rule: 'FREQ=DAILY;INTERVAL=0;COUNT=5');
      expect(dates, [first]);
    });

    test('ignores unrecognized BYDAY tokens rather than throwing', () {
      final first = DateTime(2026, 1, 5, 9, 0); // Monday
      final dates = RecurrenceExpander.expand(firstStart: first, rule: 'FREQ=WEEKLY;BYDAY=XX,MO;COUNT=2');
      expect(dates.length, 2);
      for (final d in dates) {
        expect(d.weekday, DateTime.monday);
      }
    });
  });
}
