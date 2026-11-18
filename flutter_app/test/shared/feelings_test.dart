import 'package:flutter_test/flutter_test.dart';
import 'package:gather_app/shared/utils/feelings.dart';

void main() {
  group('feelings helpers', () {
    test('stored format round-trips through emoji and label helpers', () {
      for (final f in kFeelingOptions) {
        expect(feelingEmoji(f.stored), f.emoji, reason: f.label);
        expect(feelingLabel(f.stored), f.label, reason: f.label);
      }
    });

    test('feelingEmoji is null for null/blank input', () {
      expect(feelingEmoji(null), isNull);
      expect(feelingEmoji(''), isNull);
      expect(feelingEmoji('   '), isNull);
    });

    test('feelingLabel keeps multi-word labels and tolerates label-only input', () {
      expect(feelingLabel('😊 very happy'), 'very happy');
      expect(feelingLabel('happy'), 'happy');
      expect(feelingLabel('  😊 happy  '), 'happy');
    });

    test('options are unique so the picker never shows duplicates', () {
      expect(kFeelingOptions.map((f) => f.label).toSet().length, kFeelingOptions.length);
      expect(kFeelingOptions.map((f) => f.emoji).toSet().length, kFeelingOptions.length);
    });
  });
}
