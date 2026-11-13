import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gather_app/features/admin/platform_analytics_tab.dart';
import 'package:gather_app/features/data/repositories.dart';

class _FakeAdminRepo extends AdminRepository {
  _FakeAdminRepo({this.failCrashes = false});
  final bool failCrashes;

  @override
  Future<Map<String, dynamic>> platformKpis() async => {
        'dau': 12,
        'dau_yesterday': 10,
        'wau': 40,
        'mau': 120,
        'mau_previous_30d': 100,
        'stickiness_pct': 10,
        'total_users': 1500,
        'new_users_today': 3,
        'new_users_30d': 60,
        'user_growth_pct_30d': 20,
        'posts_24h': 7,
        'comments_24h': 9,
        'likes_24h': 33,
      };

  @override
  Future<List<Map<String, dynamic>>> activitySeries({int days = 30}) async => [
        for (var i = 0; i < 5; i++)
          {
            'activity_date': '2026-11-0${i + 1}',
            'dau': i + 1,
            'mau_rolling': 10 + i,
            'new_users': 1,
            'post_count': 2,
            'comment_count': 3,
            'like_count': 4,
            'report_count': 0,
          },
      ];

  @override
  Future<List<Map<String, dynamic>>> retentionCohorts({int weeks = 8}) async => [
        {
          'cohort_week': '2026-11-02',
          'cohort_size': 10,
          'd1_eligible': 10,
          'd1_retained': 5,
          'd7_eligible': 0,
          'd7_retained': 0,
          'd30_eligible': 0,
          'd30_retained': 0,
        },
      ];

  @override
  Future<Map<String, dynamic>> engagementSummary({int days = 30}) async => {
        'active_users': 20,
        'engaged_users': 10,
        'engagement_rate_pct': 50,
        'posts': 1,
        'comments': 2,
        'likes': 3,
        'actions_per_active_user': 0.3,
        'feed_views': 5,
        'feed_no_interaction': 1,
        'post_creation_started': 2,
        'post_creation_abandoned': 1,
        'users_by_platform': {'web': 4},
      };

  @override
  Future<Map<String, dynamic>> moderationAnalytics({int days = 30}) async => {
        'reports_total': 4,
        'reports_open': 1,
        'reports_automated': 0,
        'posts_removed': 1,
        'avg_appeal_review_hours': null,
        'reports_by_status': {'open': 1},
        'reports_by_category': {'spam': 3},
        'actions_by_type': {},
        'appeals_by_status': {},
      };

  @override
  Future<List<Map<String, dynamic>>> uploadsSeries({int days = 30}) async => [
        {'upload_date': '2026-11-10', 'upload_count': 2, 'upload_bytes': 2048},
      ];

  @override
  Future<Map<String, dynamic>> crashAnalytics({int days = 14}) async {
    if (failCrashes) throw Exception('boom');
    return {
      'window_days': 14,
      'total_errors': 3,
      'affected_users': 1,
      'by_platform': {'web': 3},
      'by_version': {'0.1.0+1': 3},
      'top_errors': [
        {'message': 'ImageCodecException', 'count': 3, 'users': 1},
      ],
      'daily': [],
    };
  }
}

Widget _host(AdminRepository repo) => MaterialApp(home: Scaffold(body: PlatformAnalyticsTab(repo: repo)));

void _tallViewport(WidgetTester tester) {
  // ListView builds lazily; a tall surface renders every section.
  tester.view.physicalSize = const Size(1000, 8000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('renders KPIs, retention and sections', (tester) async {
    _tallViewport(tester);
    await tester.pumpWidget(_host(_FakeAdminRepo()));
    await tester.pumpAndSettle();

    expect(find.text('DAU (today)'), findsOneWidget);
    expect(find.text('1,500'), findsOneWidget); // total users, thousands separator
    expect(find.text('Retention (weekly signup cohorts)'), findsOneWidget);
    expect(find.text('50%'), findsWidgets); // day-1 retention 5/10
    expect(find.text('–'), findsWidgets); // day-7/30 not yet eligible
  });

  testWidgets('a failing section does not blank the page', (tester) async {
    _tallViewport(tester);
    await tester.pumpWidget(_host(_FakeAdminRepo(failCrashes: true)));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not load this section'), findsOneWidget);
    expect(find.text('DAU (today)'), findsOneWidget);
  });

  testWidgets('charts expose a text alternative to screen readers', (tester) async {
    _tallViewport(tester);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(_FakeAdminRepo()));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel(RegExp('Line chart of daily active users')), findsOneWidget);
    handle.dispose();
  });
}
