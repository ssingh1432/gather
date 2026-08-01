import 'package:flutter/material.dart';

import '../data/repositories.dart';
import '../../shared/widgets/reusables.dart';
import '../../shared/utils/time_ago.dart';

/// Read-only moderation history for a community: role changes, removals,
/// bans, unbans, warnings, permission overrides, settings changes.
/// Populated exclusively by `log_community_audit()` (migration 053) from
/// inside each moderation RPC — there is no client insert path, so this
/// list can't be tampered with or backdated. RLS requires manage_bans or
/// manage_reports in this community (or site admin/mod), so reaching this
/// screen at all already implies the caller is allowed to see it.
class CommunityAuditLogScreen extends StatefulWidget {
  const CommunityAuditLogScreen({super.key, required this.communityId});
  final String communityId;

  @override
  State<CommunityAuditLogScreen> createState() => _CommunityAuditLogScreenState();
}

class _CommunityAuditLogScreenState extends State<CommunityAuditLogScreen> {
  final repo = CommunityRepository();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _entries = const [];

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
      _entries = await repo.listAuditLog(widget.communityId);
    } catch (e) {
      _error = 'Could not load the moderation log. $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Moderation log')),
      body: _loading
          ? const FeedSkeletonList()
          : _error != null
              ? ErrorRetryState(title: 'Unable to load log', message: _error!, onRetry: _load)
              : _entries.isEmpty
                  ? const Center(child: Text('No moderation actions yet.'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _entries.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) => _AuditLogTile(entry: _entries[i]),
                      ),
                    ),
    );
  }
}

class _AuditLogTile extends StatelessWidget {
  const _AuditLogTile({required this.entry});
  final Map<String, dynamic> entry;

  @override
  Widget build(BuildContext context) {
    final actor = (entry['actor'] as Map<String, dynamic>?) ?? const {};
    final target = (entry['target'] as Map<String, dynamic>?) ?? const {};
    final action = entry['action'] as String? ?? '';
    final metadata = (entry['metadata'] as Map<String, dynamic>?) ?? const {};
    final createdAt = DateTime.tryParse(entry['created_at'] as String? ?? '');

    final actorName = actor['username'] != null ? '@${actor['username']}' : 'A site admin';
    final targetName = target['username'] != null ? '@${target['username']}' : null;

    return ListTile(
      leading: CircleAvatar(backgroundColor: _iconColor(action).withValues(alpha: 0.15), child: Icon(_icon(action), color: _iconColor(action), size: 20)),
      title: Text(_describe(action, actorName, targetName)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (metadata['reason'] != null && (metadata['reason'] as String).isNotEmpty) Text('Reason: ${metadata['reason']}'),
          if (createdAt != null) Text(timeAgo(createdAt), style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      isThreeLine: metadata['reason'] != null,
    );
  }

  String _describe(String action, String actorName, String? targetName) {
    final target = targetName ?? 'a member';
    return switch (action) {
      'role_changed' => '$actorName changed $target\'s role',
      'member_removed' => '$actorName removed $target',
      'member_banned' => '$actorName banned $target',
      'member_unbanned' => '$actorName unbanned $target',
      'member_warned' => '$actorName warned $target',
      'permission_overridden' => '$actorName changed a permission override',
      'settings_changed' => '$actorName updated community settings',
      'report_resolved' => '$actorName resolved a report',
      'report_dismissed' => '$actorName dismissed a report',
      'post_removed' => '$actorName removed a post',
      _ => '$actorName performed $action on $target',
    };
  }

  IconData _icon(String action) => switch (action) {
        'member_banned' => Icons.block,
        'member_unbanned' => Icons.check_circle_outline,
        'member_warned' => Icons.warning_amber,
        'member_removed' => Icons.person_remove,
        'role_changed' => Icons.swap_horiz,
        'permission_overridden' => Icons.tune,
        'settings_changed' => Icons.settings,
        'report_resolved' => Icons.check_circle_outline,
        'report_dismissed' => Icons.cancel_outlined,
        'post_removed' => Icons.delete_outline,
        _ => Icons.history,
      };

  Color _iconColor(String action) => switch (action) {
        'member_banned' => Colors.red,
        'member_unbanned' => Colors.green,
        'member_warned' => Colors.orange,
        'member_removed' => Colors.red,
        _ => Colors.blueGrey,
      };
}
