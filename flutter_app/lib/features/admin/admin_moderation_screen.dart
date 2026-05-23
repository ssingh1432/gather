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
  bool _loading = true;
  String? _error;
  bool _allowed = false;
  List<Map<String, dynamic>> _reports = const [];

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uid = SupabaseConfig.client.auth.currentUser?.id;
      if (uid == null) {
        _allowed = false;
        _reports = const [];
      } else {
        final me = await SupabaseConfig.client.from('users').select().eq('id', uid).single();
        _allowed = ['admin', 'moderator'].contains(me['role']);
        _reports = _allowed ? await repo.openReports() : const [];
      }
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _actOnReport(Map<String, dynamic> report, Future<void> Function() action, String successMessage) async {
    try {
      await action();
      await repo.resolveReport(report['id'].toString());
      await _loadReports();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Action failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_error != null) return Scaffold(appBar: AppBar(title: const Text('Moderation')), body: Center(child: Text('Error: $_error')));
    if (!_allowed) return const Scaffold(body: Center(child: Text('Access denied')));

    return Scaffold(
      appBar: AppBar(title: const Text('Moderation')),
      body: _reports.isEmpty
          ? const Center(child: Text('No open reports'))
          : RefreshIndicator(
              onRefresh: _loadReports,
              child: ListView(
                children: _reports
                    .map((e) => ListTile(
                          title: Text(e['reason']?.toString() ?? 'No reason'),
                          subtitle: Text(e['target_type']?.toString() ?? 'Unknown target'),
                          trailing: Wrap(
                            children: [
                              IconButton(
                                onPressed: e['target_post_id'] == null
                                    ? null
                                    : () => _actOnReport(e, () => repo.removePost(e['target_post_id'].toString()), 'Post removed and report resolved'),
                                icon: const Icon(Icons.delete),
                              ),
                              IconButton(
                                onPressed: e['target_user_id'] == null
                                    ? null
                                    : () => _actOnReport(e, () => repo.banUser(e['target_user_id'].toString()), 'User banned and report resolved'),
                                icon: const Icon(Icons.block),
                              )
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ),
    );
  }
}
