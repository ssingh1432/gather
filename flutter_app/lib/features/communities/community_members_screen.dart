import 'package:flutter/material.dart';

import '../../core/supabase_client.dart';
import '../data/repositories.dart';
import '../../shared/widgets/reusables.dart';

/// Member roster + role management + (for private communities) pending
/// join-request approval. All mutations go through the SECURITY DEFINER
/// RPCs in `CommunityRepository`, which independently re-check the
/// caller's role server-side — this screen's own role checks are only for
/// showing/hiding controls, not the actual security boundary.
class CommunityMembersScreen extends StatefulWidget {
  const CommunityMembersScreen({super.key, required this.communityId});
  final String communityId;

  @override
  State<CommunityMembersScreen> createState() => _CommunityMembersScreenState();
}

class _CommunityMembersScreenState extends State<CommunityMembersScreen> {
  final repo = CommunityRepository();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _members = const [];
  List<Map<String, dynamic>> _requests = const [];
  String? _myRole;
  bool _isPrivate = false;

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
      final uid = SupabaseConfig.currentUserId;
      final community = await repo.getCommunity(widget.communityId);
      _isPrivate = community?['visibility'] == 'private';
      _members = await repo.listMembers(widget.communityId);
      _myRole = uid == null ? null : _members.firstWhere((m) => m['user_id'] == uid, orElse: () => const {})['role'] as String?;
      final canSeeRequests = _isPrivate && (_myRole == 'owner' || _myRole == 'admin' || _myRole == 'moderator');
      _requests = canSeeRequests ? await repo.listJoinRequests(widget.communityId) : const [];
    } catch (e) {
      _error = 'Could not load members. $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _canManage => _myRole == 'owner' || _myRole == 'admin' || _myRole == 'moderator';

  Future<void> _decide(String requestId, bool approve) async {
    try {
      await repo.decideJoinRequest(requestId, approve);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(approve ? 'Request approved.' : 'Request declined.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update request: $e')));
    }
  }

  Future<void> _setRole(String userId, String role) async {
    try {
      await repo.setMemberRole(widget.communityId, userId, role);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update role: $e')));
    }
  }

  Future<void> _remove(String userId, String username) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove member'),
        content: Text('Remove @$username from this community?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await repo.removeMember(widget.communityId, userId);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not remove member: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Members')),
      body: _loading
          ? const FeedSkeletonList()
          : _error != null
              ? ErrorRetryState(title: 'Unable to load members', message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      if (_requests.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Text('Pending requests (${_requests.length})', style: Theme.of(context).textTheme.titleSmall),
                        ),
                        for (final r in _requests) _RequestTile(request: r, onDecide: _decide),
                        const Divider(height: 24),
                      ],
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Text('${_members.length} member${_members.length == 1 ? '' : 's'}', style: Theme.of(context).textTheme.titleSmall),
                      ),
                      for (final m in _members)
                        _MemberTile(
                          member: m,
                          canManage: _canManage,
                          myRole: _myRole,
                          onSetRole: _setRole,
                          onRemove: _remove,
                        ),
                    ],
                  ),
                ),
    );
  }
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({required this.request, required this.onDecide});
  final Map<String, dynamic> request;
  final Future<void> Function(String requestId, bool approve) onDecide;

  @override
  Widget build(BuildContext context) {
    final user = (request['users'] as Map<String, dynamic>?) ?? const {};
    final username = user['username'] as String? ?? 'user';
    return ListTile(
      leading: CircleAvatar(
        backgroundImage: (user['profile_photo_url'] as String?)?.isNotEmpty == true ? NetworkImage(user['profile_photo_url']) : null,
        child: (user['profile_photo_url'] as String?)?.isNotEmpty != true ? const Icon(Icons.person) : null,
      ),
      title: Text(user['display_name'] as String? ?? '@$username'),
      subtitle: Text('@$username${(request['message'] as String?)?.isNotEmpty == true ? ' · "${request['message']}"' : ''}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(icon: const Icon(Icons.check, color: Colors.green), onPressed: () => onDecide(request['id'].toString(), true)),
          IconButton(icon: const Icon(Icons.close, color: Colors.red), onPressed: () => onDecide(request['id'].toString(), false)),
        ],
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.member, required this.canManage, required this.myRole, required this.onSetRole, required this.onRemove});
  final Map<String, dynamic> member;
  final bool canManage;
  final String? myRole;
  final Future<void> Function(String userId, String role) onSetRole;
  final Future<void> Function(String userId, String username) onRemove;

  @override
  Widget build(BuildContext context) {
    final user = (member['users'] as Map<String, dynamic>?) ?? const {};
    final username = user['username'] as String? ?? 'user';
    final role = member['role'] as String? ?? 'member';
    final userId = member['user_id'].toString();
    // Owner can manage anyone but themselves; admin can manage moderators/members only.
    final canManageThisRow = canManage && role != 'owner' && (myRole == 'owner' || (myRole == 'admin' && role != 'admin'));

    return ListTile(
      leading: CircleAvatar(
        backgroundImage: (user['profile_photo_url'] as String?)?.isNotEmpty == true ? NetworkImage(user['profile_photo_url']) : null,
        child: (user['profile_photo_url'] as String?)?.isNotEmpty != true ? const Icon(Icons.person) : null,
      ),
      title: Text(user['display_name'] as String? ?? '@$username'),
      subtitle: Text('@$username'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RoleBadge(role: role),
          if (canManageThisRow)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'remove') {
                  onRemove(userId, username);
                } else {
                  onSetRole(userId, value);
                }
              },
              itemBuilder: (context) => [
                if (role != 'admin' && myRole == 'owner') const PopupMenuItem(value: 'admin', child: Text('Make admin')),
                if (role != 'moderator') const PopupMenuItem(value: 'moderator', child: Text('Make moderator')),
                if (role != 'member') const PopupMenuItem(value: 'member', child: Text('Make member')),
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'remove', child: Text('Remove from community', style: TextStyle(color: Colors.red))),
              ],
            ),
        ],
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});
  final String role;

  @override
  Widget build(BuildContext context) {
    if (role == 'member') return const SizedBox.shrink();
    final colors = {
      'owner': Colors.amber,
      'admin': Colors.deepPurple,
      'moderator': Colors.teal,
    };
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Chip(
        label: Text(role, style: const TextStyle(fontSize: 11)),
        backgroundColor: (colors[role] ?? Colors.grey).withValues(alpha: 0.15),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
    );
  }
}
