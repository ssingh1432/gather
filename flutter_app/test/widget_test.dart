// Basic smoke test to keep the test harness wired up in CI.
//
// This intentionally does not boot the full GatherApp widget tree, since
// GatherApp depends on Supabase being initialized in main() first. A fuller
// integration test that mocks Supabase can replace this later.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Renders a basic widget without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('Gather')),
        ),
      ),
    );

    expect(find.text('Gather'), findsOneWidget);
  });
}
