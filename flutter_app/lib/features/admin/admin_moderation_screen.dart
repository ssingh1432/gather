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
  bool _loading = true;
  String? _error;
  bool _allowed = false;
  List<Map<String, dynamic>> _reports = const [];
  List<Map<String, dynamic>> _feedback = const [];

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
        } else {
          _reports = const [];
          _feedback = const [];
        }
      }
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _actOnReport(Map<String, dynamic> report, Future<void> Function(String reportId) action, String successMessage) async {
    try {
      final reportId = report['id'].toString();
      await action(reportId);
      await repo.resolveReport(reportId);
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

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_error != null) return Scaffold(appBar: AppBar(title: const Text('Moderation')), body: Center(child: Text('Error: $_error')));
    if (!_allowed) return const Scaffold(body: Center(child: Text('Access denied')));

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Moderation'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Reports'),
              Tab(text: 'Beta feedback'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _ReportsList(reports: _reports, onRefresh: _loadAdminData, onActOnReport: _actOnReport),
            _BetaFeedbackList(feedback: _feedback, onRefresh: _loadAdminData, onReview: _reviewFeedback),
          ],
        ),
      ),
    );
  }
}

class _ReportsList extends StatelessWidget {
  const _ReportsList({required this.reports, required this.onRefresh, required this.onActOnReport});

  final List<Map<String, dynamic>> reports;
  final Future<void> Function() onRefresh;
  final Future<void> Function(Map<String, dynamic>, Future<void> Function(String), String) onActOnReport;

  @override
  Widget build(BuildContext context) => reports.isEmpty
      ? const Center(child: Text('No open reports'))
      : RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView(
            children: reports
                .map((e) => ListTile(
                      title: Text(e['reason']?.toString() ?? 'No reason'),
                      subtitle: Text(e['target_type']?.toString() ?? 'Unknown target'),
                      trailing: Wrap(
                        children: [
                          IconButton(
                            onPressed: e['target_post_id'] == null
                                ? null
                                : () => onActOnReport(
                                      e,
                                      (reportId) => ModerationRepository().removePost(e['target_post_id'].toString(), reportId: reportId),
                                      'Post removed and report resolved',
                                    ),
                            icon: const Icon(Icons.delete),
                          ),
                          IconButton(
                            onPressed: e['target_user_id'] == null
                                ? null
                                : () => onActOnReport(
                                      e,
                                      (reportId) => ModerationRepository().suspendUser(e['target_user_id'].toString(), reportId: reportId),
                                      'User suspended and report resolved',
                                    ),
                            icon: const Icon(Icons.pause_circle),
                          )
                        ],
                      ),
                    ))
                .toList(),
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
