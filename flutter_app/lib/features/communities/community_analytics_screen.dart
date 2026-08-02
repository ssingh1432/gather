import 'package:flutter/material.dart';

import '../data/repositories.dart';
import '../../shared/widgets/reusables.dart';

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
        title: Text(widget.communityName?.isNotEmpty == true ? '${widget.communityName} · Insights' : 'Community Insights'),
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
                        padding: const EdgeInsets.all(12),
                        children: [
                          _HealthScoreCard(health: _health ?? const {}),
                          const SizedBox(height: 16),
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
                          const SizedBox(height: 16),
                          _SectionCard(
                            title: 'Daily active members (14 days)',
                            child: _MiniBarChart(
                              labels: _dau.map((r) => (r['activity_date'] as String).substring(5)).toList(),
                              values: _dau.map((r) => (r['active_members'] as num).toDouble()).toList(),
                              legendPrimary: 'Active members',
                            ),
                          ),
                          const SizedBox(height: 16),
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
                          const SizedBox(height: 16),
                          _SectionCard(
                            title: 'Popular posts (30 days)',
                            child: _popularPosts.isEmpty
                                ? const Padding(padding: EdgeInsets.all(8), child: Text('No posts in this window yet.'))
                                : Column(
                                    children: _popularPosts
                                        .map((p) => ListTile(
                                              contentPadding: EdgeInsets.zero,
                                              title: Text(
                                                (p['text_content'] as String?)?.trim().isNotEmpty == true ? p['text_content'] as String : '(media post)',
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              subtitle: Text('${p['like_count']} likes · ${p['reply_count']} replies · ${p['view_count']} views'),
                                              trailing: Text(
                                                (p['engagement_score'] as num).toStringAsFixed(0),
                                                style: const TextStyle(fontWeight: FontWeight.bold),
                                              ),
                                            ))
                                        .toList(),
                                  ),
                          ),
                          const SizedBox(height: 16),
                          _SectionCard(
                            title: 'Moderator activity (30 days)',
                            child: _modActivity.isEmpty
                                ? const Padding(padding: EdgeInsets.all(8), child: Text('No moderation actions in this window.'))
                                : Column(
                                    children: _modActivity
                                        .map((m) => ListTile(
                                              contentPadding: EdgeInsets.zero,
                                              leading: const Icon(Icons.shield_outlined),
                                              title: Text('@${m['username'] ?? 'unknown'}'),
                                              trailing: Text('${m['action_count']} actions', style: const TextStyle(fontWeight: FontWeight.w600)),
                                            ))
                                        .toList(),
                                  ),
                          ),
                          const SizedBox(height: 24),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: _scoreColor(score).withValues(alpha: 0.15),
              child: Text(score.toStringAsFixed(0), style: TextStyle(color: _scoreColor(score), fontWeight: FontWeight.bold, fontSize: 20)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Community health', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('${health['dau_today'] ?? 0} active today · ${health['posts_last_7d'] ?? 0} posts this week · ${health['open_reports'] ?? 0} open reports'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              child,
            ],
          ),
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
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: (retentionPct / 100).clamp(0, 1), minHeight: 6),
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
    if (values.isEmpty) return const Padding(padding: EdgeInsets.all(8), child: Text('No data yet.'));
    final maxVal = [...values, ...(secondaryValues ?? const [])].map((v) => v.abs()).fold<double>(1, (a, b) => a > b ? a : b);
    final primaryColor = Theme.of(context).colorScheme.primary;
    final secondaryColor = Theme.of(context).colorScheme.error;

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
