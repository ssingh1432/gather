import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/utils/time_ago.dart';
import '../../shared/widgets/reusables.dart';
import '../data/repositories.dart';
import 'page_local_repository.dart';
import 'pages_theme.dart';

/// Follower analytics + audience management for a Page.
///
/// Viewing the roster is gated by `view_analytics`. Removing a follower is a
/// stronger owner/manager action and is gated independently by `manage_roles`
/// through the server-side `remove_page_follower` RPC.
class PageFollowersScreen extends StatefulWidget {
  const PageFollowersScreen({super.key, required this.pageId});
  final String pageId;

  @override
  State<PageFollowersScreen> createState() => _PageFollowersScreenState();
}

class _PageFollowersScreenState extends State<PageFollowersScreen> {
  final _repo = PageRepository();
  final _localRepo = PageLocalRepository();
  bool _loading = true;
  String? _error;
  bool _canView = false;
  bool _canInvite = false;
  bool _canManageFollowers = false;
  Map<String, dynamic> _stats = const {
    'total_followers': 0,
    'new_last_7d': 0,
    'new_last_30d': 0,
  };
  List<Map<String, dynamic>> _followers = const [];

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
      final canView = await _repo.hasPagePermission(widget.pageId, 'view_analytics');
      final canInvite = await _repo.hasPagePermission(widget.pageId, 'manage_content');
      final canManageFollowers = await _repo.hasPagePermission(widget.pageId, 'manage_roles');
      final stats = canView ? await _repo.getPageFollowerStats(widget.pageId) : _stats;
      final followers = canView
          ? await _repo.listPageFollowers(widget.pageId)
          : const <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _canView = canView;
        _canInvite = canInvite;
        _canManageFollowers = canManageFollowers;
        _stats = stats;
        _followers = followers;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load followers. $e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _openInviteSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _InviteFollowersSheet(pageId: widget.pageId, repo: _repo),
    );
  }

  Future<void> _removeFollower(Map<String, dynamic> follower) async {
    final userId = follower['user_id'] as String?;
    if (userId == null) return;
    final username = (follower['username'] as String?)?.trim();
    final displayName = (follower['display_name'] as String?)?.trim();
    final label = displayName?.isNotEmpty == true
        ? displayName!
        : username?.isNotEmpty == true
            ? '@$username'
            : 'this follower';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove follower?'),
        content: Text(
          'Remove $label from this Page\'s followers? They can follow the Page again later unless the Page is configured otherwise.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Remove',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _localRepo.removeFollower(widget.pageId, userId);
      if (!mounted) return;
      setState(() {
        _followers = _followers.where((f) => f['user_id'] != userId).toList();
        final total = (_stats['total_followers'] as num?)?.toInt() ?? 0;
        _stats = {..._stats, 'total_followers': total > 0 ? total - 1 : 0};
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label was removed from the Page followers.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not remove follower: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Followers', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          if (_canInvite)
            IconButton(
              icon: const Icon(Icons.person_add_alt_1_outlined),
              tooltip: 'Invite followers',
              onPressed: _openInviteSheet,
            ),
        ],
      ),
      body: _loading
          ? const FeedSkeletonList()
          : _error != null
              ? ErrorRetryState(
                  title: 'Unable to load followers',
                  message: _error!,
                  onRetry: _load,
                )
              : !_canView
                  ? const EmptyState(
                      icon: Icons.lock_outline,
                      title: 'Not authorized',
                      message:
                          'Follower analytics are visible to team members with the "View analytics" permission.',
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.only(bottom: PageTokens.spaceXxl),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(PageTokens.spaceLg),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _StatCard(
                                    label: 'Total',
                                    value: '${_stats['total_followers'] ?? 0}',
                                  ),
                                ),
                                const SizedBox(width: PageTokens.spaceSm),
                                Expanded(
                                  child: _StatCard(
                                    label: 'Last 7 days',
                                    value: '+${_stats['new_last_7d'] ?? 0}',
                                  ),
                                ),
                                const SizedBox(width: PageTokens.spaceSm),
                                Expanded(
                                  child: _StatCard(
                                    label: 'Last 30 days',
                                    value: '+${_stats['new_last_30d'] ?? 0}',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          PageSectionHeader(
                            title: '${_followers.length} follower${_followers.length == 1 ? '' : 's'}',
                          ),
                          if (_followers.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: PageTokens.spaceLg),
                              child: EmptyState(
                                icon: Icons.people_outline,
                                title: 'No followers yet',
                                message: 'Invite people to get your first followers.',
                              ),
                            )
                          else
                            for (final f in _followers)
                              ListTile(
                                leading: CircleAvatar(
                                  backgroundImage: (f['profile_photo_url'] as String?) != null
                                      ? NetworkImage(f['profile_photo_url'] as String)
                                      : null,
                                  child: (f['profile_photo_url'] as String?) == null
                                      ? const Icon(Icons.person_outline)
                                      : null,
                                ),
                                title: Text(
                                  (f['display_name'] as String?)?.isNotEmpty == true
                                      ? f['display_name'] as String
                                      : '@${f['username']}',
                                ),
                                subtitle: Text(
                                  '@${f['username']} · followed ${timeAgo(DateTime.parse(f['followed_at'] as String))}',
                                ),
                                trailing: _canManageFollowers
                                    ? PopupMenuButton<String>(
                                        tooltip: 'Manage follower',
                                        onSelected: (value) {
                                          if (value == 'remove') _removeFollower(f);
                                        },
                                        itemBuilder: (_) => const [
                                          PopupMenuItem(
                                            value: 'remove',
                                            child: Text('Remove follower'),
                                          ),
                                        ],
                                      )
                                    : (f['notify'] as bool? ?? false)
                                        ? const Icon(
                                            Icons.notifications_active_outlined,
                                            size: 18,
                                            color: AppColors.brandTeal,
                                          )
                                        : null,
                              ),
                        ],
                      ),
                    ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: PageTokens.spaceMd,
        horizontal: PageTokens.spaceSm,
      ),
      decoration: BoxDecoration(
        color: PageColors.surfaceCard(context),
        borderRadius: BorderRadius.circular(PageTokens.radiusMd),
        border: Border.all(color: PageColors.border(context)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandTeal,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _InviteFollowersSheet extends StatefulWidget {
  const _InviteFollowersSheet({required this.pageId, required this.repo});
  final String pageId;
  final PageRepository repo;

  @override
  State<_InviteFollowersSheet> createState() => _InviteFollowersSheetState();
}

class _InviteFollowersSheetState extends State<_InviteFollowersSheet> {
  final _controller = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final usernames = _controller.text
        .split(RegExp(r'[,\s]+'))
        .map((u) => u.trim().replaceFirst('@', ''))
        .where((u) => u.isNotEmpty)
        .toSet()
        .toList();
    if (usernames.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final invited = await widget.repo.inviteUsersToFollowPage(
        widget.pageId,
        usernames,
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              invited == 0
                  ? 'No new invites sent — those usernames may already follow this page, be invalid, or already invited.'
                  : 'Invited $invited ${invited == 1 ? 'person' : 'people'} to follow this page.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _sending = false);
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
          Text('Invite followers', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            'Enter one or more usernames, separated by commas or spaces.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 1,
            maxLines: 3,
            decoration: pageFieldDecoration(
              context,
              labelText: 'Usernames',
              hintText: '@amita, @rajesh123',
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _sending ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brandTeal,
                foregroundColor: AppColors.onBrandTeal,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(PageTokens.radiusPill),
                ),
              ),
              child: _sending
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.onBrandTeal,
                      ),
                    )
                  : const Text(
                      'Send invites',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
