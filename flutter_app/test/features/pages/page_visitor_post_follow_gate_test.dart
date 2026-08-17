import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gather_app/features/pages/page_profile_screen.dart';

void main() {
  group('PageVisitorPostFollowGate', () {
    Future<void> pump(
      WidgetTester tester, {
      required bool busy,
      required VoidCallback onFollow,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PageVisitorPostFollowGate(busy: busy, onFollow: onFollow),
          ),
        ),
      );
    }

    testWidgets('shows the follow-to-post message and a Follow action', (tester) async {
      await pump(tester, busy: false, onFollow: () {});

      expect(find.text('Follow this Page to post'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Follow'), findsOneWidget);
    });

    testWidgets('tapping Follow invokes the existing follow action', (tester) async {
      var followTapped = false;
      await pump(tester, busy: false, onFollow: () => followTapped = true);

      await tester.tap(find.widgetWithText(FilledButton, 'Follow'));
      await tester.pump();

      expect(followTapped, isTrue);
    });

    testWidgets('disables the Follow action while a follow request is in flight', (tester) async {
      var followTapped = false;
      await pump(tester, busy: true, onFollow: () => followTapped = true);

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);

      await tester.tap(find.widgetWithText(FilledButton, 'Follow'), warnIfMissed: false);
      await tester.pump();

      expect(followTapped, isFalse);
    });
  });
}
