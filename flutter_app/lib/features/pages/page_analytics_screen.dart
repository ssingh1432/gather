import 'package:flutter/material.dart';

import '../data/repositories.dart';
import '../../shared/widgets/reusables.dart';
import 'pages_theme.dart';

/// Page Analytics (Step 11 of the Professional Page System): reach,
/// impressions, views, follower growth, engagement, and top posts.
/// Gated server-side by the `view_analytics` page permission (or owner
/// role) via migration 084_pages_analytics_step11.sql — a caller without
/// it gets an access-denied state, not empty charts.
class PageAnalyticsScreen extends StatefulWidget {
  const PageAnalyticsScreen({super.key, required this.pageId, this.pageName});
  final String pageId;
  final String? pageName;

  @override
  State<PageAnalyticsScreen> createState() => _PageAnalyticsScreenState();
}

class _PageAnalyticsScreenState extends State<PageAnalyticsScreen> {
  final repo = PageAnalyticsRepository();
  bool _loading = true;
  bool _accessDenied = false;
  String? _error;

  List<Map<String, dynamic>> _summary = const [];
  List<Map<String, dynamic>> _growth = const [];
  List<Map<String, dynamic>> _topPosts = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _accessDenied = false;
      _error = null;
    });
    try {
      final results = await Future.wait([
        repo.summary(widget.pageId, daysBack: 14),
        repo.audienceGrowth(widget.pageId, daysBack: 14),
        repo.topPosts(widget.pageId, daysBack: 30, limit: 5),
      ]);
      _summary = results[0];
      _growth = results[1];
      _topPosts = results[2];
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('permission') || msg.contains('denied') || msg.contains('Not authorized')) {
        _accessDenied = true;
      } else {
        _error = 'Could not load analytics: $e';
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _sum(String key) => _summary.fold<int>(0, (a, r) => a + ((r[key] as num?)?.toInt() ?? 0));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.pageName?.isNotEmpty == true ? '${widget.pageName} · Insights' : 'Page Insights',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        bottom: appBarBottomBorder(context),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _accessDenied
              ? const EmptyState(
                  icon: Icons.lock_outline,
                  title: 'Analytics not available',
                  message: "You need the page's analytics permission to view insights here — ask an owner or manager.",
                )
              : _error != null
                  ? ErrorRetryState(title: 'Something went wrong', message: _error!, onRetry: _load)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.all(PageTokens.spaceLg),
                        children: [
                          _SummaryGrid(
                            reach: _sum('reach'),
                            impressions: _sum('impressions'),
                            views: _sum('views'),
                            newFollowers: _sum('new_followers'),
                            engagement: _sum('engagement'),
                          ),
                          const SizedBox(height: PageTokens.spaceLg),
                          _SectionCard(
                            title: 'Audience growth (14 days)',
                            child: _MiniBarChart(
                              labels: _growth.map((r) => (r['day'] as String).substring(5)).toList(),
                              values: _growth.map((r) => (r['new_followers'] as num).toDouble()).toList(),
                              legendPrimary: 'New followers',
                            ),
                          ),
                          const SizedBox(height: PageTokens.spaceLg),
                          _SectionCard(
                            title: 'Reach & views (14 days)',
                            child: _MiniBarChart(
                              labels: _summary.map((r) => (r['day'] as String).substring(5)).toList(),
                              values: _summary.map((r) => (r['reach'] as num).toDouble()).toList(),
                              secondaryValues: _summary.map((r) => -(r['views'] as num).toDouble()).toList(),
                              legendPrimary: 'Reach',
                              legendSecondary: 'Views',
                            ),
                          ),
                          const SizedBox(height: PageTokens.spaceLg),
                          _SectionCard(
                            title: 'Top posts (30 days)',
                            child: _topPosts.isEmpty
                                ? Padding(
                                    padding: const EdgeInsets.all(PageTokens.spaceSm),
                                    child: Text('No posts in this window yet.', style: Theme.of(context).textTheme.bodySmall),
                                  )
                                : Column(
                                    children: [
                                      for (final p in _topPosts)
                                        Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 6),
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      (p['content'] as String?)?.trim().isNotEmpty == true ? p['content'] as String : '(media post)',
                                                      maxLines: 2,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      '${p['views']} views · ${p['reach']} reach · ${p['impressions']} impressions',
                                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              PageStatChip(
                                                icon: Icons.trending_up,
                                                label: (p['engagement_score'] as num).toStringAsFixed(0),
                                                color: AppColors.brandTeal,
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                          ),
                          const SizedBox(height: PageTokens.spaceXl),
                        ],
                      ),
                    ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.reach, required this.impressions, required this.views, required this.newFollowers, required this.engagement});
  final int reach, impressions, views, newFollowers, engagement;

  @override
  Widget build(BuildContext context) {
    final items = [
      ('Reach', reach, Icons.public),
      ('Impressions', impressions, Icons.visibility_outlined),
      ('Views', views, Icons.remove_red_eye_outlined),
      ('New followers', newFollowers, Icons.person_add_alt_1_outlined),
      ('Engagement', engagement, Icons.bolt_outlined),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: PageTokens.spaceMd,
      crossAxisSpacing: PageTokens.spaceMd,
      childAspectRatio: 2.2,
      children: [
        for (final (label, value, icon) in items)
          Container(
            decoration: BoxDecoration(
              color: PageColors.surfaceCard(context),
              borderRadius: BorderRadius.circular(PageTokens.radiusMd),
              border: Border.all(color: PageColors.border(context)),
              boxShadow: PageTokens.subtleShadow(context),
            ),
            padding: const EdgeInsets.all(PageTokens.spaceMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: AppColors.brandTeal),
                const SizedBox(height: 6),
                Text('$value', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: PageColors.surfaceCard(context),
          borderRadius: BorderRadius.circular(PageTokens.radiusMd),
          border: Border.all(color: PageColors.border(context)),
        ),
        padding: const EdgeInsets.all(PageTokens.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: PageTokens.spaceMd),
            child,
          ],
        ),
      );
}

/// Minimal, dependency-free bar chart — mirrors
/// `CommunityAnalyticsScreen`'s `_MiniBarChart` so Pages and Communities
/// insights look/feel identical without a cross-feature import.
class _MiniBarChart extends StatelessWidget {
  const _MiniBarChart({required this.labels, required this.values, this.secondaryValues, required this.legendPrimary, this.legendSecondary});
  final List<String> labels;
  final List<double> values;
  final List<double>? secondaryValues;
  final String legendPrimary;
  final String? legendSecondary;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return Padding(padding: const EdgeInsets.all(PageTokens.spaceSm), child: Text('No data yet.', style: Theme.of(context).textTheme.bodySmall));
    final maxVal = [...values, ...(secondaryValues ?? const [])].map((v) => v.abs()).fold<double>(1, (a, b) => a > b ? a : b);
    const primaryColor = AppColors.brandTeal;
    const secondaryColor = Color(0xFFE0714B);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 100,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(values.length, (i) {
              final barHeight = (values[i].abs() / maxVal) * 70;
              final subHeight = secondaryValues != null ? (secondaryValues![i].abs() / maxVal) * 30 : 0.0;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(height: barHeight, decoration: BoxDecoration(color: primaryColor, borderRadius: BorderRadius.circular(2))),
                      if (secondaryValues != null) const SizedBox(height: 1),
                      if (secondaryValues != null)
                        Container(height: subHeight, decoration: BoxDecoration(color: secondaryColor, borderRadius: BorderRadius.circular(2))),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 4),
        Row(children: labels.map((l) => Expanded(child: Text(l, textAlign: TextAlign.center, style: const TextStyle(fontSize: 9)))).toList()),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          children: [
            _LegendDot(color: primaryColor, label: legendPrimary),
            if (legendSecondary != null) _LegendDot(color: secondaryColor, label: legendSecondary!),
          ],
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      );
}
