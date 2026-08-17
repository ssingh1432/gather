import 'package:flutter_test/flutter_test.dart';

import 'package:gather_app/features/pages/page_analytics_screen.dart';
import 'package:gather_app/features/pages/page_manage_screen.dart';
import 'package:gather_app/features/pages/page_profile_screen.dart';
import 'package:gather_app/features/pages/page_settings_screen.dart';

void main() {
  group('Professional Pages final QA contracts', () {
    const pageId = 'page-qa-123';

    test('public Page preserves its Page identity', () {
      const page = PageProfileScreen(pageId: pageId);
      expect(page.pageId, pageId);
    });

    test('Manage Page preserves its Page identity', () {
      const page = PageManageScreen(pageId: pageId);
      expect(page.pageId, pageId);
    });

    test('Page Insights preserves its Page identity', () {
      const page = PageAnalyticsScreen(pageId: pageId);
      expect(page.pageId, pageId);
    });

    test('Page Settings preserves its Page identity', () {
      const page = PageSettingsScreen(pageId: pageId);
      expect(page.pageId, pageId);
    });
  });
}
