import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/responsive.dart';
import '../../core/supabase_client.dart';
import '../data/repositories.dart';

/// Phase 8: unified Admin Panel shell.
///
/// This is the entry point for every admin section. Sections that already
/// have a dedicated, fully-built screen (Reports/Content Review/Appeals via
/// [AdminModerationScreen], Legal/Complaints via AdminLegalDashboardScreen)
/// are wired in as launch tiles rather than re-implemented here. Sections
/// landing in later Phase 8 batches (Security, Storage, Realtime Status,
/// System Health, Backup Status, Moderator/Role/Permission Management,
/// Announcements, admin Notifications, Settings, Data Requests) show as
/// "coming soon" placeholders so the full nav is visible from day one, per
/// the requested spec, even though they're not all functional yet.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

enum _Section {
  overview('Overview', Icons.dashboard_outlined),
  users('Users', Icons.people_outline),
  posts('Posts', Icons.article_outlined),
  communities('Communities', Icons.groups_outlined),
  reports('Reports', Icons.flag_outlined),
  contentReview('Content Review Queue', Icons.fact_check_outlined),
  complaints('Complaints', Icons.report_problem_outlined),
  legalRequests('Legal Requests', Icons.gavel_outlined),
  analytics('Analytics', Icons.insights_outlined),
  security('Security', Icons.security_outlined),
  auditLogs('Audit Logs', Icons.history_outlined),
  storage('Storage', Icons.storage_outlined),
  realtimeStatus('Realtime Status', Icons.podcasts_outlined),
  systemHealth('System Health', Icons.monitor_heart_outlined),
  moderatorManagement('Moderator Management', Icons.shield_outlined),
  roleManagement('Role Management', Icons.admin_panel_settings_outlined),
  permissions('Permissions', Icons.lock_outline),
  announcements('Announcements', Icons.campaign_outlined),
  notifications('Notifications', Icons.notifications_outlined),
  dataRequests('Data Requests', Icons.folder_shared_outlined),
  backupStatus('Backup Status', Icons.backup_outlined),
  settings('Settings', Icons.settings_outlined);

  final String label;
  final IconData icon;
  const _Section(this.label, this.icon);
}

/// Sections implemented as launch tiles into existing screens rather than
/// rebuilt here, and their target routes.
const Map<_Section, String> _externalRoutes = {
  _Section.reports: '/admin/moderation',
  _Section.contentReview: '/admin/moderation',
  _Section.complaints: '/admin/legal',
  _Section.legalRequests: '/admin/legal',
};

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _repo = AdminRepository();
  bool _loading = true;
  bool _allowed = false;
  String? _role;
  String? _error;
  _Section _section = _Section.overview;

  @override
  void initState() {
    super.initState();
    _checkAccess();
  }

  Future<void> _checkAccess() async {
    setState(() => _loading = true);
    try {
      final uid = SupabaseConfig.client.auth.currentUser?.id;
      if (uid == null) {
        _allowed = false;
      } else {
        final me = await SupabaseConfig.client.from('users').select('role').eq('id', uid).single();
        _role = me['role'] as String?;
        _allowed = ['admin', 'moderator'].contains(_role);
      }
    } catch (e) {
      _error = '$e';
      _allowed = false;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_allowed) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_error ?? "You don't have access to the admin panel."),
          ),
        ),
      );
    }

    final isDesktop = Breakpoints.isDesktop(context);

    return Scaffold(
      appBar: isDesktop ? null : AppBar(title: Text(_section.label)),
      body: SafeArea(
        child: Row(
          children: [
            if (isDesktop)
              SizedBox(
                width: 260,
                child: _NavList(
                  selected: _section,
                  onSelect: (s) => _onSelect(s),
                ),
              ),
            if (isDesktop) const VerticalDivider(width: 1),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
      drawer: isDesktop
          ? null
          : Drawer(
              child: SafeArea(
                child: _NavList(
                  selected: _section,
                  onSelect: (s) {
                    Navigator.pop(context);
                    _onSelect(s);
                  },
                ),
              ),
            ),
    );
  }

  void _onSelect(_Section s) {
    final route = _externalRoutes[s];
    if (route != null) {
      context.push(route);
      return;
    }
    setState(() => _section = s);
  }

  Widget _buildBody() {
    switch (_section) {
      case _Section.overview:
        return _OverviewTab(repo: _repo);
      case _Section.users:
        return _UsersTab(repo: _repo, role: _role);
      case _Section.posts:
        return _PostsTab(repo: _repo);
      case _Section.communities:
        return _CommunitiesTab(repo: _repo);
      case _Section.auditLogs:
        return _AuditLogTab(repo: _repo);
      case _Section.analytics:
        return _OverviewTab(repo: _repo, analyticsMode: true);
      default:
        return _ComingSoonTab(section: _section);
    }
  }
}

class _NavList extends StatelessWidget {
  const _NavList({required this.selected, required this.onSelect});
  final _Section selected;
  final ValueChanged<_Section> onSelect;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text('Admin Panel', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        ),
        for (final s in _Section.values)
          ListTile(
            leading: Icon(s.icon),
            title: Text(s.label),
            selected: s == selected,
            trailing: _externalRoutes.containsKey(s) ? const Icon(Icons.open_in_new, size: 16) : null,
            onTap: () => onSelect(s),
          ),
      ],
    );
  }
}

class _ComingSoonTab extends StatelessWidget {
  const _ComingSoonTab({required this.section});
  final _Section section;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(section.icon, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(section.label, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('Shipping in a later Phase 8 batch.', textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _OverviewTab extends StatefulWidget {
  const _OverviewTab({required this.repo, this.analyticsMode = false});
  final AdminRepository repo;
  final bool analyticsMode;

  @override
  State<_OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<_OverviewTab> {
  Map<String, dynamic>? _stats;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _stats = await widget.repo.overviewStats();
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text('Error: $_error'));
    final s = _stats ?? const {};
    final cards = <(String, String, IconData)>[
      ('Total Users', '${s['total_users'] ?? 0}', Icons.people_outline),
      ('Total Posts', '${s['total_posts'] ?? 0}', Icons.article_outlined),
      ('Communities', '${s['total_communities'] ?? 0}', Icons.groups_outlined),
      ('Open Reports', '${s['open_reports'] ?? 0}', Icons.flag_outlined),
      ('Suspended Users', '${s['suspended_users'] ?? 0}', Icons.block_outlined),
      ('New Users (7d)', '${s['new_users_7d'] ?? 0}', Icons.person_add_outlined),
      ('New Posts (7d)', '${s['new_posts_7d'] ?? 0}', Icons.post_add_outlined),
    ];
    return RefreshIndicator(
      onRefresh: _load,
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          mainAxisExtent: 100,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: cards.length,
        itemBuilder: (context, i) {
          final (label, value, icon) = cards[i];
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 20),
                  const SizedBox(height: 8),
                  Text(value, style: Theme.of(context).textTheme.headlineSmall),
                  Text(label, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _UsersTab extends StatefulWidget {
  const _UsersTab({required this.repo, required this.role});
  final AdminRepository repo;
  final String? role;

  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  List<Map<String, dynamic>> _users = const [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _users = await widget.repo.searchUsers(query: _searchCtrl.text);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _suspend(Map<String, dynamic> user) async {
    final days = await showDialog<int>(
      context: context,
      builder: (ctx) {
        final options = {'1 day': 1, '3 days': 3, '7 days': 7, '30 days': 30, 'Indefinite': null};
        return SimpleDialog(
          title: Text('Suspend @${user['username']}'),
          children: options.entries
              .map((e) => SimpleDialogOption(onPressed: () => Navigator.pop(ctx, e.value ?? -1), child: Text(e.key)))
              .toList(),
        );
      },
    );
    if (days == null) return;
    try {
      await widget.repo.suspendUser(user['id'].toString(), durationDays: days == -1 ? null : days);
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User suspended')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _reinstate(Map<String, dynamic> user) async {
    try {
      await widget.repo.reinstateUser(user['id'].toString());
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User reinstated')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = widget.role == 'admin';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Search by username or email',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(icon: const Icon(Icons.clear), onPressed: () {
                _searchCtrl.clear();
                _load();
              }),
            ),
            onSubmitted: (_) => _load(),
          ),
        ),
        if (_loading) const Expanded(child: Center(child: CircularProgressIndicator())),
        if (!_loading)
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                itemCount: _users.length,
                itemBuilder: (context, i) {
                  final u = _users[i];
                  final suspended = u['status'] == 'suspended';
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: u['profile_photo_url'] != null ? NetworkImage(u['profile_photo_url'].toString()) : null,
                      child: u['profile_photo_url'] == null ? const Icon(Icons.person) : null,
                    ),
                    title: Text('@${u['username']}'),
                    subtitle: Text('${u['email'] ?? ''} · role: ${u['role']} · status: ${u['status']}'),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'suspend') _suspend(u);
                        if (v == 'reinstate') _reinstate(u);
                        if (v == 'make_mod' && isAdmin) widget.repo.setUserRole(u['id'].toString(), 'moderator').then((_) => _load());
                        if (v == 'make_admin' && isAdmin) widget.repo.setUserRole(u['id'].toString(), 'admin').then((_) => _load());
                        if (v == 'make_user' && isAdmin) widget.repo.setUserRole(u['id'].toString(), 'user').then((_) => _load());
                      },
                      itemBuilder: (ctx) => [
                        if (!suspended) const PopupMenuItem(value: 'suspend', child: Text('Suspend')),
                        if (suspended) const PopupMenuItem(value: 'reinstate', child: Text('Reinstate')),
                        if (isAdmin) const PopupMenuDivider(),
                        if (isAdmin) const PopupMenuItem(value: 'make_mod', child: Text('Make moderator')),
                        if (isAdmin) const PopupMenuItem(value: 'make_admin', child: Text('Make admin')),
                        if (isAdmin) const PopupMenuItem(value: 'make_user', child: Text('Reset to user')),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _PostsTab extends StatefulWidget {
  const _PostsTab({required this.repo});
  final AdminRepository repo;

  @override
  State<_PostsTab> createState() => _PostsTabState();
}

class _PostsTabState extends State<_PostsTab> {
  List<Map<String, dynamic>> _posts = const [];
  bool _loading = true;
  bool _removedOnly = false;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _posts = await widget.repo.searchPosts(query: _searchCtrl.text, removedOnly: _removedOnly ? true : null);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(hintText: 'Search post text', prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
                  onSubmitted: (_) => _load(),
                ),
              ),
              const SizedBox(width: 12),
              FilterChip(
                label: const Text('Removed only'),
                selected: _removedOnly,
                onSelected: (v) {
                  setState(() => _removedOnly = v);
                  _load();
                },
              ),
            ],
          ),
        ),
        if (_loading) const Expanded(child: Center(child: CircularProgressIndicator())),
        if (!_loading)
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                itemCount: _posts.length,
                itemBuilder: (context, i) {
                  final p = _posts[i];
                  final removed = p['is_removed'] == true;
                  final author = (p['users'] as Map?)?['username']?.toString() ?? 'unknown';
                  return ListTile(
                    title: Text('@$author', style: TextStyle(decoration: removed ? TextDecoration.lineThrough : null)),
                    subtitle: Text(p['text_content']?.toString() ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: removed
                        ? TextButton(onPressed: () => widget.repo.restorePost(p['id'].toString()).then((_) => _load()), child: const Text('Restore'))
                        : TextButton(onPressed: () => widget.repo.removePost(p['id'].toString()).then((_) => _load()), child: const Text('Remove')),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _CommunitiesTab extends StatefulWidget {
  const _CommunitiesTab({required this.repo});
  final AdminRepository repo;

  @override
  State<_CommunitiesTab> createState() => _CommunitiesTabState();
}

class _CommunitiesTabState extends State<_CommunitiesTab> {
  List<Map<String, dynamic>> _communities = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _communities = await widget.repo.listCommunities();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        itemCount: _communities.length,
        itemBuilder: (context, i) {
          final c = _communities[i];
          final memberCountList = c['member_count'] as List?;
          final memberCount = (memberCountList != null && memberCountList.isNotEmpty) ? ((memberCountList.first as Map)['count'] ?? 0) : 0;
          return ListTile(
            leading: const Icon(Icons.groups_outlined),
            title: Text(c['name']?.toString() ?? ''),
            subtitle: Text(c['description']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Text('$memberCount members'),
          );
        },
      ),
    );
  }
}

class _AuditLogTab extends StatefulWidget {
  const _AuditLogTab({required this.repo});
  final AdminRepository repo;

  @override
  State<_AuditLogTab> createState() => _AuditLogTabState();
}

class _AuditLogTabState extends State<_AuditLogTab> {
  List<Map<String, dynamic>> _log = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _log = await widget.repo.auditLog();
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Error: $_error')));
    }
    if (_log.isEmpty) {
      return const Center(child: Text('No admin actions logged yet.'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        itemCount: _log.length,
        itemBuilder: (context, i) {
          final e = _log[i];
          final admin = (e['users'] as Map?)?['username']?.toString() ?? 'unknown';
          return ListTile(
            leading: const Icon(Icons.history),
            title: Text(e['action']?.toString() ?? ''),
            subtitle: Text('by @$admin · ${e['target_type'] ?? ''} ${e['target_id'] ?? ''}'),
            trailing: Text('${e['created_at']}'.split('T').first),
          );
        },
      ),
    );
  }
}
