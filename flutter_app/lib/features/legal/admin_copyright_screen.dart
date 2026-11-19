import 'package:flutter/material.dart';

import '../../core/supabase_client.dart';
import '../../shared/widgets/reusables.dart';
import 'copyright_repository.dart';
import 'my_copyright_screen.dart' show copyrightStatusLabel;

/// Staff queue for copyright notices and counter-notices (migration 130).
/// Client-side role gate mirrors AdminLegalDashboardScreen; the RPCs and RLS
/// enforce the real authorization.
class AdminCopyrightScreen extends StatefulWidget {
  const AdminCopyrightScreen({super.key});

  @override
  State<AdminCopyrightScreen> createState() => _AdminCopyrightScreenState();
}

class _AdminCopyrightScreenState extends State<AdminCopyrightScreen> with SingleTickerProviderStateMixin {
  final _repo = CopyrightRepository();
  late final TabController _tabs = TabController(length: 2, vsync: this);

  bool _loading = true;
  bool _allowed = false;
  List<Map<String, dynamic>> _notices = const [];
  List<Map<String, dynamic>> _counters = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final uid = SupabaseConfig.currentUserId;
      if (uid != null) {
        final me = await SupabaseConfig.client.from('users').select('role').eq('id', uid).single();
        _allowed = ['admin', 'moderator'].contains(me['role']);
      }
      if (_allowed) {
        final results = await Future.wait([_repo.notices(), _repo.counterNotices()]);
        _notices = results[0];
        _counters = results[1].where((c) => c['status'] == 'submitted').toList();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<String?> _askNotes(String title) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Reviewer notes (optional)', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(controller.text), child: const Text('Confirm')),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _resolveNotice(String id, String action, String title) async {
    final notes = action == 'review' ? '' : await _askNotes(title);
    if (notes == null) return;
    try {
      await _repo.resolveNotice(id, action, notes: notes);
      await _load();
    } catch (e) {
      if (mounted) _toast(CopyrightFormValidator.friendlyError(e));
    }
  }

  Future<void> _resolveCounter(String id, {required bool restore}) async {
    final notes = await _askNotes(restore ? 'Restore the content?' : 'Keep the content removed?');
    if (notes == null) return;
    try {
      await _repo.resolveCounterNotice(id, restore: restore, notes: notes);
      await _load();
    } catch (e) {
      if (mounted) _toast(CopyrightFormValidator.friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(appBar: AppBar(title: const Text('Copyright notices')), body: const Center(child: CircularProgressIndicator()));
    }
    if (!_allowed) {
      return Scaffold(
        appBar: AppBar(title: const Text('Copyright notices')),
        body: const EmptyState(icon: Icons.lock_outline, title: 'Staff only', message: 'You do not have access to this page.'),
      );
    }
    final open = _notices.where((n) => n['status'] == 'submitted' || n['status'] == 'under_review').toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Copyright notices'),
        bottom: TabBar(controller: _tabs, tabs: [
          Tab(text: 'Notices (${open.length} open)'),
          Tab(text: 'Counter-notices (${_counters.length})'),
        ]),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _NoticeList(rows: _notices, onResolve: _resolveNotice),
          _CounterList(rows: _counters, onResolve: _resolveCounter),
        ],
      ),
    );
  }
}

class _NoticeList extends StatelessWidget {
  const _NoticeList({required this.rows, required this.onResolve});

  final List<Map<String, dynamic>> rows;
  final Future<void> Function(String id, String action, String title) onResolve;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const EmptyState(icon: Icons.copyright_outlined, title: 'No notices', message: 'Nothing has been filed yet.');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final n = rows[i];
        final id = n['id'] as String;
        final status = (n['status'] as String?) ?? 'submitted';
        final open = status == 'submitted' || status == 'under_review';
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: Text('${n['claimant_name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700))),
                  Chip(label: Text(copyrightStatusLabel(status))),
                ]),
                Text('${n['claimant_email'] ?? ''}'),
                const SizedBox(height: 6),
                Text((n['work_description'] as String?) ?? ''),
                if ((n['original_work_url'] as String?)?.isNotEmpty ?? false) Text('Original: ${n['original_work_url']}'),
                if ((n['infringing_url'] as String?)?.isNotEmpty ?? false) Text('Reported link: ${n['infringing_url']}'),
                if (n['target_post_id'] != null) Text('Post: ${n['target_post_id']}'),
                if (open)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(spacing: 8, runSpacing: 8, children: [
                      if (status == 'submitted')
                        OutlinedButton(onPressed: () => onResolve(id, 'review', ''), child: const Text('Start review')),
                      FilledButton(onPressed: () => onResolve(id, 'remove', 'Remove the content?'), child: const Text('Remove content')),
                      OutlinedButton(onPressed: () => onResolve(id, 'reject', 'Reject this notice?'), child: const Text('Reject')),
                    ]),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CounterList extends StatelessWidget {
  const _CounterList({required this.rows, required this.onResolve});

  final List<Map<String, dynamic>> rows;
  final Future<void> Function(String id, {required bool restore}) onResolve;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const EmptyState(icon: Icons.balance_outlined, title: 'No open counter-notices', message: 'Counter-notices awaiting review appear here.');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final c = rows[i];
        final id = c['id'] as String;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text((c['statement'] as String?) ?? ''),
                const SizedBox(height: 4),
                Text('Signed: ${c['signature'] ?? ''}'),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    FilledButton(onPressed: () => onResolve(id, restore: true), child: const Text('Restore content')),
                    OutlinedButton(onPressed: () => onResolve(id, restore: false), child: const Text('Keep removed')),
                  ]),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
