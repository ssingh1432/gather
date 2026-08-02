/// Expands a small, deliberately-limited RRULE-style subset into concrete
/// occurrence dates. This is intentionally NOT a full RFC 5545 parser —
/// Gather only needs the common cases communities actually use (weekly
/// meetups, monthly gatherings, daily standups). Anything more exotic can be
/// modeled as a series of one-off events instead.
///
/// Supported rule string, e.g. `FREQ=WEEKLY;INTERVAL=2;BYDAY=SA;COUNT=10`:
///   FREQ      = DAILY | WEEKLY | MONTHLY   (required)
///   INTERVAL  = positive integer, default 1
///   BYDAY     = comma-separated SU,MO,TU,WE,TH,FR,SA (WEEKLY only; if
///               omitted, uses the weekday of the first occurrence)
///   COUNT     = positive integer — stop after this many occurrences
///   UNTIL     = ISO-8601 date — stop generating past this date
/// Exactly one of COUNT / UNTIL should be provided; if both are given,
/// whichever is reached first wins. If neither is given, a hard safety cap
/// of 104 occurrences (~2 years weekly) is applied so a typo can never
/// generate an unbounded number of rows.
class RecurrenceExpander {
  static const _dayCodes = ['SU', 'MO', 'TU', 'WE', 'TH', 'FR', 'SA'];
  static const _hardCap = 104;

  /// Returns the list of occurrence start times, including [firstStart]
  /// itself as the first entry.
  static List<DateTime> expand({
    required DateTime firstStart,
    required String rule,
  }) {
    final parts = <String, String>{};
    for (final segment in rule.split(';')) {
      final kv = segment.split('=');
      if (kv.length == 2) parts[kv[0].trim().toUpperCase()] = kv[1].trim();
    }

    final freq = parts['FREQ']?.toUpperCase();
    final interval = int.tryParse(parts['INTERVAL'] ?? '1') ?? 1;
    final count = int.tryParse(parts['COUNT'] ?? '');
    final until = parts['UNTIL'] != null ? DateTime.tryParse(parts['UNTIL']!) : null;
    final byDay = parts['BYDAY']?.split(',').map((d) => d.trim().toUpperCase()).where(_dayCodes.contains).toList();

    if (freq == null || (interval <= 0)) return [firstStart];

    final maxCount = count != null && count > 0 ? count.clamp(1, _hardCap) : _hardCap;
    final results = <DateTime>[];

    switch (freq) {
      case 'DAILY':
        var current = firstStart;
        while (results.length < maxCount) {
          if (until != null && current.isAfter(until)) break;
          results.add(current);
          current = current.add(Duration(days: interval));
        }
        break;

      case 'WEEKLY':
        final targetWeekdays = (byDay != null && byDay.isNotEmpty)
            ? byDay.map((d) => _dayCodes.indexOf(d) + 1).toList() // DateTime.weekday: Mon=1..Sun=7
            : [firstStart.weekday];
        var weekStart = firstStart.subtract(Duration(days: firstStart.weekday - 1));
        var weekIndex = 0;
        while (results.length < maxCount) {
          if (weekIndex % interval == 0) {
            final candidates = targetWeekdays.map((wd) => weekStart.add(Duration(days: wd - 1))).where((d) => !d.isBefore(firstStart)).toList()
              ..sort((a, b) => a.compareTo(b));
            for (final c in candidates) {
              if (results.length >= maxCount) break;
              if (until != null && c.isAfter(until)) return _withTime(results, firstStart);
              results.add(DateTime(c.year, c.month, c.day, firstStart.hour, firstStart.minute));
            }
          }
          weekStart = weekStart.add(const Duration(days: 7));
          weekIndex++;
          if (weekIndex > _hardCap * 2) break; // absolute safety valve
        }
        return results.take(maxCount).toList();

      case 'MONTHLY':
        var monthOffset = 0;
        while (results.length < maxCount) {
          final year = firstStart.year + ((firstStart.month - 1 + monthOffset * interval) ~/ 12);
          final month = ((firstStart.month - 1 + monthOffset * interval) % 12) + 1;
          final day = firstStart.day.clamp(1, DateTime(year, month + 1, 0).day);
          final candidate = DateTime(year, month, day, firstStart.hour, firstStart.minute);
          if (until != null && candidate.isAfter(until)) break;
          results.add(candidate);
          monthOffset++;
        }
        break;

      default:
        return [firstStart];
    }

    return results;
  }

  static List<DateTime> _withTime(List<DateTime> dates, DateTime reference) => dates;
}
