import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gather_app/core/responsive.dart';

Future<void> _pumpAt(WidgetTester t, double width, void Function(BuildContext) check) async {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = Size(width, 800);
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: Builder(builder: (c) {
    check(c);
    return const SizedBox();
  })));
}

void main() {
  testWidgets('phone below 700', (t) async {
    await _pumpAt(t, 699, (c) {
      expect(Breakpoints.isMobile(c), isTrue);
      expect(Breakpoints.isTablet(c), isFalse);
      expect(Breakpoints.isDesktop(c), isFalse);
    });
  });

  testWidgets('tablet from 700 up to 999', (t) async {
    await _pumpAt(t, 700, (c) {
      expect(Breakpoints.isMobile(c), isFalse);
      expect(Breakpoints.isTablet(c), isTrue);
    });
    await _pumpAt(t, 999, (c) => expect(Breakpoints.isTablet(c), isTrue));
  });

  testWidgets('desktop from 1000', (t) async {
    await _pumpAt(t, 1000, (c) {
      expect(Breakpoints.isDesktop(c), isTrue);
      expect(Breakpoints.isTablet(c), isFalse);
    });
  });
}
