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
          _summary = await repo.dashboardSummary();
        } else {
          _reports = const [];
          _feedback = const [];
          _pendingPayouts = const [];
          _appeals = const [];
          _keywordFilters = const [];
          _mediaQueue = const [];
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
                value: category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: ModerationRepository.reportCategories
                    .map((c) => DropdownMenuItem(value: c, child: Text(ModerationRepository.reportCategoryLabels[c]!)))
                    .toList(),
                onChanged: (v) => setDialogState(() => category = v ?? 'other'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: severity,
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
      length: 6,
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
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _ReportsList(reports: _reports, repo: repo, onRefresh: _loadAdminData, onActOnReport: _actOnReport, promptDuration: _promptDurationDays),
            _AppealsList(appeals: _appeals, onReview: _reviewAppeal, onRefresh: _loadAdminData),
            _MediaQueueList(items: _mediaQueue, onReview: _reviewMedia, onRefresh: _loadAdminData),
            _KeywordFilterList(filters: _keywordFilters, onAdd: _addKeywordFilter, onRemove: _removeKeywordFilter, onRefresh: _loadAdminData),
            _BetaFeedbackList(feedback: _feedback, onRefresh: _loadAdminData, onReview: _reviewFeedback),
            _PayoutReviewList(payouts: _pendingPayouts, onRefresh: _loadAdminData, onReview: _reviewPayout),
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
                title: Text(e['reason']?.toString() ?? 'No reason'),
                subtitle: Text([
                  if (category != null) ModerationRepository.reportCategoryLabels[category] ?? category,
                  e['target_type']?.toString() ?? 'Unknown target',
                  if (isAuto) 'auto-flagged',
                ].join(' • ')),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
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

class _MediaQueueList extends StatelessWidget {
  const _MediaQueueList({required this.items, required this.onReview, required this.onRefresh});

  final List<Map<String, dynamic>> items;
  final Future<void> Function(Map<String, dynamic>, String) onReview;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) => items.isEmpty
      ? const Center(child: Text('No media flagged for review'))
      : RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final m = items[index];
              return ListTile(
                leading: Icon(m['media_type'] == 'video' ? Icons.videocam : Icons.image),
                title: Text(m['media_url']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${m['media_type']} • flagged ${m['created_at']}'),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    IconButton(
                      tooltip: 'Approve',
                      icon: const Icon(Icons.check_circle, color: Colors.green),
                      onPressed: () => onReview(m, 'approved'),
                    ),
                  ],
                ),
              );
            },
          ),
        );
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
