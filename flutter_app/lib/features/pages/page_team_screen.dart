import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../data/repositories.dart';
import '../../shared/widgets/reusables.dart';
import '../../shared/utils/time_ago.dart';
import 'pages_theme.dart';

/// Team roster + role management for a Page (Step 5 of the brief).
///
/// The page owner (`pages.owner_id`) is shown as a fixed, non-editable
/// first row — ownership isn't a `page_roles` row and can't be reassigned
/// or revoked from here. Below it is the assignable roster: manager,
/// editor, content_creator, moderator, customer_support, analyst — each
/// with its own permission set (migration 072's `page_role_permissions`).
/// All mutations go through the SECURITY DEFINER RPCs added in migration
/// 075, which independently re-check the caller's permission server-side —
/// this screen's own `_canManageRoles` check only hides/shows controls.
class PageTeamScreen extends StatefulWidget {
  const PageTeamScreen({super.key, required this.pageId});
  final String pageId;

  @override
  State<PageTeamScreen> createState() => _PageTeamScreenState();
}

class _PageTeamScreenState extends State<PageTeamScreen> {
  final _repo = PageRepository();
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _page;
  List<Map<String, dynamic>> _team = const [];
  Map<String, Set<String>> _roleMatrix = const {};
  List<Map<String, dynamic>> _permissions = const [];
  bool _canManageRoles = false;

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
      final page = await _repo.getPage(widget.pageId);
      final team = await _repo.listTeamMembers(widget.pageId);
      final matrix = await _repo.listRolePermissionMatrix();
      final perms = await _repo.listPagePermissions();
      final canManage = await _repo.hasPagePermission(widget.pageId, 'manage_roles');
      if (!mounted) return;
      setState(() {
        _page = page;
        _team = team;
        _roleMatrix = matrix;
        _permissions = perms;
        _canManageRoles = canManage;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load the team. $e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _openAddSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _AddMemberSheet(
        pageId: widget.pageId,
        repo: _repo,
        onAdded: _load,
      ),
    );
  }

  Future<void> _changeRole(Map<String, dynamic> member) async {
    final current = member['role'] as String;
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => _RoleSheet(selectedRole: current),
    );
    if (selected == null || selected == current) return;
    try {
      await _repo.updateTeamMemberRole(widget.pageId, member['user_id'] as String, selected);
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Role updated.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update role: ${_friendly(e)}')));
    }
  }

  Future<void> _remove(Map<String, dynamic> member) async {
    final username = (member['users'] as Map<String, dynamic>?)?['username'] as String? ?? 'this user';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove from team'),
        content: Text('Remove @$username from this page\'s team? They will lose all page permissions immediately.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Remove', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repo.removeTeamMember(widget.pageId, member['user_id'] as String);
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('@$username removed from the team.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not remove: ${_friendly(e)}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Team', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          if (_canManageRoles)
            IconButton(
              icon: const Icon(Icons.person_add_alt_outlined),
              tooltip: 'Add team member',
              onPressed: _openAddSheet,
            ),
        ],
      ),
      body: _loading
          ? const FeedSkeletonList()
          : _error != null
              ? ErrorRetryState(title: 'Unable to load team', message: _error!, onRetry: _load)
              : _page == null
                  ? const Center(child: Text('Page not found'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.symmetric(vertical: PageTokens.spaceSm),
                        children: [
                          const PageSectionHeader(title: 'Owner'),
                          _OwnerTile(page: _page!),
                          const Divider(height: PageTokens.spaceXl),
                          PageSectionHeader(title: 'Team (${_team.length})'),
                          if (_team.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: PageTokens.spaceLg, vertical: PageTokens.spaceSm),
                              child: Text(
                                'No team members yet. Add people to help manage this page.',
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                              ),
                            )
                          else
                            for (final m in _team)
                              _MemberTile(
                                member: m,
                                canManage: _canManageRoles,
                                onChangeRole: () => _changeRole(m),
                                onRemove: () => _remove(m),
                              ),
                          const SizedBox(height: PageTokens.spaceXl),
                          const Divider(height: 1),
                          PageSectionHeader(title: 'What each role can do'),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: PageTokens.spaceLg),
                            child: _RoleMatrixCard(matrix: _roleMatrix, permissions: _permissions),
                          ),
                          const SizedBox(height: PageTokens.spaceXxl),
                        ],
                      ),
                    ),
    );
  }
}

/// Strips the generic "Exception: " / RPC prefix Supabase adds so the raise
/// exception message set in migration 075 reaches the user cleanly.
String _friendly(Object e) {
  final s = e.toString();
  final match = RegExp(r'message[":\s]+([^,"}]+)').firstMatch(s);
  return match?.group(1)?.trim() ?? s.replaceFirst('Exception: ', '');
}

class _OwnerTile extends StatelessWidget {
  const _OwnerTile({required this.page});
  final Map<String, dynamic> page;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: PageTokens.spaceLg, vertical: PageTokens.spaceXs),
      child: Container(
        padding: const EdgeInsets.all(PageTokens.spaceMd),
        decoration: BoxDecoration(
          color: PageColors.surfaceCard(context),
          borderRadius: BorderRadius.circular(PageTokens.radiusMd),
          border: Border.all(color: PageColors.border(context)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.brandTeal.withValues(alpha: 0.15),
              child: const Icon(Icons.verified_user, color: AppColors.brandTeal, size: 18),
            ),
            const SizedBox(width: PageTokens.spaceMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Page owner', style: TextStyle(fontWeight: FontWeight.w700)),
                  Text(
                    kPageRoleDescriptions['owner']!,
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            PageStatChip(icon: Icons.star, label: 'Owner', color: AppColors.brandTeal),
          ],
        ),
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.member, required this.canManage, required this.onChangeRole, required this.onRemove});
  final Map<String, dynamic> member;
  final bool canManage;
  final VoidCallback onChangeRole;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final user = member['users'] as Map<String, dynamic>?;
    final username = user?['username'] as String? ?? 'unknown';
    final displayName = user?['display_name'] as String?;
    final photoUrl = user?['profile_photo_url'] as String?;
    final role = member['role'] as String;
    final createdAt = member['created_at'] as String?;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: PageTokens.spaceLg, vertical: PageTokens.spaceXs),
      child: Container(
        padding: const EdgeInsets.all(PageTokens.spaceMd),
        decoration: BoxDecoration(
          color: PageColors.surfaceCard(context),
          borderRadius: BorderRadius.circular(PageTokens.radiusMd),
          border: Border.all(color: PageColors.border(context)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: PageColors.surfaceMuted(context),
              backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
              child: photoUrl == null ? const Icon(Icons.person_outline) : null,
            ),
            const SizedBox(width: PageTokens.spaceMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(displayName?.isNotEmpty == true ? displayName! : '@$username', style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(
                    '@$username${createdAt != null ? ' · joined ${timeAgo(DateTime.parse(createdAt))}' : ''}',
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (canManage)
              PopupMenuButton<String>(
                onSelected: (v) => v == 'role' ? onChangeRole() : onRemove(),
                itemBuilder: (ctx) => const [
                  PopupMenuItem(value: 'role', child: Text('Change role')),
                  PopupMenuItem(value: 'remove', child: Text('Remove from team')),
                ],
                child: PageStatChip(icon: Icons.badge_outlined, label: kPageRoles[role] ?? role),
              )
            else
              PageStatChip(icon: Icons.badge_outlined, label: kPageRoles[role] ?? role),
          ],
        ),
      ),
    );
  }
}

class _RoleMatrixCard extends StatelessWidget {
  const _RoleMatrixCard({required this.matrix, required this.permissions});
  final Map<String, Set<String>> matrix;
  final List<Map<String, dynamic>> permissions;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(PageTokens.spaceMd),
      decoration: BoxDecoration(
        color: PageColors.surfaceCard(context),
        borderRadius: BorderRadius.circular(PageTokens.radiusMd),
        border: Border.all(color: PageColors.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final roleKey in kPageRoles.keys) ...[
            Text(kPageRoles[roleKey]!, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(kPageRoleDescriptions[roleKey] ?? '', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final p in permissions)
                  if ((matrix[roleKey] ?? const {}).contains(p['key']))
                    Chip(
                      label: Text(p['label'] as String, style: const TextStyle(fontSize: 11)),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: EdgeInsets.zero,
                    ),
              ],
            ),
            if (roleKey != kPageRoles.keys.last) const Divider(height: PageTokens.spaceXl),
          ],
        ],
      ),
    );
  }
}

class _RoleSheet extends StatelessWidget {
  const _RoleSheet({required this.selectedRole});
  final String selectedRole;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Align(alignment: Alignment.centerLeft, child: Text('Choose a role', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
          ),
          for (final entry in kPageRoles.entries)
            ListTile(
              title: Text(entry.value),
              subtitle: Text(kPageRoleDescriptions[entry.key] ?? ''),
              trailing: entry.key == selectedRole ? const Icon(Icons.check, color: AppColors.brandTeal) : null,
              onTap: () => Navigator.pop(context, entry.key),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _AddMemberSheet extends StatefulWidget {
  const _AddMemberSheet({required this.pageId, required this.repo, required this.onAdded});
  final String pageId;
  final PageRepository repo;
  final Future<void> Function() onAdded;

  @override
  State<_AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends State<_AddMemberSheet> {
  final _usernameController = TextEditingController();
  String _role = 'editor';
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _usernameController.text.trim().replaceFirst('@', '');
    if (username.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.repo.addTeamMember(widget.pageId, username, _role);
      await widget.onAdded();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('@$username added to the team.')));
      }
    } catch (e) {
      if (mounted) setState(() => _error = _friendly(e));
    } finally {
      if (mounted) setState(() => _sending = false);
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
          Text('Add team member', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _usernameController,
            autofocus: true,
            decoration: pageFieldDecoration(context, labelText: 'Username', hintText: '@username'),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          Text('Role', style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in kPageRoles.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: _role == entry.key,
                  onSelected: (_) => setState(() => _role = entry.key),
                ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PageTokens.radiusPill)),
              ),
              child: _sending
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onBrandTeal))
                  : const Text('Add to team', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}
