import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gather_app/features/legal/file_copyright_notice_screen.dart';

Future<void> _pump(WidgetTester t, {String? postId}) async {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = const Size(800, 1600);
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: FileCopyrightNoticeScreen(postId: postId)));
}

Finder _snack(String text) => find.descendant(of: find.byType(SnackBar), matching: find.textContaining(text));

Future<void> _tapSubmit(WidgetTester t) async {
  await t.ensureVisible(find.text('Submit notice'));
  await t.tap(find.text('Submit notice'));
  await t.pump();
}

void main() {
  testWidgets('shows the form with both legal statements unchecked', (t) async {
    await _pump(t);
    expect(find.text('Report copyright infringement'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNWidgets(2));
    for (final c in t.widgetList<CheckboxListTile>(find.byType(CheckboxListTile))) {
      expect(c.value, isFalse);
    }
  });

  testWidgets('asks for the infringing link when opened without a post', (t) async {
    await _pump(t);
    expect(find.text('Link to the infringing content'), findsOneWidget);
  });

  testWidgets('hides the link field when reporting a specific post', (t) async {
    await _pump(t, postId: 'abc');
    expect(find.text('Link to the infringing content'), findsNothing);
    expect(find.textContaining('Reporting the post'), findsOneWidget);
  });

  testWidgets('empty submit is blocked with a validation message (no network call)', (t) async {
    await _pump(t);
    await _tapSubmit(t);
    expect(_snack('Enter your full legal name'), findsOneWidget);
  });

  testWidgets('complete text but unchecked statements is blocked', (t) async {
    await _pump(t);
    await t.enterText(find.widgetWithText(TextField, 'Your full legal name'), 'Asha Gurung');
    await t.enterText(find.widgetWithText(TextField, 'Contact email'), 'asha@example.com');
    await t.enterText(find.widgetWithText(TextField, 'Describe the copyrighted work'), 'My original photograph of Pashupatinath');
    await t.enterText(find.widgetWithText(TextField, 'Link to the infringing content'), 'https://gather.example/p/1');
    await t.enterText(find.widgetWithText(TextField, 'Electronic signature (type your full name)'), 'Asha Gurung');
    await _tapSubmit(t);
    expect(_snack('good-faith belief'), findsOneWidget);
  });
}
