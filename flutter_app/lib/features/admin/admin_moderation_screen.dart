import 'package:flutter/material.dart';

import '../../core/supabase_client.dart';
import '../data/repositories.dart';

class AdminModerationScreen extends StatefulWidget {
  const AdminModerationScreen({super.key});

  @override
  State<AdminModerationScreen> createState() => _AdminModerationScreenState();
}

class _AdminModerationScreenState extends State<AdminModerationScreen> {
  final repo = ModerationRepository();
  final betaRepo = BetaOpsRepository();
  final monetizationRepo = MonetizationRepository();
  bool _loading = true;
  String? _error;
  bool _allowed = false;
  List<Map<String, dynamic>> _reports = const [];
  List<Map<String, dynamic>> _feedback = const [];
  List<Map<String, dynamic>> _pendingPayouts = const [];
  List<Map<String, dynamic>> _appeals = const [];
  List<Map<String, dynamic>> _keywordFilters = const [];
  List<Map<String, dynamic>> _mediaQueue = const [];
  List<Map<String, dynamic>> _pendingMediaQueue = const [];
  Map<String, dynamic> _summary = const {};

  @override
  void initState() {
    super.initState();
    _loadAdminData();
  }

  Future<void> _loadAdminData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uid = SupabaseConfig.client.auth.currentUser?.id;
      if (uid == null) {
        _allowed = false;
        _reports = const [];
        _feedback = const [];
      } else {
        final me = await SupabaseConfig.client.from('users').select().eq('id', uid).single();
        _allowed = ['admin', 'moderator'].contains(me['role']);
        if (_allowed) {
          _reports = await repo.openReports();
          _feedback = await betaRepo.feedback();
          _pendingPayouts = await monetizationRepo.pendingPayoutReviews();
          _appeals = await repo.pendingAppeals();
          _keywordFilters = await repo.keywordFilters();
          _mediaQueue = await repo.flaggedMedia();
          _pendingMediaQueue = await repo.pendingMediaQueue();
          _summary = await repo.dashboardSummary();
        } else {
          _reports = const [];
          _feedback = const [];
          _pendingPayouts = const [];
          _appeals = const [];
          _keywordFilters = const [];
          _mediaQueue = const [];
          _pendingMediaQueue = const [];
          _summary = const {};
        }
      }
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _actOnReport(Map<String, dynamic> report, Future<void> Function(String reportId) action, String successMessage, {bool resolve = true}) async {
    try {
      final reportId = report['id'].toString();
      await action(reportId);
      if (resolve) await repo.resolveReport(reportId);
      await _loadAdminData();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Action failed: $e')));
    }
  }

  Future<void> _reviewFeedback(Map<String, dynamic> feedback, {required String tag, required String status}) async {
    try {
      await betaRepo.reviewFeedback(feedback['id'].toString(), tag: tag, status: status);
      await _loadAdminData();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Feedback updated')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Feedback update failed: $e')));
    }
  }

  Future<void> _reviewPayout(Map<String, dynamic> payout, String status) async {
    try {
      await monetizationRepo.reviewPayout(userId: payout['user_id'].toString(), status: status);
      await _loadAdminData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(status == 'approved' ? 'Payout approved — ads enabled' : 'Payout rejected')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Review failed: $e')));
    }
  }

  Future<int?> _promptDurationDays(BuildContext context) => showDialog<int>(
        context: context,
        builder: (ctx) {
          final options = {'1 day': 1, '3 days': 3, '7 days': 7, '14 days': 14, '30 days': 30, 'Indefinite': null};
          return SimpleDialog(
            title: const Text('Suspend for how long?'),
            children: options.entries
                .map((e) => SimpleDialogOption(onPressed: () => Navigator.pop(ctx, e.value ?? -1), child: Text(e.key)))
                .toList(),
          );
        },
      );

  Future<void> _reviewAppeal(Map<String, dynamic> appeal, String decision) async {
    try {
      await repo.reviewAppeal(appeal['id'].toString(), decision);
      await _loadAdminData();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Appeal $decision')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Appeal review failed: $e')));
    }
  }

  Future<void> _addKeywordFilter() async {
    final keywordCtrl = TextEditingController();
    String severity = 'flag';
    String category = 'other';
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add keyword filter'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: keywordCtrl, decoration: const InputDecoration(labelText: 'Keyword')),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: ModerationRepository.reportCategories
                    .map((c) => DropdownMenuItem(value: c, child: Text(ModerationRepository.reportCategoryLabels[c]!)))
                    .toList(),
                onChanged: (v) => setDialogState(() => category = v ?? 'other'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: severity,
                decoration: const InputDecoration(labelText: 'Severity'),
                items: const [
                  DropdownMenuItem(value: 'flag', child: Text('Flag (auto-report for review)')),
                  DropdownMenuItem(value: 'block', child: Text('Block (reject the post/comment)')),
                ],
                onChanged: (v) => setDialogState(() => severity = v ?? 'flag'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
          ],
        ),
      ),
    );
    if (result != true || keywordCtrl.text.trim().isEmpty) return;
    try {
      await repo.addKeywordFilter(keyword: keywordCtrl.text.trim(), category: category, severity: severity);
      await _loadAdminData();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Keyword filter added')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to add filter: $e')));
    }
  }

  Future<void> _removeKeywordFilter(String id) async {
    try {
      await repo.removeKeywordFilter(id);
      await _loadAdminData();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to remove filter: $e')));
    }
  }

  Future<void> _reviewMedia(Map<String, dynamic> flag, String status) async {
    try {
      await repo.recordMediaModerationResult(flag['id'].toString(), status);
      await _loadAdminData();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Media marked $status')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Review failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_error != null) return Scaffold(appBar: AppBar(title: const Text('Moderation')), body: Center(child: Text('Error: $_error')));
    if (!_allowed) return const Scaffold(body: Center(child: Text('Access denied')));

    return DefaultTabController(
      length: 7,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_summary.isEmpty
              ? 'Moderation'
              : 'Moderation — ${_summary['open_reports'] ?? 0} open • ${_summary['suspended_users'] ?? 0} suspended • ${_summary['banned_users'] ?? 0} banned'),
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: _reports.isEmpty ? 'Reports' : 'Reports (${_reports.length})'),
              Tab(text: _appeals.isEmpty ? 'Appeals' : 'Appeals (${_appeals.length})'),
              Tab(text: _mediaQueue.isEmpty ? 'Media queue' : 'Media queue (${_mediaQueue.length})'),
              const Tab(text: 'Keyword filters'),
              const Tab(text: 'Beta feedback'),
              Tab(text: _pendingPayouts.isEmpty ? 'Payouts' : 'Payouts (${_pendingPayouts.length})'),
              const Tab(text: 'Look up user'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _ReportsList(reports: _reports, repo: repo, onRefresh: _loadAdminData, onActOnReport: _actOnReport, promptDuration: _promptDurationDays),
            _AppealsList(appeals: _appeals, onReview: _reviewAppeal, onRefresh: _loadAdminData),
            _MediaQueueList(flagged: _mediaQueue, pending: _pendingMediaQueue, onReview: _reviewMedia, onRefresh: _loadAdminData),
            _KeywordFilterList(filters: _keywordFilters, onAdd: _addKeywordFilter, onRemove: _removeKeywordFilter, onRefresh: _loadAdminData),
            _BetaFeedbackList(feedback: _feedback, onRefresh: _loadAdminData, onReview: _reviewFeedback),
            _PayoutReviewList(payouts: _pendingPayouts, onRefresh: _loadAdminData, onReview: _reviewPayout),
            _UserLookupTab(repo: repo, promptDuration: _promptDurationDays),
          ],
        ),
      ),
    );
  }
}

class _ReportsList extends StatelessWidget {
  const _ReportsList({required this.reports, required this.repo, required this.onRefresh, required this.onActOnReport, required this.promptDuration});

  final List<Map<String, dynamic>> reports;
  final ModerationRepository repo;
  final Future<void> Function() onRefresh;
  final Future<void> Function(Map<String, dynamic>, Future<void> Function(String), String, {bool resolve}) onActOnReport;
  final Future<int?> Function(BuildContext) promptDuration;

  @override
  Widget build(BuildContext context) => reports.isEmpty
      ? const Center(child: Text('No open reports'))
      : RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView.separated(
            itemCount: reports.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final e = reports[index];
              final category = e['category']?.toString();
              final isAuto = e['is_automated'] == true;
              return ExpansionTile(
                title: Row(
                  children: [
                    Flexible(child: Text(e['reason']?.toString() ?? 'No reason')),
                    if (e['target_user_id'] != null) _StrikeBadge(repo: repo, userId: e['target_user_id'].toString()),
                  ],
                ),
                subtitle: Text([
                  if (category != null) ModerationRepository.reportCategoryLabels[category] ?? category,
                  e['target_type']?.toString() ?? 'Unknown target',
                  if (isAuto) 'auto-flagged',
                ].join(' • ')),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  _ReportDetailExtras(repo: repo, report: e),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (e['target_post_id'] != null)
                          ActionChip(
                            avatar: const Icon(Icons.delete, size: 18),
                            label: const Text('Remove post'),
                            onPressed: () => onActOnReport(
                              e,
                              (reportId) => repo.removePost(e['target_post_id'].toString(), reportId: reportId),
                              'Post removed and report resolved',
                            ),
                          ),
                        if (e['target_user_id'] != null) ...[
                          ActionChip(
                            avatar: const Icon(Icons.info_outline, size: 18),
                            label: const Text('Warn'),
                            onPressed: () => onActOnReport(
                              e,
                              (reportId) => repo.issueWarning(e['target_user_id'].toString(), reportId: reportId),
                              'Warning issued and report resolved',
                            ),
                          ),
                          ActionChip(
                            avatar: const Icon(Icons.flag, size: 18),
                            label: const Text('Add strike'),
                            onPressed: () => onActOnReport(
                              e,
                              (reportId) => repo.addStrike(e['target_user_id'].toString(), reportId: reportId),
                              'Strike added and report resolved',
                            ),
                          ),
                          ActionChip(
                            avatar: const Icon(Icons.pause_circle, size: 18),
                            label: const Text('Suspend'),
                            onPressed: () async {
                              final days = await promptDuration(context);
                              if (days == null) return;
                              await onActOnReport(
                                e,
                                (reportId) => repo.suspendUser(
                                  e['target_user_id'].toString(),
                                  reportId: reportId,
                                  durationDays: days == -1 ? null : days,
                                ),
                                'User suspended and report resolved',
                              );
                            },
                          ),
                          ActionChip(
                            avatar: const Icon(Icons.block, size: 18),
                            label: const Text('Ban'),
                            onPressed: () => onActOnReport(
                              e,
                              (reportId) => repo.banUser(e['target_user_id'].toString(), reportId: reportId),
                              'User banned and report resolved',
                            ),
                          ),
                        ],
                        ActionChip(
                          avatar: const Icon(Icons.check, size: 18),
                          label: const Text('Dismiss'),
                          onPressed: () => onActOnReport(e, (_) async {}, 'Report dismissed'),
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.note_add, size: 18),
                          label: const Text('Add note'),
                          onPressed: () async {
                            final noteCtrl = TextEditingController();
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Moderator note'),
                                content: TextField(controller: noteCtrl, maxLines: 3, decoration: const InputDecoration(hintText: 'Internal note (not visible to the user)')),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                  ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
                                ],
                              ),
                            );
                            if (ok == true && noteCtrl.text.trim().isNotEmpty) {
                              final targetType = e['target_post_id'] != null ? 'post' : 'user';
                              final targetId = e['target_post_id'] ?? e['target_user_id'];
                              await repo.addModeratorNote(targetType: targetType, targetId: targetId.toString(), note: noteCtrl.text.trim());
                              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Note saved')));
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        );
}

/// Evidence thumbnails + past moderator notes for one report's target,
/// shown inside its ExpansionTile above the action chips. Closes two of
/// the four "backend exists, no UI" gaps: evidence was previously
/// upload-only plumbing with no viewer, and notes could only be added,
/// never seen.
class _ReportDetailExtras extends StatefulWidget {
  const _ReportDetailExtras({required this.repo, required this.report});

  final ModerationRepository repo;
  final Map<String, dynamic> report;

  @override
  State<_ReportDetailExtras> createState() => _ReportDetailExtrasState();
}

class _ReportDetailExtrasState extends State<_ReportDetailExtras> {
  bool _loading = true;
  List<Map<String, dynamic>> _evidence = const [];
  Map<String, String> _signedUrls = const {};
  List<Map<String, dynamic>> _notes = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final reportId = widget.report['id'].toString();
      final targetUserId = widget.report['target_user_id']?.toString();
      final targetPostId = widget.report['target_post_id']?.toString();

      final results = await Future.wait([
        widget.repo.evidenceFor(reportId),
        widget.repo.moderatorNotesFor(targetUserId: targetUserId, targetPostId: targetPostId),
      ]);
      final evidence = results[0];
      final notes = results[1];

      // Evidence lives in a private bucket, so each file_url is a storage
      // path, not a viewable link — resolve one short-lived signed URL per
      // item. Failures here (e.g. a stale/deleted object) shouldn't block
      // showing the rest of the report, so they're just skipped.
      final urls = <String, String>{};
      for (final item in evidence) {
        final path = item['file_url']?.toString();
        if (path == null) continue;
        try {
          urls[path] = await widget.repo.evidenceSignedUrl(path);
        } catch (_) {
          // leave unresolved — thumbnail shows a placeholder instead
        }
      }

      if (mounted) {
        setState(() {
          _evidence = evidence;
          _notes = notes;
          _signedUrls = urls;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_evidence.isEmpty && _notes.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_evidence.isNotEmpty) ...[
          Text('Evidence (${_evidence.length})', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 6),
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _evidence.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final item = _evidence[i];
                final path = item['file_url']?.toString();
                final url = path == null ? null : _signedUrls[path];
                return GestureDetector(
                  onTap: url == null
                      ? null
                      : () => showDialog(
                            context: context,
                            builder: (_) => Dialog(child: InteractiveViewer(child: Image.network(url))),
                          ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: url == null
                        ? Container(width: 72, height: 72, color: Colors.grey.shade300, child: const Icon(Icons.broken_image))
                        : Image.network(url, width: 72, height: 72, fit: BoxFit.cover),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (_notes.isNotEmpty) ...[
          Text('Past moderator notes (${_notes.length})', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          ..._notes.map((n) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• ${n['note']} — ${n['created_at']}', style: Theme.of(context).textTheme.bodySmall),
              )),
        ],
      ],
    );
  }
}

/// Small "N strikes" chip next to a reported user's name, so a mod can see
/// escalation history before deciding an action — previously strike_count
/// was tracked and drove auto-escalation but was never shown anywhere.
class _StrikeBadge extends StatefulWidget {
  const _StrikeBadge({required this.repo, required this.userId});

  final ModerationRepository repo;
  final String userId;

  @override
  State<_StrikeBadge> createState() => _StrikeBadgeState();
}

class _StrikeBadgeState extends State<_StrikeBadge> {
  Map<String, dynamic>? _status;

  @override
  void initState() {
    super.initState();
    widget.repo.userStatus(widget.userId).then((s) {
      if (mounted) setState(() => _status = s);
    });
  }

  @override
  Widget build(BuildContext context) {
    final strikes = _status?['strike_count'] as int?;
    if (strikes == null || strikes == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Chip(
        label: Text('$strikes strike${strikes == 1 ? '' : 's'}'),
        visualDensity: VisualDensity.compact,
        backgroundColor: strikes >= 5 ? Colors.red.shade100 : Colors.orange.shade100,
        padding: EdgeInsets.zero,
      ),
    );
  }
}

/// Closes the last UI gap: mods could previously only warn/strike/suspend/
/// ban a user from inside an already-open report. This lets them act
/// directly — e.g. a repeat offender flagged from outside the app, or
/// evidence that arrived without a fresh report attached.
class _UserLookupTab extends StatefulWidget {
  const _UserLookupTab({required this.repo, required this.promptDuration});

  final ModerationRepository repo;
  final Future<int?> Function(BuildContext) promptDuration;

  @override
  State<_UserLookupTab> createState() => _UserLookupTabState();
}

class _UserLookupTabState extends State<_UserLookupTab> {
  final _queryCtrl = TextEditingController();
  List<Map<String, dynamic>> _results = const [];
  bool _searching = false;

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _queryCtrl.text.trim();
    if (q.isEmpty) return;
    setState(() => _searching = true);
    try {
      final results = await widget.repo.lookupUsers(q);
      if (mounted) setState(() => _results = results);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _act(Map<String, dynamic> user, Future<void> Function(String userId) action, String successMessage) async {
    try {
      await action(user['id'].toString());
      await _search(); // refresh this user's row (status/strikes) after acting
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Action failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _queryCtrl,
                  decoration: const InputDecoration(labelText: 'Search by username', border: OutlineInputBorder()),
                  onSubmitted: (_) => _search(),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(onPressed: _searching ? null : _search, child: const Text('Search')),
            ],
          ),
          const SizedBox(height: 16),
          if (_searching) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
          if (!_searching && _results.isEmpty && _queryCtrl.text.isNotEmpty) const Text('No users found.'),
          Expanded(
            child: ListView.separated(
              itemCount: _results.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final u = _results[i];
                final strikes = u['strike_count'] as int? ?? 0;
                final status = u['status']?.toString() ?? 'active';
                final suspendedUntil = u['suspended_until']?.toString();
                return ExpansionTile(
                  title: Text(u['username']?.toString() ?? u['email']?.toString() ?? 'Unknown'),
                  subtitle: Text([
                    'status: $status',
                    if (status == 'suspended' && suspendedUntil != null) 'until $suspendedUntil',
                    '$strikes strike${strikes == 1 ? '' : 's'}',
                    if (u['role'] != null && u['role'] != 'user') u['role'].toString(),
                  ].join(' • ')),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ActionChip(
                            avatar: const Icon(Icons.info_outline, size: 18),
                            label: const Text('Warn'),
                            onPressed: () => _act(u, (id) => widget.repo.issueWarning(id), 'Warning issued'),
                          ),
                          ActionChip(
                            avatar: const Icon(Icons.flag, size: 18),
                            label: const Text('Add strike'),
                            onPressed: () => _act(u, (id) => widget.repo.addStrike(id), 'Strike added'),
                          ),
                          ActionChip(
                            avatar: const Icon(Icons.pause_circle, size: 18),
                            label: const Text('Suspend'),
                            onPressed: () async {
                              final days = await widget.promptDuration(context);
                              if (days == null) return;
                              await _act(
                                u,
                                (id) => widget.repo.suspendUser(id, durationDays: days == -1 ? null : days),
                                'User suspended',
                              );
                            },
                          ),
                          ActionChip(
                            avatar: const Icon(Icons.block, size: 18),
                            label: const Text('Ban'),
                            onPressed: () => _act(u, (id) => widget.repo.banUser(id), 'User banned'),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AppealsList extends StatelessWidget {
  const _AppealsList({required this.appeals, required this.onReview, required this.onRefresh});

  final List<Map<String, dynamic>> appeals;
  final Future<void> Function(Map<String, dynamic>, String) onReview;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) => appeals.isEmpty
      ? const Center(child: Text('No pending appeals'))
      : RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView.separated(
            itemCount: appeals.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final a = appeals[index];
              final user = a['users'] as Map<String, dynamic>?;
              final action = a['moderation_actions'] as Map<String, dynamic>?;
              return ListTile(
                title: Text(a['message']?.toString() ?? ''),
                subtitle: Text('${user?['username'] ?? user?['email'] ?? a['user_id']} • appealing: ${action?['action'] ?? 'unknown action'}'),
                isThreeLine: true,
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    IconButton(
                      tooltip: 'Approve (reinstates the user)',
                      icon: const Icon(Icons.check_circle, color: Colors.green),
                      onPressed: () => onReview(a, 'approved'),
                    ),
                    IconButton(
                      tooltip: 'Deny',
                      icon: const Icon(Icons.cancel, color: Colors.red),
                      onPressed: () => onReview(a, 'denied'),
                    ),
                  ],
                ),
              );
            },
          ),
        );
}

/// Was flagged-only (auto-approve was the only path for new media, with no
/// way for a mod to manually flag something that slipped through). Now a
/// toggle between the two queues, with a manual "Flag" action added to the
/// pending list.
class _MediaQueueList extends StatefulWidget {
  const _MediaQueueList({required this.flagged, required this.pending, required this.onReview, required this.onRefresh});

  final List<Map<String, dynamic>> flagged;
  final List<Map<String, dynamic>> pending;
  final Future<void> Function(Map<String, dynamic>, String) onReview;
  final Future<void> Function() onRefresh;

  @override
  State<_MediaQueueList> createState() => _MediaQueueListState();
}

class _MediaQueueListState extends State<_MediaQueueList> {
  bool _showPending = false;

  @override
  Widget build(BuildContext context) {
    final items = _showPending ? widget.pending : widget.flagged;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: false, label: Text('Flagged (${widget.flagged.length})')),
              ButtonSegment(value: true, label: Text('Pending review (${widget.pending.length})')),
            ],
            selected: {_showPending},
            onSelectionChanged: (s) => setState(() => _showPending = s.first),
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? Center(child: Text(_showPending ? 'No media waiting on the auto-moderation hook' : 'No media flagged for review'))
              : RefreshIndicator(
                  onRefresh: widget.onRefresh,
                  child: ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final m = items[index];
                      return ListTile(
                        leading: Icon(m['media_type'] == 'video' ? Icons.videocam : Icons.image),
                        title: Text(m['media_url']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${m['media_type']} • ${_showPending ? 'uploaded' : 'flagged'} ${m['created_at']}'),
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            IconButton(
                              tooltip: 'Approve',
                              icon: const Icon(Icons.check_circle, color: Colors.green),
                              onPressed: () => widget.onReview(m, 'approved'),
                            ),
                            if (_showPending)
                              IconButton(
                                tooltip: 'Flag for review',
                                icon: const Icon(Icons.flag, color: Colors.orange),
                                onPressed: () => widget.onReview(m, 'flagged'),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

class _KeywordFilterList extends StatelessWidget {
  const _KeywordFilterList({required this.filters, required this.onAdd, required this.onRemove, required this.onRefresh});

  final List<Map<String, dynamic>> filters;
  final VoidCallback onAdd;
  final Future<void> Function(String) onRemove;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: ElevatedButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Add keyword filter')),
            ),
            if (filters.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No active keyword filters')),
            ...filters.map((f) => ListTile(
                  title: Text(f['keyword']?.toString() ?? ''),
                  subtitle: Text('${ModerationRepository.reportCategoryLabels[f['category']] ?? f['category']} • ${f['severity']}'),
                  trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => onRemove(f['id'].toString())),
                )),
          ],
        ),
      );
}

class _BetaFeedbackList extends StatelessWidget {
  const _BetaFeedbackList({required this.feedback, required this.onRefresh, required this.onReview});

  final List<Map<String, dynamic>> feedback;
  final Future<void> Function() onRefresh;
  final Future<void> Function(Map<String, dynamic>, {required String tag, required String status}) onReview;

  @override
  Widget build(BuildContext context) => feedback.isEmpty
      ? const Center(child: Text('No beta feedback yet'))
      : RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView.separated(
            itemCount: feedback.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = feedback[index];
              final user = item['users'] as Map<String, dynamic>?;
              return ExpansionTile(
                title: Text(item['message']?.toString() ?? 'No message', maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text('${item['kind']} • ${item['status']} • ${user?['email'] ?? item['user_id']}'),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  Align(alignment: Alignment.centerLeft, child: Text(item['message']?.toString() ?? '')),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Version ${item['app_version']} on ${item['platform']} • ${item['created_at']}'),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ActionChip(label: const Text('Tag bug'), onPressed: () => onReview(item, tag: 'bug', status: item['status']?.toString() ?? 'open')),
                      ActionChip(label: const Text('Tag UX'), onPressed: () => onReview(item, tag: 'ux', status: item['status']?.toString() ?? 'open')),
                      ActionChip(label: const Text('Tag feature'), onPressed: () => onReview(item, tag: 'feature_request', status: item['status']?.toString() ?? 'open')),
                      ActionChip(label: const Text('Resolve'), onPressed: () => onReview(item, tag: item['tag']?.toString() ?? 'ux', status: 'resolved')),
                      ActionChip(label: const Text('Ignore'), onPressed: () => onReview(item, tag: item['tag']?.toString() ?? 'ux', status: 'ignored')),
                    ],
                  ),
                ],
              );
            },
          ),
        );
}

class _PayoutReviewList extends StatelessWidget {
  const _PayoutReviewList({required this.payouts, required this.onRefresh, required this.onReview});

  final List<Map<String, dynamic>> payouts;
  final Future<void> Function() onRefresh;
  final Future<void> Function(Map<String, dynamic> payout, String status) onReview;

  static const _providerLabels = {'esewa': 'eSewa', 'khalti': 'Khalti', 'bank': 'Bank account'};

  @override
  Widget build(BuildContext context) => payouts.isEmpty
      ? const Center(child: Text('No payout preferences awaiting review'))
      : RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView.separated(
            itemCount: payouts.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final p = payouts[index];
              final user = p['users'] as Map<String, dynamic>?;
              final provider = _providerLabels[p['provider']] ?? p['provider']?.toString() ?? 'Unknown';
              return ListTile(
                title: Text('${user?['username'] ?? p['user_id']} — $provider'),
                subtitle: Text('Holder: ${p['holder_name']} • Ref: •••${p['masked_reference']}\n${user?['email'] ?? ''}'),
                isThreeLine: true,
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    IconButton(
                      tooltip: 'Approve',
                      onPressed: () => onReview(p, 'approved'),
                      icon: const Icon(Icons.check_circle, color: Colors.green),
                    ),
                    IconButton(
                      tooltip: 'Reject',
                      onPressed: () => onReview(p, 'rejected'),
                      icon: const Icon(Icons.cancel, color: Colors.red),
                    ),
                  ],
                ),
              );
            },
          ),
        );
}
