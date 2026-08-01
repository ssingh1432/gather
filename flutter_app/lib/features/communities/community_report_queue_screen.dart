import 'package:flutter/material.dart';

import '../data/repositories.dart';

/// Community-scoped report queue (migration 058). Only reports on posts
/// within this community, visible/actionable to whoever holds
/// manage_reports (view/resolve/dismiss) or manage_posts (remove) here —
/// separate from the site-wide admin report queue, which still exists
/// unchanged and sees everything including user-target reports this
/// screen doesn't handle.
class CommunityReportQueueScreen extends StatefulWidget {
  const CommunityReportQueueScreen({super.key, required this.communityId});
  final String communityId;

  @override
  State<CommunityReportQueueScreen> createState() => _CommunityReportQueueScreenState();
}

class _CommunityReportQueueScreenState extends State<CommunityReportQueueScreen> {
  final repo = CommunityRepository();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _reports = const [];
  String _statusFilter = 'open';

  static const _statusOptions = {'open': 'Open', 'reviewing': 'Reviewing', 'resolved': 'Resolved', 'dismissed': 'Dismissed'};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _reports = await repo.getCommunityReportQueue(widget.communityId, status: _statusFilter);
    } catch (e) {
      _error = 'Could not load the report queue. $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resolve(String reportId) async {
    final note = await _promptNote('Resolve report', 'Optional note (e.g. what you checked)');
    try {
      await repo.resolveCommunityReport(reportId, note: note);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not resolve: $e')));
    }
  }

  Future<void> _dismiss(String reportId) async {
    final note = await _promptNote('Dismiss report', 'Optional note (e.g. why this isn\'t a violation)');
    try {
      await repo.dismissCommunityReport(reportId, note: note);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not dismiss: $e')));
    }
  }

  Future<void> _removePost(String reportId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove this post?'),
        content: const Text('The post will be hidden from the community and the report marked resolved. This requires manage_posts, separately from resolving/dismissing.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove post', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;
    final note = await _promptNote('Remove post', 'Reason for removal (optional)');
    try {
      await repo.removePostViaCommunityReport(reportId, note: note);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not remove post: $e')));
    }
  }

  Future<String?> _promptNote(String title, String hint) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: controller, autofocus: true, maxLines: 3, decoration: InputDecoration(hintText: hint, border: const OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Confirm without a note')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim().isEmpty ? null : controller.text.trim()), child: const Text('Confirm')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report queue'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                for (final entry in _statusOptions.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: ChoiceChip(
                      label: Text(entry.value),
                      selected: _statusFilter == entry.key,
                      onSelected: (_) {
                        setState(() => _statusFilter = entry.key);
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _reports.isEmpty
                  ? Center(child: Text('No ${_statusOptions[_statusFilter]!.toLowerCase()} reports.'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        itemCount: _reports.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) => _ReportTile(
                          report: _reports[i],
                          onResolve: _statusFilter == 'open' || _statusFilter == 'reviewing' ? () => _resolve(_reports[i]['id'] as String) : null,
                          onDismiss: _statusFilter == 'open' || _statusFilter == 'reviewing' ? () => _dismiss(_reports[i]['id'] as String) : null,
                          onRemovePost: _statusFilter == 'open' || _statusFilter == 'reviewing' ? () => _removePost(_reports[i]['id'] as String) : null,
                        ),
                      ),
                    ),
    );
  }
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({required this.report, this.onResolve, this.onDismiss, this.onRemovePost});
  final Map<String, dynamic> report;
  final VoidCallback? onResolve;
  final VoidCallback? onDismiss;
  final VoidCallback? onRemovePost;

  @override
  Widget build(BuildContext context) {
    final category = (report['category'] as String? ?? 'other').replaceAll('_', ' ');
    final reporter = report['reporter_username'] as String?;
    final preview = report['post_preview'] as String? ?? '';
    final reason = report['reason'] as String?;
    final isAutomated = report['is_automated'] == true;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Chip(label: Text(category), visualDensity: VisualDensity.compact, backgroundColor: Colors.red.withValues(alpha: 0.1)),
              const SizedBox(width: 8),
              if (isAutomated)
                const Chip(label: Text('Auto-flagged'), visualDensity: VisualDensity.compact)
              else
                Text('Reported by ${reporter != null ? '@$reporter' : 'a user'}', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 6),
          Text(preview.isEmpty ? '(no text content)' : preview, maxLines: 3, overflow: TextOverflow.ellipsis),
          if (reason != null && reason.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('"$reason"', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
          ],
          if (onResolve != null || onDismiss != null || onRemovePost != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (onDismiss != null) OutlinedButton(onPressed: onDismiss, child: const Text('Dismiss')),
                if (onResolve != null) OutlinedButton(onPressed: onResolve, child: const Text('Resolve')),
                if (onRemovePost != null)
                  OutlinedButton(
                    onPressed: onRemovePost,
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                    child: const Text('Remove post'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
