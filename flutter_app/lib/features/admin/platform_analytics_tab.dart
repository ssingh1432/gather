import 'package:flutter/material.dart';

import '../data/repositories.dart';

/// Phase 15: platform-wide analytics for admins/moderators.
///
/// Data comes from the `admin_*` analytics RPCs (migration 125). Each section
/// loads independently, so one failing query never blanks the whole page.
/// Charts always have a text alternative (a summary label plus an expandable
/// data table) so the dashboard is usable with a screen reader.
class PlatformAnalyticsTab extends StatefulWidget {
  const PlatformAnalyticsTab({super.key, required this.repo});
  final AdminRepository repo;

  @override
  State<PlatformAnalyticsTab> createState() => _PlatformAnalyticsTabState();
}

class _Res<T> {
  const _Res.ok(this.data) : error = null;
  const _Res.err(this.error) : data = null;
  final T? data;
  final String? error;
}

Future<_Res<T>> _guard<T>(Future<T> Function() f) async {
  try {
    return _Res.ok(await f());
  } catch (e) {
    return _Res.err('$e');
  }
}

class _PlatformAnalyticsTabState extends State<PlatformAnalyticsTab> {
  int _days = 30;
  bool _loading = true;

  _Res<Map<String, dynamic>>? _kpis;
  _Res<List<Map<String, dynamic>>>? _series;
  _Res<List<Map<String, dynamic>>>? _cohorts;
  _Res<Map<String, dynamic>>? _engagement;
  _Res<Map<String, dynamic>>? _moderation;
  _Res<List<Map<String, dynamic>>>? _uploads;
  _Res<Map<String, dynamic>>? _crashes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final repo = widget.repo;
    final results = await Future.wait<Object>([
      _guard(repo.platformKpis),
      _guard(() => repo.activitySeries(days: _days)),
      _guard(() => repo.retentionCohorts(weeks: 8)),
      _guard(() => repo.engagementSummary(days: _days)),
      _guard(() => repo.moderationAnalytics(days: _days)),
      _guard(() => repo.uploadsSeries(days: _days)),
      _guard(() => repo.crashAnalytics(days: _days < 14 ? 14 : _days)),
    ]);
    if (!mounted) return;
    setState(() {
      _kpis = results[0] as _Res<Map<String, dynamic>>;
      _series = results[1] as _Res<List<Map<String, dynamic>>>;
      _cohorts = results[2] as _Res<List<Map<String, dynamic>>>;
      _engagement = results[3] as _Res<Map<String, dynamic>>;
      _moderation = results[4] as _Res<Map<String, dynamic>>;
      _uploads = results[5] as _Res<List<Map<String, dynamic>>>;
      _crashes = results[6] as _Res<Map<String, dynamic>>;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _kpis == null) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _rangePicker(),
          const SizedBox(height: 12),
          _kpiSection(),
          _sectionTitle('Daily & monthly active users'),
          _activityChart(),
          _sectionTitle('Retention (weekly signup cohorts)'),
          _retentionTable(),
          _sectionTitle('Engagement · last $_days days'),
          _engagementCard(),
          _sectionTitle('Moderation · last $_days days'),
          _moderationCard(),
          _sectionTitle('Uploads & storage growth'),
          _uploadsCard(),
          _sectionTitle('Crashes & errors'),
          _crashCard(),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ UI bits

  Widget _rangePicker() => Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 8,
              children: [
                for (final d in const [7, 30, 90])
                  ChoiceChip(
                    label: Text('$d days'),
                    selected: _days == d,
                    onSelected: (_) {
                      if (_days == d) return;
                      setState(() => _days = d);
                      _load();
                    },
                  ),
              ],
            ),
          ),
          IconButton(tooltip: 'Refresh analytics', onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      );

  Widget _sectionTitle(String t) => Semantics(
        header: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 24, 0, 8),
          child: Text(t, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        ),
      );

  Widget _errorBox(String? e) => Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          'Could not load this section: $e',
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      );

  Widget _kpiSection() {
    final r = _kpis;
    if (r == null) return const SizedBox.shrink();
    if (r.error != null) return _errorBox(r.error);
    final k = r.data!;
    final growth = k['user_growth_pct_30d'];
    final cards = <(String, String, String?)>[
      ('DAU (today)', _n(k['dau']), 'Yesterday ${_n(k['dau_yesterday'])}'),
      ('WAU (7d)', _n(k['wau']), null),
      ('MAU (30d)', _n(k['mau']), 'Prev. 30d ${_n(k['mau_previous_30d'])}'),
      ('Stickiness (DAU/MAU)', '${_n(k['stickiness_pct'])}%', null),
      ('Total users', _n(k['total_users']), 'Today +${_n(k['new_users_today'])}'),
      ('New users (30d)', _n(k['new_users_30d']), growth == null ? 'No prior period' : '${_n(growth)}% vs prior 30d'),
      ('Posts (24h)', _n(k['posts_24h']), null),
      ('Comments (24h)', _n(k['comments_24h']), null),
      ('Likes (24h)', _n(k['likes_24h']), null),
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [for (final c in cards) _KpiCard(label: c.$1, value: c.$2, caption: c.$3)],
    );
  }

  Widget _activityChart() {
    final r = _series;
    if (r == null) return const SizedBox.shrink();
    if (r.error != null) return _errorBox(r.error);
    final rows = r.data!;
    if (rows.isEmpty) return const Text('No activity yet.');
    final dau = [for (final e in rows) _d(e['dau'])];
    final mau = [for (final e in rows) _d(e['mau_rolling'])];
    final peakDau = dau.reduce((a, b) => a > b ? a : b).round();
    final latestMau = mau.last.round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: 'Line chart of daily active users and rolling 30-day monthly active users over ${rows.length} days. '
              'Peak daily active users $peakDau. Latest monthly active users $latestMau. Full data is available in the table below.',
          child: ExcludeSemantics(
            child: SizedBox(
              height: 180,
              child: _LineChart(
                series: [
                  _ChartSeries('DAU', dau, Theme.of(context).colorScheme.primary),
                  _ChartSeries('MAU (rolling 30d)', mau, Theme.of(context).colorScheme.tertiary),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Wrap(spacing: 16, children: [
          _Legend('DAU', primary: true),
          _Legend('MAU (rolling 30d)', primary: false),
        ]),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('View data table'),
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Date')),
                  DataColumn(label: Text('DAU'), numeric: true),
                  DataColumn(label: Text('MAU'), numeric: true),
                  DataColumn(label: Text('New users'), numeric: true),
                  DataColumn(label: Text('Posts'), numeric: true),
                  DataColumn(label: Text('Comments'), numeric: true),
                  DataColumn(label: Text('Likes'), numeric: true),
                  DataColumn(label: Text('Reports'), numeric: true),
                ],
                rows: [
                  for (final e in rows.reversed.take(31))
                    DataRow(cells: [
                      DataCell(Text('${e['activity_date']}')),
                      DataCell(Text(_n(e['dau']))),
                      DataCell(Text(_n(e['mau_rolling']))),
                      DataCell(Text(_n(e['new_users']))),
                      DataCell(Text(_n(e['post_count']))),
                      DataCell(Text(_n(e['comment_count']))),
                      DataCell(Text(_n(e['like_count']))),
                      DataCell(Text(_n(e['report_count']))),
                    ]),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _retentionTable() {
    final r = _cohorts;
    if (r == null) return const SizedBox.shrink();
    if (r.error != null) return _errorBox(r.error);
    final rows = r.data!;
    if (rows.isEmpty) return const Text('No signups in this period.');
    String pct(dynamic retained, dynamic eligible) {
      final e = _d(eligible);
      if (e == 0) return '–';
      return '${(100 * _d(retained) / e).toStringAsFixed(0)}%';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Cohort week')),
              DataColumn(label: Text('Users'), numeric: true),
              DataColumn(label: Text('Day 1'), numeric: true),
              DataColumn(label: Text('Day 7'), numeric: true),
              DataColumn(label: Text('Day 30'), numeric: true),
            ],
            rows: [
              for (final e in rows)
                DataRow(cells: [
                  DataCell(Text('${e['cohort_week']}')),
                  DataCell(Text(_n(e['cohort_size']))),
                  DataCell(Text(pct(e['d1_retained'], e['d1_eligible']))),
                  DataCell(Text(pct(e['d7_retained'], e['d7_eligible']))),
                  DataCell(Text(pct(e['d30_retained'], e['d30_eligible']))),
                ]),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Day-N retention = share of a cohort that was active exactly N days after signup. '
          '"–" means no user in that cohort has reached day N yet.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _engagementCard() {
    final r = _engagement;
    if (r == null) return const SizedBox.shrink();
    if (r.error != null) return _errorBox(r.error);
    final e = r.data!;
    return _KeyValueCard(rows: [
      ('Active users', _n(e['active_users'])),
      ('Engaged users (posted, commented or liked)', _n(e['engaged_users'])),
      ('Engagement rate', '${_n(e['engagement_rate_pct'])}%'),
      ('Posts', _n(e['posts'])),
      ('Comments', _n(e['comments'])),
      ('Likes', _n(e['likes'])),
      ('Actions per active user', _n(e['actions_per_active_user'])),
      ('Feed views / no interaction', '${_n(e['feed_views'])} / ${_n(e['feed_no_interaction'])}'),
      ('Post creation started / abandoned', '${_n(e['post_creation_started'])} / ${_n(e['post_creation_abandoned'])}'),
      ..._mapRows('Active users on', e['users_by_platform']),
    ]);
  }

  Widget _moderationCard() {
    final r = _moderation;
    if (r == null) return const SizedBox.shrink();
    if (r.error != null) return _errorBox(r.error);
    final m = r.data!;
    return _KeyValueCard(rows: [
      ('Reports received', _n(m['reports_total'])),
      ('Open reports (all time)', _n(m['reports_open'])),
      ('Auto-generated reports', _n(m['reports_automated'])),
      ('Posts removed', _n(m['posts_removed'])),
      ('Avg. appeal review time', m['avg_appeal_review_hours'] == null ? '–' : '${_n(m['avg_appeal_review_hours'])} h'),
      ..._mapRows('Reports · status', m['reports_by_status']),
      ..._mapRows('Reports · category', m['reports_by_category']),
      ..._mapRows('Actions', m['actions_by_type']),
      ..._mapRows('Appeals', m['appeals_by_status']),
    ]);
  }

  Widget _uploadsCard() {
    final r = _uploads;
    if (r == null) return const SizedBox.shrink();
    if (r.error != null) return _errorBox(r.error);
    final rows = r.data!;
    if (rows.isEmpty) return const Text('No uploads in this period.');
    final counts = [for (final e in rows) _d(e['upload_count'])];
    final totalCount = counts.fold<double>(0, (a, b) => a + b).round();
    final totalBytes = rows.fold<double>(0, (a, e) => a + _d(e['upload_bytes']));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$totalCount uploads · ${_bytes(totalBytes)} in the last $_days days'),
        const SizedBox(height: 8),
        Semantics(
          label: 'Line chart of uploads per day. $totalCount uploads in total.',
          child: ExcludeSemantics(
            child: SizedBox(
              height: 120,
              child: _LineChart(series: [_ChartSeries('Uploads', counts, Theme.of(context).colorScheme.primary)]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _crashCard() {
    final r = _crashes;
    if (r == null) return const SizedBox.shrink();
    if (r.error != null) return _errorBox(r.error);
    final c = r.data!;
    final top = (c['top_errors'] as List?) ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _KeyValueCard(rows: [
          ('Window', '${_n(c['window_days'])} days'),
          ('Errors logged', _n(c['total_errors'])),
          ('Affected users', _n(c['affected_users'])),
          ..._mapRows('Platform', c['by_platform']),
          ..._mapRows('App version', c['by_version']),
        ]),
        if (top.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Top errors', style: Theme.of(context).textTheme.titleSmall),
          for (final e in top)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('${(e as Map)['message']}', maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text('${_n(e['count'])} occurrences · ${_n(e['users'])} users'),
            ),
        ],
      ],
    );
  }

  // ----------------------------------------------------------------- helpers

  List<(String, String)> _mapRows(String prefix, dynamic map) {
    if (map is! Map || map.isEmpty) return const [];
    final entries = map.entries.toList()
      ..sort((a, b) => _d(b.value).compareTo(_d(a.value)));
    return [for (final e in entries) ('$prefix: ${e.key}', _n(e.value))];
  }
}

double _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

String _n(dynamic v) {
  if (v == null) return '–';
  final d = _d(v);
  final isInt = d == d.roundToDouble();
  final text = isInt ? d.toStringAsFixed(0) : d.toStringAsFixed(1);
  final parts = text.split('.');
  final whole = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return parts.length > 1 ? '$whole.${parts[1]}' : whole;
}

String _bytes(double b) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = b;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(i == 0 ? 0 : 1)} ${units[i]}';
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.label, required this.value, this.caption});
  final String label;
  final String value;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      label: '$label: $value${caption == null ? '' : '. $caption'}',
      excludeSemantics: true,
      child: SizedBox(
        width: 190,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: t.headlineSmall),
                const SizedBox(height: 2),
                Text(label, style: t.bodyMedium),
                if (caption != null) Text(caption!, style: t.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _KeyValueCard extends StatelessWidget {
  const _KeyValueCard({required this.rows});
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Column(
            children: [
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Text(r.$1)),
                      const SizedBox(width: 12),
                      Text(r.$2, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
}

class _Legend extends StatelessWidget {
  const _Legend(this.text, {required this.primary});
  final String text;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 14, height: 4, color: primary ? scheme.primary : scheme.tertiary),
      const SizedBox(width: 6),
      Text(text, style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}

class _ChartSeries {
  const _ChartSeries(this.name, this.values, this.color);
  final String name;
  final List<double> values;
  final Color color;
}

/// Minimal dependency-free line chart.
class _LineChart extends StatelessWidget {
  const _LineChart({required this.series});
  final List<_ChartSeries> series;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _LineChartPainter(
          series: series,
          gridColor: Theme.of(context).dividerColor,
          labelStyle: Theme.of(context).textTheme.bodySmall ?? const TextStyle(fontSize: 11),
        ),
        size: Size.infinite,
      );
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({required this.series, required this.gridColor, required this.labelStyle});
  final List<_ChartSeries> series;
  final Color gridColor;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 36.0;
    const bottom = 4.0;
    final plot = Rect.fromLTWH(left, 6, size.width - left - 4, size.height - 6 - bottom);
    var maxV = 1.0;
    var points = 0;
    for (final s in series) {
      points = s.values.length > points ? s.values.length : points;
      for (final v in s.values) {
        if (v > maxV) maxV = v;
      }
    }
    maxV = maxV.ceilToDouble();

    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 2; i++) {
      final y = plot.bottom - plot.height * (i / 2);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      final tp = TextPainter(
        text: TextSpan(text: _n(maxV * i / 2), style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(0, y - tp.height / 2));
    }

    for (final s in series) {
      if (s.values.isEmpty) continue;
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round;
      final path = Path();
      for (var i = 0; i < s.values.length; i++) {
        final x = s.values.length == 1 ? plot.center.dx : plot.left + plot.width * (i / (s.values.length - 1));
        final y = plot.bottom - plot.height * (s.values[i] / maxV);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
      if (s.values.length == 1) {
        canvas.drawCircle(Offset(plot.center.dx, plot.bottom - plot.height * (s.values[0] / maxV)), 3, Paint()..color = s.color);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter old) =>
      old.series != series || old.gridColor != gridColor || old.labelStyle != labelStyle;
}
