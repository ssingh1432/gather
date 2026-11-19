import 'package:flutter/material.dart';

import '../../core/supabase_client.dart';
import '../../shared/widgets/reusables.dart';
import 'copyright_repository.dart';
import 'file_copyright_notice_screen.dart';

/// Human-readable status text for a copyright notice (shared with the staff screen).
String copyrightStatusLabel(String status) => switch (status) {
      'submitted' => 'Submitted',
      'under_review' => 'Under review',
      'content_removed' => 'Content removed',
      'rejected' => 'Rejected',
      'counter_notice_received' => 'Counter-notice received',
      'restored' => 'Content restored',
      'withdrawn' => 'Withdrawn',
      _ => status.replaceAll('_', ' '),
    };

/// Notices the user filed, and notices filed against the user's content, with
/// the actions each side is allowed: withdraw (claimant) and counter-notice (author).
class MyCopyrightScreen extends StatefulWidget {
  const MyCopyrightScreen({super.key});

  @override
  State<MyCopyrightScreen> createState() => _MyCopyrightScreenState();
}

class _MyCopyrightScreenState extends State<MyCopyrightScreen> {
  final _repo = CopyrightRepository();
  late Future<List<Map<String, dynamic>>> _notices = _repo.notices();

  void _reload() => setState(() => _notices = _repo.notices());

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _withdraw(String id) async {
    try {
      await _repo.withdraw(id);
      if (mounted) _reload();
    } catch (e) {
      if (mounted) _toast(CopyrightFormValidator.friendlyError(e));
    }
  }

  Future<void> _counter(String noticeId) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _CounterNoticeDialog(repo: _repo, noticeId: noticeId),
    );
    if (done == true && mounted) {
      _toast('Counter-notice sent. A moderator will review it.');
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = SupabaseConfig.currentUserId;
    return Scaffold(
      appBar: AppBar(title: const Text('Copyright notices')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FileCopyrightNoticeScreen()));
          if (mounted) _reload();
        },
        icon: const Icon(Icons.add),
        label: const Text('Report infringement'),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _notices,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const EmptyState(icon: Icons.error_outline, title: 'Could not load notices', message: 'Please try again later.');
          }
          final rows = snapshot.data ?? const [];
          if (rows.isEmpty) {
            return const EmptyState(
              icon: Icons.copyright_outlined,
              title: 'No copyright notices',
              message: 'Notices you file, or that concern your posts, appear here.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final n = rows[i];
              final status = (n['status'] as String?) ?? 'submitted';
              final isClaimant = n['claimant_id'] == uid;
              final isAuthor = n['target_author_id'] == uid;
              final canWithdraw = isClaimant && (status == 'submitted' || status == 'under_review');
              final canCounter = isAuthor && status == 'content_removed';
              final created = ((n['created_at'] as String?) ?? '').split('T').first;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              isClaimant ? 'Filed by you' : 'Against your content',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          Chip(label: Text(copyrightStatusLabel(status))),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text((n['work_description'] as String?) ?? '', maxLines: 3, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text(created, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      if (canWithdraw || canCounter)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Wrap(
                            spacing: 8,
                            children: [
                              if (canWithdraw)
                                OutlinedButton(onPressed: () => _withdraw(n['id'] as String), child: const Text('Withdraw notice')),
                              if (canCounter)
                                FilledButton(onPressed: () => _counter(n['id'] as String), child: const Text('File counter-notice')),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _CounterNoticeDialog extends StatefulWidget {
  const _CounterNoticeDialog({required this.repo, required this.noticeId});

  final CopyrightRepository repo;
  final String noticeId;

  @override
  State<_CounterNoticeDialog> createState() => _CounterNoticeDialogState();
}

class _CounterNoticeDialogState extends State<_CounterNoticeDialog> {
  final _statement = TextEditingController();
  final _signature = TextEditingController();
  bool _consent = false;
  bool _busy = false;

  @override
  void dispose() {
    _statement.dispose();
    _signature.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final error = CopyrightFormValidator.validateCounterNotice(
      statement: _statement.text,
      signature: _signature.text,
      consent: _consent,
    );
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.repo.submitCounterNotice(
        noticeId: widget.noticeId,
        statement: _statement.text,
        consent: _consent,
        signature: _signature.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(CopyrightFormValidator.friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('File a counter-notice'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Only file this if you believe the content was removed by mistake or misidentification.'),
            const SizedBox(height: 12),
            TextField(
              controller: _statement,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Why was the removal a mistake?', border: OutlineInputBorder()),
            ),
            CheckboxListTile(
              value: _consent,
              onChanged: (v) => setState(() => _consent = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: const Text('I consent to the jurisdiction stated in the Copyright Policy and accept that this statement is made under penalty of misrepresentation.'),
            ),
            TextField(
              controller: _signature,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Electronic signature (full name)', border: OutlineInputBorder()),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _send, child: const Text('Send counter-notice')),
      ],
    );
  }
}
