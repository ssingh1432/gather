import 'package:flutter_test/flutter_test.dart';

import 'package:gather_app/features/pages/page_team_screen.dart';

void main() {
  group('Page team screen contract', () {
    test('requires and preserves the Page id used for team management', () {
      const page = PageTeamScreen(pageId: 'page-123');

      expect(page.pageId, 'page-123');
    });
  });
}
