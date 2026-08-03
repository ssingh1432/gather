import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/supabase_client.dart';
import '../../core/theme/app_theme.dart';
import '../data/repositories.dart';
import '../../shared/widgets/reusables.dart';
import '../../shared/utils/time_ago.dart';
import 'community_audit_log_screen.dart';
import 'community_keyword_filters_screen.dart';
import 'community_report_queue_screen.dart';
import 'community_theme.dart';

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
  List<Map<String, dynamic>> _bans = const [];
  String? _myRole;
  bool _isPrivate = false;
  bool _canManageBans = false;
  bool _canManageMembers = false;
  bool _canManageReports = false;

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
      // manage_bans is permission-based (migration 052), not a raw role
      // check, so it correctly reflects any per-community override an
      // owner has set — unlike role/removal actions below, which are
      // still gated by the simpler role hierarchy from migration 049.
      _canManageBans = await repo.hasPermission(widget.communityId, 'manage_bans');
      _bans = _canManageBans ? await repo.listActiveBans(widget.communityId) : const [];
      _canManageMembers = await repo.hasPermission(widget.communityId, 'manage_members');
      _canManageReports = await repo.hasPermission(widget.communityId, 'manage_reports');
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

  Future<void> _openInviteSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _InviteSheet(communityId: widget.communityId, repo: repo),
    );
  }

  Future<void> _warn(String userId, String username) async {
    final reason = await _promptReason(context, title: 'Warn @$username', hint: 'Reason for this warning');
    if (reason == null || reason.trim().isEmpty) return;
    try {
      await repo.warnMember(widget.communityId, userId, reason.trim());
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('@$username has been warned.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not warn member: $e')));
    }
  }

  Future<void> _ban(String userId, String username) async {
    final result = await showDialog<_BanChoice>(
      context: context,
      builder: (ctx) => _BanDialog(username: username),
    );
    if (result == null) return;
    try {
      await repo.banMember(widget.communityId, userId, reason: result.reason, expiresAt: result.expiresAt);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('@$username has been banned and removed from the community.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not ban member: $e')));
    }
  }

  Future<void> _unban(String userId, String username) async {
    try {
      await repo.unbanMember(widget.communityId, userId);
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('@$username has been unbanned.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not unban member: $e')));
    }
  }

  Future<String?> _promptReason(BuildContext context, {required String title, required String hint}) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(hintText: hint, border: const OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Send warning')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Members', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          if (_canManageMembers)
            IconButton(
              icon: const Icon(Icons.person_add_alt_outlined),
              tooltip: 'Invite',
              onPressed: _openInviteSheet,
            ),
          if (_canManageReports)
            IconButton(
              icon: const Icon(Icons.flag_outlined),
              tooltip: 'Report queue',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => CommunityReportQueueScreen(communityId: widget.communityId)),
              ),
            ),
          if (_canManageReports)
            IconButton(
              icon: const Icon(Icons.filter_alt_outlined),
              tooltip: 'Keyword filters',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => CommunityKeywordFiltersScreen(communityId: widget.communityId)),
              ),
            ),
          if (_canManageBans)
            IconButton(
              icon: const Icon(Icons.history),
              tooltip: 'Moderation log',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => CommunityAuditLogScreen(communityId: widget.communityId)),
              ),
            ),
        ],
      ),
      body: _loading
          ? const FeedSkeletonList()
          : _error != null
              ? ErrorRetryState(title: 'Unable to load members', message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: CommunityTokens.spaceSm),
                    children: [
                      if (_requests.isNotEmpty) ...[
                        CommunitySectionHeader(title: 'Pending requests (${_requests.length})'),
                        for (final r in _requests) CommunityRowCard(child: _RequestTile(request: r, onDecide: _decide)),
                        const Divider(height: CommunityTokens.spaceXl),
                      ],
                      CommunitySectionHeader(title: '${_members.length} member${_members.length == 1 ? '' : 's'}'),
                      for (final m in _members)
                        CommunityRowCard(
                          child: _MemberTile(
                            member: m,
                            canManage: _canManage,
                            canManageBans: _canManageBans,
                            canManageReports: _canManageReports,
                            myRole: _myRole,
                            communityId: widget.communityId,
                            onSetRole: _setRole,
                            onRemove: _remove,
                            onWarn: _warn,
                            onBan: _ban,
                          ),
                        ),
                      if (_bans.isNotEmpty) ...[
                        const Divider(height: CommunityTokens.spaceXl),
                        CommunitySectionHeader(title: 'Banned (${_bans.length})'),
                        for (final b in _bans) CommunityRowCard(child: _BannedUserTile(ban: b, onUnban: _unban)),
                      ],
                    ],
                  ),
                ),
    );
  }
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Absolute date for a future ban expiry — timeAgo() only handles past
/// timestamps, so it can't be reused here.
String _formatExpiry(DateTime dateTime) {
  final local = dateTime.toLocal();
  return '${_months[local.month - 1]} ${local.day}, ${local.year}';
}

/// Bottom sheet for both invite flows: invite a specific person by
/// username (accept/decline required on their end), or generate a
/// shareable code with an optional use-limit/expiry.
class _InviteSheet extends StatefulWidget {
  const _InviteSheet({required this.communityId, required this.repo});
  final String communityId;
  final CommunityRepository repo;

  @override
  State<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<_InviteSheet> {
  final _usernameController = TextEditingController();
  bool _sendingInvite = false;
  bool _creatingLink = false;
  String? _generatedCode;
  int? _linkMaxUses;
  static const _maxUsesOptions = {null: 'Unlimited', 5: '5 uses', 20: '20 uses', 100: '100 uses'};

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _sendUsernameInvite() async {
    final username = _usernameController.text.trim().replaceFirst('@', '');
    if (username.isEmpty || _sendingInvite) return;
    setState(() => _sendingInvite = true);
    try {
      await widget.repo.inviteUserByUsername(widget.communityId, username);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Invite sent to @$username.')));
        _usernameController.clear();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not send invite: $e')));
    } finally {
      if (mounted) setState(() => _sendingInvite = false);
    }
  }

  Future<void> _generateLink() async {
    setState(() => _creatingLink = true);
    try {
      final code = await widget.repo.createInviteLink(widget.communityId, maxUses: _linkMaxUses);
      if (mounted) setState(() => _generatedCode = code);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not create invite link: $e')));
    } finally {
      if (mounted) setState(() => _creatingLink = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Invite people', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Text('By username', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    hintText: '@username',
                    filled: true,
                    fillColor: CommunityColors.surfaceMuted(context),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(CommunityTokens.radiusSm), borderSide: BorderSide.none),
                  ),
                  onSubmitted: (_) => _sendUsernameInvite(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brandTeal,
                  foregroundColor: AppColors.onBrandTeal,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CommunityTokens.radiusPill)),
                ),
                onPressed: _sendingInvite ? null : _sendUsernameInvite,
                child: _sendingInvite ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onBrandTeal)) : const Text('Send'),
              ),
            ],
          ),
          Text(
            'They\'ll get a notification and can accept or decline — nothing happens automatically.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Divider(height: 32),
          Text('Shareable link', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          if (_generatedCode == null) ...[
            Wrap(
              spacing: 8,
              children: [
                for (final entry in _maxUsesOptions.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: _linkMaxUses == entry.key,
                    onSelected: (_) => setState(() => _linkMaxUses = entry.key),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _creatingLink ? null : _generateLink,
              icon: _creatingLink
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.link),
              label: const Text('Create invite link'),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(border: Border.all(color: CommunityColors.border(context)), borderRadius: BorderRadius.circular(CommunityTokens.radiusSm)),
              child: Row(
                children: [
                  Expanded(
                    child: Text(_generatedCode!, style: Theme.of(context).textTheme.titleMedium?.copyWith(letterSpacing: 2, fontFamily: 'monospace')),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_outlined),
                    tooltip: 'Copy code',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _generatedCode!));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code copied.')));
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.share_outlined),
                    tooltip: 'Share',
                    onPressed: () => Share.share('Join my community on Gather! Use invite code $_generatedCode in the app.'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: () => setState(() => _generatedCode = null), child: const Text('Create another link')),
          ],
        ],
      ),
    );
  }
}

/// Bottom sheet: moderator note history for one member, plus an add form.
/// Notes are visible to anyone with manage_reports in this community —
/// they're internal moderator context, not shown to the member themselves.
class _MemberNotesSheet extends StatefulWidget {
  const _MemberNotesSheet({required this.communityId, required this.userId, required this.username});
  final String communityId;
  final String userId;
  final String username;

  @override
  State<_MemberNotesSheet> createState() => _MemberNotesSheetState();
}

class _MemberNotesSheetState extends State<_MemberNotesSheet> {
  final repo = CommunityRepository();
  final _controller = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  List<Map<String, dynamic>> _notes = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _notes = await repo.listCommunityModeratorNotes(widget.communityId, targetUserId: widget.userId);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not load notes: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addNote() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      await repo.addCommunityModeratorNote(widget.communityId, targetUserId: widget.userId, note: text);
      _controller.clear();
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not add note: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Moderator notes — @${widget.username}', style: Theme.of(context).textTheme.titleLarge),
          Text('Only visible to moderators — not shown to this member.', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: _loading
                ? const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
                : _notes.isEmpty
                    ? const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('No notes yet.'))
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: _notes.length,
                        separatorBuilder: (_, __) => const Divider(height: 16),
                        itemBuilder: (context, i) {
                          final n = _notes[i];
                          final moderator = (n['moderator'] as Map?)?['username'] as String?;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(n['note'] as String? ?? ''),
                              const SizedBox(height: 2),
                              Text(
                                '${moderator != null ? '@$moderator' : 'A moderator'} · ${timeAgo(DateTime.tryParse(n['created_at'] as String? ?? '') ?? DateTime.now())}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          );
                        },
                      ),
          ),
          const Divider(height: 24),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: InputDecoration(
                    hintText: 'Add a note',
                    filled: true,
                    fillColor: CommunityColors.surfaceMuted(context),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(CommunityTokens.radiusSm), borderSide: BorderSide.none),
                  ),
                  onSubmitted: (_) => _addNote(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brandTeal,
                  foregroundColor: AppColors.onBrandTeal,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CommunityTokens.radiusPill)),
                ),
                onPressed: _saving ? null : _addNote,
                child: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onBrandTeal)) : const Text('Add'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BanChoice {
  const _BanChoice({this.reason, this.expiresAt});
  final String? reason;
  final DateTime? expiresAt;
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
  const _MemberTile({
    required this.member,
    required this.canManage,
    required this.canManageBans,
    required this.canManageReports,
    required this.myRole,
    required this.communityId,
    required this.onSetRole,
    required this.onRemove,
    required this.onWarn,
    required this.onBan,
  });
  final Map<String, dynamic> member;
  final bool canManage;
  final bool canManageBans;
  final bool canManageReports;
  final String? myRole;
  final String communityId;
  final Future<void> Function(String userId, String role) onSetRole;
  final Future<void> Function(String userId, String username) onRemove;
  final Future<void> Function(String userId, String username) onWarn;
  final Future<void> Function(String userId, String username) onBan;

  Future<void> _openNotes(BuildContext context, String userId, String username) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _MemberNotesSheet(communityId: communityId, userId: userId, username: username),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = (member['users'] as Map<String, dynamic>?) ?? const {};
    final username = user['username'] as String? ?? 'user';
    final role = member['role'] as String? ?? 'member';
    final userId = member['user_id'].toString();
    // Owner can manage anyone but themselves; admin can manage moderators/members only.
    final canManageThisRow = canManage && role != 'owner' && (myRole == 'owner' || (myRole == 'admin' && role != 'admin'));
    // Bans/warnings use the migration-052 permission system rather than
    // this hardcoded hierarchy, but the owner is still never a valid target.
    final canDiscipline = canManageBans && role != 'owner';
    // Notes are just documentation, not a disciplinary action, so unlike
    // warn/ban there's no reason to exclude the owner as a target.
    final canAddNotes = canManageReports;

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
          CommunityRoleChip(role: role),
          if (canManageThisRow || canDiscipline || canAddNotes)
            PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'remove':
                    onRemove(userId, username);
                  case 'warn':
                    onWarn(userId, username);
                  case 'ban':
                    onBan(userId, username);
                  case 'notes':
                    _openNotes(context, userId, username);
                  default:
                    onSetRole(userId, value);
                }
              },
              itemBuilder: (context) => [
                if (canManageThisRow) ...[
                  if (role != 'admin' && myRole == 'owner') const PopupMenuItem(value: 'admin', child: Text('Make admin')),
                  if (role != 'moderator') const PopupMenuItem(value: 'moderator', child: Text('Make moderator')),
                  if (role != 'trusted_member') const PopupMenuItem(value: 'trusted_member', child: Text('Make trusted member')),
                  if (role != 'member') const PopupMenuItem(value: 'member', child: Text('Make member')),
                  const PopupMenuDivider(),
                  const PopupMenuItem(value: 'remove', child: Text('Remove from community', style: TextStyle(color: Colors.red))),
                ],
                if (canDiscipline) ...[
                  if (canManageThisRow) const PopupMenuDivider(),
                  const PopupMenuItem(value: 'warn', child: Text('Warn')),
                  const PopupMenuItem(value: 'ban', child: Text('Ban', style: TextStyle(color: Colors.red))),
                ],
                if (canAddNotes) ...[
                  if (canManageThisRow || canDiscipline) const PopupMenuDivider(),
                  const PopupMenuItem(value: 'notes', child: Text('Moderator notes')),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _BannedUserTile extends StatelessWidget {
  const _BannedUserTile({required this.ban, required this.onUnban});
  final Map<String, dynamic> ban;
  final Future<void> Function(String userId, String username) onUnban;

  @override
  Widget build(BuildContext context) {
    final user = (ban['users'] as Map<String, dynamic>?) ?? const {};
    final username = user['username'] as String? ?? 'user';
    final userId = ban['user_id'].toString();
    final expiresAt = ban['expires_at'] as String?;
    final reason = ban['reason'] as String?;
    final expiryText = expiresAt == null ? 'Permanent' : 'Until ${_formatExpiry(DateTime.parse(expiresAt))}';

    return ListTile(
      leading: CircleAvatar(
        backgroundImage: (user['profile_photo_url'] as String?)?.isNotEmpty == true ? NetworkImage(user['profile_photo_url']) : null,
        child: (user['profile_photo_url'] as String?)?.isNotEmpty != true ? const Icon(Icons.person) : null,
      ),
      title: Text(user['display_name'] as String? ?? '@$username'),
      subtitle: Text('@$username · $expiryText${reason?.isNotEmpty == true ? ' · $reason' : ''}'),
      trailing: TextButton(onPressed: () => onUnban(userId, username), child: const Text('Unban')),
    );
  }
}

class _BanDialog extends StatefulWidget {
  const _BanDialog({required this.username});
  final String username;

  @override
  State<_BanDialog> createState() => _BanDialogState();
}

class _BanDialogState extends State<_BanDialog> {
  final _reasonController = TextEditingController();
  int _durationDays = 0; // 0 = permanent

  static const _durations = {0: 'Permanent', 1: '1 day', 7: '7 days', 30: '30 days'};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Ban @${widget.username}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _reasonController,
            autofocus: true,
            maxLines: 2,
            decoration: const InputDecoration(hintText: 'Reason for this ban', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          const Text('Duration'),
          Wrap(
            spacing: 8,
            children: [
              for (final entry in _durations.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: _durationDays == entry.key,
                  onSelected: (_) => setState(() => _durationDays = entry.key),
                ),
            ],
          ),
          Text(
            'They will be removed from the community immediately and cannot rejoin while banned.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            _BanChoice(
              reason: _reasonController.text.trim().isEmpty ? null : _reasonController.text.trim(),
              expiresAt: _durationDays == 0 ? null : DateTime.now().add(Duration(days: _durationDays)),
            ),
          ),
          child: const Text('Ban', style: TextStyle(color: Colors.red)),
        ),
      ],
    );
  }
}


