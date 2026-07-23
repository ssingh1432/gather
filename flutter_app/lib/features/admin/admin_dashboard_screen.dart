import 'dart:convert';

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
  _Section.dataRequests: '/admin/legal',
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
      case _Section.security:
        return _SecurityTab(repo: _repo);
      case _Section.storage:
        return _StorageTab(repo: _repo);
      case _Section.realtimeStatus:
        return _RealtimeStatusTab(repo: _repo);
      case _Section.systemHealth:
        return _SystemHealthTab(repo: _repo);
      case _Section.backupStatus:
        return _BackupStatusTab(repo: _repo);
      case _Section.moderatorManagement:
        return _ModeratorManagementTab(repo: _repo);
      case _Section.roleManagement:
        return _RoleManagementTab(repo: _repo, role: _role);
      case _Section.permissions:
        return _PermissionsTab(repo: _repo, role: _role);
      case _Section.announcements:
        return _AnnouncementsTab(repo: _repo, role: _role);
      case _Section.notifications:
        return _NotificationsTab(repo: _repo);
      case _Section.settings:
        return _SettingsTab(repo: _repo, role: _role);
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

class _SecurityTab extends StatefulWidget {
  const _SecurityTab({required this.repo});
  final AdminRepository repo;

  @override
  State<_SecurityTab> createState() => _SecurityTabState();
}

class _SecurityTabState extends State<_SecurityTab> {
  List<Map<String, dynamic>> _events = const [];
  List<Map<String, dynamic>> _failures = const [];
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
      _events = await widget.repo.recentSecurityEvents();
      _failures = await widget.repo.recentLoginFailures();
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Error: $_error')));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('Failed logins (last 24h)', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          if (_failures.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No failed login attempts.')),
          for (final f in _failures)
            ListTile(
              leading: const Icon(Icons.warning_amber_outlined, color: Colors.orange),
              title: Text(f['email']?.toString() ?? ''),
              subtitle: Text('${f['failure_count']} failures · last ${f['last_failure']}'),
            ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('Recent security events', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          if (_events.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No security events logged.')),
          for (final e in _events)
            ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: Text(e['event_type']?.toString() ?? ''),
              subtitle: Text('${e['created_at']}'),
            ),
        ],
      ),
    );
  }
}

class _StorageTab extends StatefulWidget {
  const _StorageTab({required this.repo});
  final AdminRepository repo;

  @override
  State<_StorageTab> createState() => _StorageTabState();
}

class _StorageTabState extends State<_StorageTab> {
  List<Map<String, dynamic>> _buckets = const [];
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
      _buckets = await widget.repo.storageStats();
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatBytes(dynamic raw) {
    final bytes = double.tryParse(raw?.toString() ?? '0') ?? 0;
    if (bytes < 1024) return '${bytes.toStringAsFixed(0)} B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Error: $_error')));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        itemCount: _buckets.length,
        itemBuilder: (context, i) {
          final b = _buckets[i];
          final limit = b['file_size_limit'];
          return ListTile(
            leading: Icon(b['is_public'] == true ? Icons.public : Icons.lock_outline),
            title: Text(b['bucket_id']?.toString() ?? ''),
            subtitle: Text(
              '${b['object_count']} objects · ${_formatBytes(b['total_bytes'])}'
              '${limit != null ? ' · limit ${_formatBytes(limit)}/file' : ''}',
            ),
          );
        },
      ),
    );
  }
}

class _RealtimeStatusTab extends StatefulWidget {
  const _RealtimeStatusTab({required this.repo});
  final AdminRepository repo;

  @override
  State<_RealtimeStatusTab> createState() => _RealtimeStatusTabState();
}

class _RealtimeStatusTabState extends State<_RealtimeStatusTab> {
  List<Map<String, dynamic>> _tables = const [];
  bool _loading = true;
  String? _error;
  Duration? _latency;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _tables = await widget.repo.realtimeTables();
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _checkLatency() async {
    setState(() => _checking = true);
    try {
      _latency = await widget.repo.measureRoundTrip();
    } catch (_) {
      _latency = null;
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Error: $_error')));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                FilledButton.icon(
                  onPressed: _checking ? null : _checkLatency,
                  icon: _checking
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.network_check),
                  label: const Text('Test connection'),
                ),
                const SizedBox(width: 12),
                if (_latency != null) Text('${_latency!.inMilliseconds} ms round trip'),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text('Tables enabled for Realtime', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          if (_tables.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No tables are on the supabase_realtime publication.')),
          for (final t in _tables)
            ListTile(
              leading: const Icon(Icons.podcasts_outlined),
              title: Text(t['table_name']?.toString() ?? ''),
              subtitle: Text(t['schema_name']?.toString() ?? ''),
            ),
        ],
      ),
    );
  }
}

class _SystemHealthTab extends StatefulWidget {
  const _SystemHealthTab({required this.repo});
  final AdminRepository repo;

  @override
  State<_SystemHealthTab> createState() => _SystemHealthTabState();
}

class _SystemHealthTabState extends State<_SystemHealthTab> {
  Map<String, dynamic>? _health;
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
      _health = await widget.repo.systemHealth();
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Error: $_error')));
    final h = _health ?? const {};
    final rows = <(String, dynamic, bool)>[
      ('Server time', h['server_time'], false),
      ('Pending appeals', h['pending_appeals'] ?? 0, (h['pending_appeals'] ?? 0) > 0),
      ('Pending media review', h['pending_media_review'] ?? 0, (h['pending_media_review'] ?? 0) > 0),
      ('Flagged media', h['flagged_media'] ?? 0, (h['flagged_media'] ?? 0) > 0),
      ('Pending verifications', h['pending_verifications'] ?? 0, false),
      ('Deletions awaiting purge', h['account_deletions_awaiting_purge'] ?? 0, (h['account_deletions_awaiting_purge'] ?? 0) > 0),
      ('Deletions in grace period', h['account_deletions_in_grace_period'] ?? 0, false),
    ];
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        itemCount: rows.length,
        itemBuilder: (context, i) {
          final (label, value, warn) = rows[i];
          return ListTile(
            leading: Icon(warn ? Icons.warning_amber_outlined : Icons.check_circle_outline, color: warn ? Colors.orange : Colors.green),
            title: Text(label),
            trailing: Text('$value'),
          );
        },
      ),
    );
  }
}

class _BackupStatusTab extends StatefulWidget {
  const _BackupStatusTab({required this.repo});
  final AdminRepository repo;

  @override
  State<_BackupStatusTab> createState() => _BackupStatusTabState();
}

class _BackupStatusTabState extends State<_BackupStatusTab> {
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
      _log = await widget.repo.backupLog();
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Error: $_error')));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        children: [
          const Card(
            margin: EdgeInsets.all(16),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Full database backups (daily + point-in-time recovery) are managed automatically by Supabase at the platform level — see Project Settings → Database → Backups in the Supabase dashboard to restore.\n\n'
                'The log below is a lightweight daily integrity heartbeat run from this app\'s own database: a snapshot of core table row counts, so a sudden unexplained drop shows up here between platform backups.',
              ),
            ),
          ),
          if (_log.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No heartbeat runs recorded yet.')),
          for (final entry in _log)
            ListTile(
              leading: Icon(
                entry['status'] == 'ok' ? Icons.check_circle_outline : Icons.error_outline,
                color: entry['status'] == 'ok' ? Colors.green : Colors.red,
              ),
              title: Text('${entry['run_at']}'.split('.').first),
              subtitle: Text(entry['status'] == 'ok' ? '${entry['row_counts']}' : 'Error: ${entry['error']}'),
            ),
        ],
      ),
    );
  }
}

class _ModeratorManagementTab extends StatefulWidget {
  const _ModeratorManagementTab({required this.repo});
  final AdminRepository repo;

  @override
  State<_ModeratorManagementTab> createState() => _ModeratorManagementTabState();
}

class _ModeratorManagementTabState extends State<_ModeratorManagementTab> {
  List<Map<String, dynamic>> _mods = const [];
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
      _mods = await widget.repo.moderatorActivity();
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Error: $_error')));
    if (_mods.isEmpty) return const Center(child: Text('No moderators or admins yet.'));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        itemCount: _mods.length,
        itemBuilder: (context, i) {
          final m = _mods[i];
          final lastActive = m['last_active'];
          return ListTile(
            leading: CircleAvatar(child: Icon(m['role'] == 'admin' ? Icons.admin_panel_settings : Icons.shield_outlined)),
            title: Text('@${m['username']}'),
            subtitle: Text(
              '${m['role']} · ${m['moderation_action_count']} moderation actions · ${m['admin_action_count']} admin-panel actions',
            ),
            trailing: Text(lastActive != null ? '$lastActive'.split('T').first : 'never active', style: Theme.of(context).textTheme.bodySmall),
          );
        },
      ),
    );
  }
}

class _RoleManagementTab extends StatefulWidget {
  const _RoleManagementTab({required this.repo, required this.role});
  final AdminRepository repo;
  final String? role;

  @override
  State<_RoleManagementTab> createState() => _RoleManagementTabState();
}

class _RoleManagementTabState extends State<_RoleManagementTab> {
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
      _users = await widget.repo.searchUsers(query: _searchCtrl.text, limit: 100);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _changeRole(Map<String, dynamic> user, String role) async {
    try {
      await widget.repo.setUserRole(user['id'].toString(), role);
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('@${user['username']} is now $role')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = widget.role == 'admin';
    final staff = _users.where((u) => u['role'] != 'user').toList();
    final regular = _users.where((u) => u['role'] == 'user').toList();
    if (!isAdmin) {
      return const Center(
        child: Padding(padding: EdgeInsets.all(24), child: Text('Only admins can change roles. You can view Moderator Management instead.')),
      );
    }
    if (_loading) return const Center(child: CircularProgressIndicator());
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
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              children: [
                if (staff.isNotEmpty) const Padding(padding: EdgeInsets.fromLTRB(16, 8, 16, 4), child: Text('Admins & moderators', style: TextStyle(fontWeight: FontWeight.bold))),
                for (final u in staff) _roleTile(u),
                if (regular.isNotEmpty) const Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 4), child: Text('Users', style: TextStyle(fontWeight: FontWeight.bold))),
                for (final u in regular) _roleTile(u),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _roleTile(Map<String, dynamic> u) {
    return ListTile(
      leading: CircleAvatar(
        backgroundImage: u['profile_photo_url'] != null ? NetworkImage(u['profile_photo_url'].toString()) : null,
        child: u['profile_photo_url'] == null ? const Icon(Icons.person) : null,
      ),
      title: Text('@${u['username']}'),
      subtitle: Text('current role: ${u['role']}'),
      trailing: DropdownButton<String>(
        value: u['role']?.toString(),
        items: const [
          DropdownMenuItem(value: 'user', child: Text('User')),
          DropdownMenuItem(value: 'moderator', child: Text('Moderator')),
          DropdownMenuItem(value: 'admin', child: Text('Admin')),
        ],
        onChanged: (v) {
          if (v != null && v != u['role']) _changeRole(u, v);
        },
      ),
    );
  }
}

class _PermissionsTab extends StatefulWidget {
  const _PermissionsTab({required this.repo, required this.role});
  final AdminRepository repo;
  final String? role;

  @override
  State<_PermissionsTab> createState() => _PermissionsTabState();
}

class _PermissionsTabState extends State<_PermissionsTab> {
  List<Map<String, dynamic>> _moderators = const [];
  Map<String, Set<String>> _permsByUser = {};
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
      final activity = await widget.repo.moderatorActivity();
      _moderators = activity.where((m) => m['role'] == 'moderator').toList();
      final perms = <String, Set<String>>{};
      for (final m in _moderators) {
        perms[m['user_id'].toString()] = await widget.repo.permissionsFor(m['user_id'].toString());
      }
      _permsByUser = perms;
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(String userId, String key, bool grant) async {
    final isAdmin = widget.role == 'admin';
    if (!isAdmin) return;
    try {
      if (grant) {
        await widget.repo.grantPermission(userId, key);
      } else {
        await widget.repo.revokePermission(userId, key);
      }
      setState(() {
        final set = _permsByUser[userId] ?? <String>{};
        if (grant) {
          set.add(key);
        } else {
          set.remove(key);
        }
        _permsByUser[userId] = set;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Error: $_error')));
    final isAdmin = widget.role == 'admin';
    if (_moderators.isEmpty) {
      return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No moderators yet — promote someone in Role Management first.')));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!isAdmin)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('Only admins can change permissions. Showing read-only.'),
            ),
          for (final m in _moderators)
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('@${m['username']}', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final key in AdminRepository.permissionCatalog)
                          FilterChip(
                            label: Text(key),
                            selected: (_permsByUser[m['user_id'].toString()] ?? {}).contains(key),
                            onSelected: isAdmin ? (v) => _toggle(m['user_id'].toString(), key, v) : null,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AnnouncementsTab extends StatefulWidget {
  const _AnnouncementsTab({required this.repo, required this.role});
  final AdminRepository repo;
  final String? role;

  @override
  State<_AnnouncementsTab> createState() => _AnnouncementsTabState();
}

class _AnnouncementsTabState extends State<_AnnouncementsTab> {
  List<Map<String, dynamic>> _items = const [];
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
      _items = await widget.repo.announcements();
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    String severity = 'info';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('New announcement'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Title')),
                TextField(controller: bodyCtrl, decoration: const InputDecoration(labelText: 'Body'), maxLines: 4),
                const SizedBox(height: 8),
                DropdownButton<String>(
                  value: severity,
                  items: const [
                    DropdownMenuItem(value: 'info', child: Text('Info')),
                    DropdownMenuItem(value: 'warning', child: Text('Warning')),
                    DropdownMenuItem(value: 'critical', child: Text('Critical')),
                  ],
                  onChanged: (v) => setSt(() => severity = v ?? 'info'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Publish')),
          ],
        ),
      ),
    );
    if (ok != true || titleCtrl.text.trim().isEmpty || bodyCtrl.text.trim().isEmpty) return;
    try {
      await widget.repo.createAnnouncement(title: titleCtrl.text.trim(), body: bodyCtrl.text.trim(), severity: severity);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Color _severityColor(String? s) {
    switch (s) {
      case 'critical':
        return Colors.red;
      case 'warning':
        return Colors.orange;
      default:
        return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Error: $_error')));
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: _items.isEmpty
            ? const Center(child: Text('No announcements yet.'))
            : ListView.builder(
                itemCount: _items.length,
                itemBuilder: (context, i) {
                  final a = _items[i];
                  final active = a['is_active'] == true;
                  return ListTile(
                    leading: Icon(Icons.campaign, color: _severityColor(a['severity']?.toString())),
                    title: Text(a['title']?.toString() ?? '', style: TextStyle(decoration: active ? null : TextDecoration.lineThrough)),
                    subtitle: Text(a['body']?.toString() ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: Wrap(
                      spacing: 4,
                      children: [
                        Switch(
                          value: active,
                          onChanged: (v) => widget.repo.setAnnouncementActive(a['id'].toString(), v).then((_) => _load()),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => widget.repo.deleteAnnouncement(a['id'].toString()).then((_) => _load()),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.add), label: const Text('New')),
    );
  }
}

class _NotificationsTab extends StatefulWidget {
  const _NotificationsTab({required this.repo});
  final AdminRepository repo;

  @override
  State<_NotificationsTab> createState() => _NotificationsTabState();
}

class _NotificationsTabState extends State<_NotificationsTab> {
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
      _stats = await widget.repo.notificationStats();
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Error: $_error')));
    final s = _stats ?? const {};
    final byType = (s['by_type'] as Map?) ?? const {};
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Aggregate counts only — individual notifications stay private to each recipient by design.',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          ),
          ListTile(leading: const Icon(Icons.notifications_outlined), title: const Text('Total'), trailing: Text('${s['total'] ?? 0}')),
          ListTile(leading: const Icon(Icons.mark_email_unread_outlined), title: const Text('Unread'), trailing: Text('${s['unread'] ?? 0}')),
          ListTile(leading: const Icon(Icons.today_outlined), title: const Text('Last 24h'), trailing: Text('${s['last_24h'] ?? 0}')),
          const Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 4), child: Text('By type', style: TextStyle(fontWeight: FontWeight.bold))),
          for (final entry in byType.entries)
            ListTile(leading: const Icon(Icons.label_outline), title: Text(entry.key.toString()), trailing: Text('${entry.value}')),
        ],
      ),
    );
  }
}

class _SettingsTab extends StatefulWidget {
  const _SettingsTab({required this.repo, required this.role});
  final AdminRepository repo;
  final String? role;

  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  List<Map<String, dynamic>> _config = const [];
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
      _config = await widget.repo.appConfig();
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit(Map<String, dynamic> row) async {
    final isAdmin = widget.role == 'admin';
    if (!isAdmin) return;
    final ctrl = TextEditingController(text: jsonEncode(row['value']));
    final newValue = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(row['key']?.toString() ?? ''),
        content: TextField(controller: ctrl, decoration: const InputDecoration(helperText: 'Raw JSON value, e.g. true, 8, or "text"')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Save')),
        ],
      ),
    );
    if (newValue == null) return;
    try {
      final parsed = jsonDecode(newValue);
      await widget.repo.setConfigValue(row['key'].toString(), parsed);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Invalid JSON or save failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Error: $_error')));
    final isAdmin = widget.role == 'admin';
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        children: [
          if (!isAdmin) const Padding(padding: EdgeInsets.all(16), child: Text('Only admins can change settings. Showing read-only.')),
          for (final row in _config)
            ListTile(
              leading: const Icon(Icons.tune),
              title: Text(row['key']?.toString() ?? ''),
              subtitle: Text(jsonEncode(row['value'])),
              trailing: isAdmin ? IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(row)) : null,
              onTap: isAdmin ? () => _edit(row) : null,
            ),
          if (_config.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('No config keys yet.')),
        ],
      ),
    );
  }
}
