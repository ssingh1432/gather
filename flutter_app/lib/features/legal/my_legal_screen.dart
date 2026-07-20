import 'package:flutter/material.dart';

import '../../shared/widgets/reusables.dart';
import '../data/repositories.dart';
import 'file_complaint_screen.dart';

/// Tracks the current user's own legal complaints and appeals — the
/// grievance/appeal side of Phase 4 Nepal legal compliance.
class MyLegalScreen extends StatefulWidget {
  const MyLegalScreen({super.key});

  @override
  State<MyLegalScreen> createState() => _MyLegalScreenState();
}

class _MyLegalScreenState extends State<MyLegalScreen> with SingleTickerProviderStateMixin {
  final _repo = LegalRepository();
  late final TabController _tabs = TabController(length: 2, vsync: this);
  late Future<List<Map<String, dynamic>>> _complaints;
  late Future<List<Map<String, dynamic>>> _appeals;

  @override
  void initState() {
    super.initState();
    _complaints = _repo.myComplaints();
    _appeals = _repo.myAppeals();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Grievances & legal requests'),
        bottom: TabBar(controller: _tabs, tabs: const [Tab(text: 'Complaints'), Tab(text: 'Appeals')]),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FileComplaintScreen()));
          if (mounted) setState(() => _complaints = _repo.myComplaints());
        },
        icon: const Icon(Icons.add),
        label: const Text('New complaint'),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _ListPane(future: _complaints, statusKey: 'status', typeKey: 'complaint_type', emptyLabel: "You haven't filed any complaints."),
          _ListPane(future: _appeals, statusKey: 'status', typeKey: 'statement', emptyLabel: "You haven't filed any appeals."),
        ],
      ),
    );
  }
}

class _ListPane extends StatelessWidget {
  const _ListPane({required this.future, required this.statusKey, required this.typeKey, required this.emptyLabel});
  final Future<List<Map<String, dynamic>>> future;
  final String statusKey;
  final String typeKey;
  final String emptyLabel;

  Color _statusColor(String status) {
    switch (status) {
      case 'action_taken':
      case 'upheld':
      case 'overturned':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snapshot.data ?? const [];
        if (rows.isEmpty) {
          return EmptyState(icon: Icons.gavel_outlined, title: 'Nothing here yet', message: emptyLabel);
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: rows.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final row = rows[i];
            final status = (row[statusKey] as String?) ?? 'submitted';
            final label = (row[typeKey] as String?) ?? '';
            final createdAt = (row['created_at'] as String?)?.split('T').first ?? '';
            return Card(
              child: ListTile(
                title: Text(label.replaceAll('_', ' '), style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(createdAt),
                trailing: Chip(
                  label: Text(status.replaceAll('_', ' ')),
                  backgroundColor: _statusColor(status).withValues(alpha: 0.15),
                  labelStyle: TextStyle(color: _statusColor(status)),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
