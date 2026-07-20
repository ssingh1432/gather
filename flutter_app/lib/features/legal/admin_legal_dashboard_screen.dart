import 'package:flutter/material.dart';

import '../../core/supabase_client.dart';
import '../data/repositories.dart';

/// Admin-only dashboard for Phase 4 Nepal legal compliance: review
/// grievances/complaints, resolve appeals, approve identity verification,
/// and log law-enforcement/legal data requests. Gated the same way as
/// AdminModerationScreen — client-side role check backed by RLS.
class AdminLegalDashboardScreen extends StatefulWidget {
  const AdminLegalDashboardScreen({super.key});

  @override
  State<AdminLegalDashboardScreen> createState() => _AdminLegalDashboardScreenState();
}

class _AdminLegalDashboardScreenState extends State<AdminLegalDashboardScreen> with SingleTickerProviderStateMixin {
  final _repo = LegalRepository();
  late final TabController _tabs = TabController(length: 4, vsync: this);

  bool _loading = true;
  bool _allowed = false;
  List<Map<String, dynamic>> _complaints = const [];
  List<Map<String, dynamic>> _appeals = const [];
  List<Map<String, dynamic>> _verifications = const [];
  List<Map<String, dynamic>> _dataRequests = const [];

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
      if (uid == null) {
        _allowed = false;
      } else {
        final me = await SupabaseConfig.client.from('users').select('role').eq('id', uid).single();
        _allowed = ['admin', 'moderator'].contains(me['role']);
      }
      if (_allowed) {
        final results = await Future.wait([
          _repo.adminComplaints(),
          _repo.adminAppeals(),
          _repo.adminVerificationRequests(status: 'pending'),
          _repo.legalDataRequests(),
        ]);
        _complaints = results[0];
        _appeals = results[1];
        _verifications = results[2];
        _dataRequests = results[3];
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _updateComplaint(Map<String, dynamic> row, String status) async {
    await _repo.updateComplaintStatus(row['id'] as String, status: status);
    await _load();
  }

  Future<void> _resolveAppeal(Map<String, dynamic> row, String status) async {
    await _repo.resolveAppeal(row['id'] as String, status: status);
    await _load();
  }

  Future<void> _reviewVerification(Map<String, dynamic> row, String status) async {
    await _repo.reviewVerification(row['id'] as String, status: status);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (!_allowed) {
      return const Scaffold(body: Center(child: Text('Admins only.')));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Legal Dashboard'),
        bottom: TabBar(controller: _tabs, isScrollable: true, tabs: [
          Tab(text: 'Complaints (${_complaints.length})'),
          Tab(text: 'Appeals (${_appeals.length})'),
          Tab(text: 'Verification (${_verifications.length})'),
          Tab(text: 'Legal data requests (${_dataRequests.length})'),
        ]),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _ComplaintsTab(rows: _complaints, onUpdate: _updateComplaint),
          _AppealsTab(rows: _appeals, onResolve: _resolveAppeal),
          _VerificationTab(rows: _verifications, onReview: _reviewVerification),
          _DataRequestsTab(rows: _dataRequests, onRefresh: _load),
        ],
      ),
    );
  }
}

class _ComplaintsTab extends StatelessWidget {
  const _ComplaintsTab({required this.rows, required this.onUpdate});
  final List<Map<String, dynamic>> rows;
  final Future<void> Function(Map<String, dynamic>, String) onUpdate;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const Center(child: Text('No complaints.'));
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final row = rows[i];
        final complainant = (row['users'] as Map?)?['username'] as String? ?? 'unknown';
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${row['complaint_type']} — from @$complainant', style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(row['description'] as String? ?? ''),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  Chip(label: Text(row['status'] as String? ?? '')),
                  if (row['legal_basis_code'] != null) Chip(label: Text(row['legal_basis_code'] as String)),
                ]),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  OutlinedButton(onPressed: () => onUpdate(row, 'under_review'), child: const Text('Under review')),
                  FilledButton(onPressed: () => onUpdate(row, 'action_taken'), child: const Text('Action taken')),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                    onPressed: () => onUpdate(row, 'rejected'),
                    child: const Text('Reject'),
                  ),
                ]),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AppealsTab extends StatelessWidget {
  const _AppealsTab({required this.rows, required this.onResolve});
  final List<Map<String, dynamic>> rows;
  final Future<void> Function(Map<String, dynamic>, String) onResolve;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const Center(child: Text('No appeals.'));
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final row = rows[i];
        final appellant = (row['users'] as Map?)?['username'] as String? ?? 'unknown';
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Appeal from @$appellant', style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(row['statement'] as String? ?? ''),
                const SizedBox(height: 8),
                Chip(label: Text(row['status'] as String? ?? '')),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  FilledButton(onPressed: () => onResolve(row, 'overturned'), child: const Text('Overturn')),
                  OutlinedButton(onPressed: () => onResolve(row, 'upheld'), child: const Text('Uphold')),
                ]),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _VerificationTab extends StatelessWidget {
  const _VerificationTab({required this.rows, required this.onReview});
  final List<Map<String, dynamic>> rows;
  final Future<void> Function(Map<String, dynamic>, String) onReview;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const Center(child: Text('No pending verification requests.'));
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final row = rows[i];
        final username = (row['users'] as Map?)?['username'] as String? ?? 'unknown';
        return Card(
          child: ListTile(
            title: Text('@$username'),
            subtitle: Text(row['id_document_type'] as String? ?? ''),
            trailing: Wrap(spacing: 4, children: [
              IconButton(
                icon: const Icon(Icons.check, color: Colors.green),
                onPressed: () => onReview(row, 'approved'),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.red),
                onPressed: () => onReview(row, 'rejected'),
              ),
            ]),
          ),
        );
      },
    );
  }
}

class _DataRequestsTab extends StatefulWidget {
  const _DataRequestsTab({required this.rows, required this.onRefresh});
  final List<Map<String, dynamic>> rows;
  final Future<void> Function() onRefresh;

  @override
  State<_DataRequestsTab> createState() => _DataRequestsTabState();
}

class _DataRequestsTabState extends State<_DataRequestsTab> {
  final _repo = LegalRepository();

  Future<void> _logNew() async {
    final authority = TextEditingController();
    final details = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log a legal data request'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: authority, decoration: const InputDecoration(labelText: 'Requesting authority')),
            TextField(controller: details, decoration: const InputDecoration(labelText: 'Request details'), maxLines: 3),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true || authority.text.trim().isEmpty) return;
    await _repo.logLegalDataRequest(
      requestingAuthority: authority.text.trim(),
      requestDetails: details.text.trim(),
    );
    await widget.onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.small(onPressed: _logNew, child: const Icon(Icons.add)),
      body: widget.rows.isEmpty
          ? const Center(child: Text('No legal data requests logged.'))
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: widget.rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final row = widget.rows[i];
                return Card(
                  child: ListTile(
                    title: Text(row['requesting_authority'] as String? ?? ''),
                    subtitle: Text(row['request_details'] as String? ?? ''),
                    trailing: Chip(label: Text(row['status'] as String? ?? '')),
                  ),
                );
              },
            ),
    );
  }
}
