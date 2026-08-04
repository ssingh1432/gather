import 'package:flutter/material.dart';

import '../data/repositories.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/reusables.dart';
import 'community_theme.dart';

/// Community Analytics (Step 13): member growth, daily active members,
/// retention, popular posts, moderator activity, and a composite health
/// score. Gated server-side by the `view_analytics` community permission —
/// a caller without it gets an access-denied state, not empty charts.
class CommunityAnalyticsScreen extends StatefulWidget {
  const CommunityAnalyticsScreen({super.key, required this.communityId, this.communityName});
  final String communityId;
  final String? communityName;

  @override
  State<CommunityAnalyticsScreen> createState() => _CommunityAnalyticsScreenState();
}

class _CommunityAnalyticsScreenState extends State<CommunityAnalyticsScreen> {
  final repo = CommunityRepository();
  bool _loading = true;
  bool _accessDenied = false;
  String? _error;

  Map<String, dynamic>? _health;
  List<Map<String, dynamic>> _growth = const [];
  List<Map<String, dynamic>> _dau = const [];
  List<Map<String, dynamic>> _retention = const [];
  List<Map<String, dynamic>> _popularPosts = const [];
  List<Map<String, dynamic>> _modActivity = const [];

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
        repo.communityHealthScore(widget.communityId),
        repo.communityMemberGrowth(widget.communityId, daysBack: 14),
        repo.communityDailyActiveMembers(widget.communityId, daysBack: 14),
        repo.communityRetention(widget.communityId),
        repo.communityPopularPosts(widget.communityId, daysBack: 30, limit: 5),
        repo.communityModeratorActivity(widget.communityId, daysBack: 30),
      ]);
      _health = results[0] as Map<String, dynamic>;
      _growth = results[1] as List<Map<String, dynamic>>;
      _dau = results[2] as List<Map<String, dynamic>>;
      _retention = results[3] as List<Map<String, dynamic>>;
      _popularPosts = results[4] as List<Map<String, dynamic>>;
      _modActivity = results[5] as List<Map<String, dynamic>>;
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('Not authorized')) {
        _accessDenied = true;
      } else {
        _error = 'Could not load analytics: $e';
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.communityName?.isNotEmpty == true ? '${widget.communityName} · Insights' : 'Community Insights',
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
                  message: "You need the community's analytics permission to view insights here — ask an owner or admin.",
                )
              : _error != null
                  ? Center(child: Text(_error!))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.all(CommunityTokens.spaceLg),
                        children: [
                          _HealthScoreCard(health: _health ?? const {}),
                          const SizedBox(height: CommunityTokens.spaceLg),
                          _SectionCard(
                            title: 'Member growth (14 days)',
                            child: _MiniBarChart(
                              labels: _growth.map((r) => (r['activity_date'] as String).substring(5)).toList(),
                              values: _growth.map((r) => (r['joins'] as num).toDouble()).toList(),
                              secondaryValues: _growth.map((r) => -(r['leaves'] as num).toDouble()).toList(),
                              legendPrimary: 'Joins',
                              legendSecondary: 'Leaves',
                            ),
                          ),
                          const SizedBox(height: CommunityTokens.spaceLg),
                          _SectionCard(
                            title: 'Daily active members (14 days)',
                            child: _MiniBarChart(
                              labels: _dau.map((r) => (r['activity_date'] as String).substring(5)).toList(),
                              values: _dau.map((r) => (r['active_members'] as num).toDouble()).toList(),
                              legendPrimary: 'Active members',
                            ),
                          ),
                          const SizedBox(height: CommunityTokens.spaceLg),
                          _SectionCard(
                            title: 'Retention',
                            child: Column(
                              children: _retention
                                  .map((r) => _RetentionRow(
                                        cohort: r['cohort'] as String,
                                        cohortSize: (r['cohort_size'] as num).toInt(),
                                        retainedCount: (r['retained_count'] as num).toInt(),
                                        retentionPct: (r['retention_pct'] as num).toDouble(),
                                      ))
                                  .toList(),
                            ),
                          ),
                          const SizedBox(height: CommunityTokens.spaceLg),
                          _SectionCard(
                            title: 'Popular posts (30 days)',
                            child: _popularPosts.isEmpty
                                ? Padding(
                                    padding: const EdgeInsets.all(CommunityTokens.spaceSm),
                                    child: Text('No posts in this window yet.', style: Theme.of(context).textTheme.bodySmall),
                                  )
                                : Column(
                                    children: [
                                      for (final p in _popularPosts)
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
                                                      (p['text_content'] as String?)?.trim().isNotEmpty == true ? p['text_content'] as String : '(media post)',
                                                      maxLines: 2,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      '${p['like_count']} likes · ${p['reply_count']} replies · ${p['view_count']} views',
                                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              CommunityStatChip(icon: Icons.trending_up, label: (p['engagement_score'] as num).toStringAsFixed(0), color: AppColors.brandTeal),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                          ),
                          const SizedBox(height: CommunityTokens.spaceLg),
                          _SectionCard(
                            title: 'Moderator activity (30 days)',
                            child: _modActivity.isEmpty
                                ? Padding(
                                    padding: const EdgeInsets.all(CommunityTokens.spaceSm),
                                    child: Text('No moderation actions in this window.', style: Theme.of(context).textTheme.bodySmall),
                                  )
                                : Column(
                                    children: [
                                      for (final m in _modActivity)
                                        Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 5),
                                          child: Row(
                                            children: [
                                              const Icon(Icons.shield_outlined, size: 18, color: AppColors.brandTeal),
                                              const SizedBox(width: 10),
                                              Expanded(child: Text('@${m['username'] ?? 'unknown'}')),
                                              CommunityStatChip(icon: Icons.bolt, label: '${m['action_count']} actions'),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                          ),
                          const SizedBox(height: CommunityTokens.spaceXl),
                        ],
                      ),
                    ),
    );
  }
}

class _HealthScoreCard extends StatelessWidget {
  const _HealthScoreCard({required this.health});
  final Map<String, dynamic> health;

  Color _scoreColor(double score) {
    if (score >= 70) return Colors.green;
    if (score >= 40) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final score = (health['health_score'] as num?)?.toDouble() ?? 0;
    final color = _scoreColor(score);
    return Container(
      decoration: BoxDecoration(
        color: CommunityColors.surfaceCard(context),
        borderRadius: BorderRadius.circular(CommunityTokens.radiusMd),
        border: Border.all(color: CommunityColors.border(context)),
        boxShadow: CommunityTokens.cardShadow(context),
      ),
      padding: const EdgeInsets.all(CommunityTokens.spaceLg),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.14)),
            alignment: Alignment.center,
            child: Text(score.toStringAsFixed(0), style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 20)),
          ),
          const SizedBox(width: CommunityTokens.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Community health', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: CommunityTokens.spaceSm),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    CommunityStatChip(icon: Icons.bolt, label: '${health['dau_today'] ?? 0} active today'),
                    CommunityStatChip(icon: Icons.forum_outlined, label: '${health['posts_last_7d'] ?? 0} posts this week'),
                    CommunityStatChip(icon: Icons.flag_outlined, label: '${health['open_reports'] ?? 0} open reports'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
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
          color: CommunityColors.surfaceCard(context),
          borderRadius: BorderRadius.circular(CommunityTokens.radiusMd),
          border: Border.all(color: CommunityColors.border(context)),
        ),
        padding: const EdgeInsets.all(CommunityTokens.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: CommunityTokens.spaceMd),
            child,
          ],
        ),
      );
}

class _RetentionRow extends StatelessWidget {
  const _RetentionRow({required this.cohort, required this.cohortSize, required this.retainedCount, required this.retentionPct});
  final String cohort;
  final int cohortSize;
  final int retainedCount;
  final double retentionPct;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(cohort),
                Text('$retainedCount / $cohortSize · ${retentionPct.toStringAsFixed(0)}%'),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(CommunityTokens.radiusPill),
              child: LinearProgressIndicator(
                value: (retentionPct / 100).clamp(0, 1),
                minHeight: 6,
                backgroundColor: CommunityColors.surfaceMuted(context),
                valueColor: const AlwaysStoppedAnimation(AppColors.brandTeal),
              ),
            ),
          ],
        ),
      );
}

/// A minimal, dependency-free bar chart. [secondaryValues], if given, are
/// rendered as downward bars beneath the baseline (used for "leaves" next
/// to "joins" in the member-growth chart).
class _MiniBarChart extends StatelessWidget {
  const _MiniBarChart({required this.labels, required this.values, this.secondaryValues, required this.legendPrimary, this.legendSecondary});
  final List<String> labels;
  final List<double> values;
  final List<double>? secondaryValues;
  final String legendPrimary;
  final String? legendSecondary;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return Padding(padding: const EdgeInsets.all(CommunityTokens.spaceSm), child: Text('No data yet.', style: Theme.of(context).textTheme.bodySmall));
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
        Row(
          children: labels
              .map((l) => Expanded(child: Text(l, textAlign: TextAlign.center, style: const TextStyle(fontSize: 9))))
              .toList(),
        ),
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
