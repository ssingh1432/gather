import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/widgets/reusables.dart';
import '../data/repositories.dart';
import 'page_analytics_screen.dart';
import 'page_content_screen.dart';
import 'page_followers_screen.dart';
import 'page_inbox_screen.dart';
import 'page_marketplace_screen.dart';
import 'page_local_repository.dart';
import 'page_reviews_screen.dart';
import 'page_settings_screen.dart';
import 'page_subscriptions_screen.dart';
import 'page_team_screen.dart';
import 'pages_theme.dart';

class PageManageScreen extends StatefulWidget {
  const PageManageScreen({super.key, required this.pageId});

  final String pageId;

  @override
  State<PageManageScreen> createState() => _PageManageScreenState();
}

class _PageManageScreenState extends State<PageManageScreen> {
  final _repo = PageRepository();
  final _localRepo = PageLocalRepository();

  Map<String, dynamic>? _page;
  bool _loading = true;
  String? _error;
  bool _canManageContent = false;
  bool _canManageMessages = false;
  bool _canViewAnalytics = false;
  bool _canManageRoles = false;
  bool _canManageReviews = false;
  bool _canManageMonetization = false;
  bool _canEditSettings = false;
  bool _canManageVisitorPosts = false;
  int _pendingVisitorPosts = 0;

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
      final results = await Future.wait<dynamic>([
        _repo.getPage(widget.pageId),
        _repo.hasPagePermission(widget.pageId, 'manage_content'),
        _repo.hasPagePermission(widget.pageId, 'manage_messages'),
        _repo.hasPagePermission(widget.pageId, 'view_analytics'),
        _repo.hasPagePermission(widget.pageId, 'manage_roles'),
        _repo.hasPagePermission(widget.pageId, 'manage_reviews'),
        _repo.hasPagePermission(widget.pageId, 'manage_monetization'),
        _repo.hasPagePermission(widget.pageId, 'manage_settings'),
      ]);

      if (!mounted) return;

      final page = results[0] as Map<String, dynamic>?;
      if (page == null) {
        setState(() {
          _error = 'Page not found.';
          _loading = false;
        });
        return;
      }

      final canManageVisitorPosts = results[1] as bool;
      final pending = canManageVisitorPosts
          ? await _localRepo.listPendingVisitorPosts(widget.pageId)
          : <Map<String, dynamic>>[];

      if (!mounted) return;

      setState(() {
        _page = page;
        _canManageContent = results[1] as bool;
        _canManageVisitorPosts = canManageVisitorPosts;
        _canManageMessages = results[2] as bool;
        _canViewAnalytics = results[3] as bool;
        _canManageRoles = results[4] as bool;
        _canManageReviews = results[5] as bool;
        _canManageMonetization = results[6] as bool;
        _canEditSettings = results[7] as bool;
        _pendingVisitorPosts = pending.length;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load this Page. $e';
        _loading = false;
      });
    }
  }

  Future<void> _openVisitorModeration() async {
    final posts = await _localRepo.listPendingVisitorPosts(widget.pageId);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _VisitorModerationScreen(
          pageId: widget.pageId,
          initialPosts: posts,
          repo: _localRepo,
        ),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _openRules() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PageRulesScreen(
          pageId: widget.pageId,
          repo: _localRepo,
        ),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _openVisitorSettings() async {
    final settings = await _localRepo.getVisitorPostingSettings(widget.pageId);
    if (!mounted) return;

    var enabled = settings['allow_visitor_posts'] == true;
    var approval = settings['visitor_posts_require_approval'] == true;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text('Visitor posts'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Allow visitor posts'),
                    subtitle: const Text('Let signed-in users publish on this Page.'),
                    value: enabled,
                    onChanged: (value) => setLocalState(() => enabled = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Approve posts first'),
                    subtitle: const Text('New visitor posts stay pending until Page staff approve them.'),
                    value: approval,
                    onChanged: enabled
                        ? (value) => setLocalState(() => approval = value)
                        : null,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    await _localRepo.updateVisitorPostingSettings(
                      widget.pageId,
                      enabled: enabled,
                      requireApproval: approval,
                    );
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (mounted) _load();
  }

  Widget _section(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageSectionHeader(title: title),
        ...children,
      ],
    );
  }

  Widget _manageRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return _ManageRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pageName = _page?['name'] as String? ?? 'Page';

    Widget body;
    if (_loading) {
      body = const FeedSkeletonList();
    } else if (_error != null) {
      body = ErrorRetryState(
        title: 'Unable to load',
        message: _error!,
        onRetry: _load,
      );
    } else {
      final children = <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            PageTokens.spaceLg,
            PageTokens.spaceLg,
            PageTokens.spaceLg,
            0,
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: PageColors.surfaceMuted(context),
                backgroundImage: _page?['logo_url'] != null
                    ? NetworkImage(_page!['logo_url'] as String)
                    : null,
                child: _page?['logo_url'] == null
                    ? const Icon(Icons.storefront)
                    : null,
              ),
              const SizedBox(width: PageTokens.spaceMd),
              Expanded(
                child: Text(
                  pageName,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
        ),
      ];

      if (_canManageContent) {
        children.add(_section('Content', [
          _manageRow(
            icon: Icons.dashboard_customize_outlined,
            title: 'Posts & events',
            subtitle: 'Create, schedule, pin, and archive content',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PageContentScreen(pageId: widget.pageId),
              ),
            ),
          ),
        ]));
      }

      if (_canManageVisitorPosts) {
        children.add(_section('Audience', [
          _manageRow(
            icon: Icons.forum_outlined,
            title: 'Visitor posts',
            subtitle: _pendingVisitorPosts > 0
                ? '$_pendingVisitorPosts awaiting review'
                : 'Review posts from Page visitors',
            onTap: _openVisitorModeration,
          ),
          _manageRow(
            icon: Icons.tune_outlined,
            title: 'Visitor posting settings',
            subtitle: 'Allow posts and choose approval rules',
            onTap: _openVisitorSettings,
          ),
          _manageRow(
            icon: Icons.rule_outlined,
            title: 'Page rules',
            subtitle: 'Tell visitors what is welcome on this Page',
            onTap: _openRules,
          ),
        ]));
      }

      if (_canViewAnalytics) {
        children.add(_section('Audience', [
          _manageRow(
            icon: Icons.people_alt_outlined,
            title: 'Followers',
            subtitle: 'Roster, growth, and invites',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PageFollowersScreen(pageId: widget.pageId),
              ),
            ),
          ),
        ]));
      }

      if (_canManageMessages) {
        children.add(_section('Communication', [
          _manageRow(
            icon: Icons.inbox_outlined,
            title: 'Inbox',
            subtitle: 'Customer conversations and auto-reply settings',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PageInboxScreen(
                  pageId: widget.pageId,
                  pageName: pageName,
                ),
              ),
            ),
          ),
        ]));
      }

      if (_canManageReviews) {
        children.add(_section('Trust', [
          _manageRow(
            icon: Icons.star_outline,
            title: 'Reviews',
            subtitle: 'Respond to and moderate reviews',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PageReviewsScreen(pageId: widget.pageId),
              ),
            ),
          ),
        ]));
      }

      if (_canManageRoles) {
        children.add(_section('Team', [
          _manageRow(
            icon: Icons.group_outlined,
            title: 'Team & roles',
            subtitle: 'Add or remove team members',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PageTeamScreen(pageId: widget.pageId),
              ),
            ),
          ),
        ]));
      }

      if (_canViewAnalytics) {
        children.add(_section('Insights', [
          _manageRow(
            icon: Icons.insights_outlined,
            title: 'Analytics',
            subtitle: 'Reach, engagement, and follower growth',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PageAnalyticsScreen(
                  pageId: widget.pageId,
                  pageName: pageName,
                ),
              ),
            ),
          ),
        ]));
      }

      if (_canManageMonetization) {
        children.add(_section('Business', [
          _manageRow(
            icon: Icons.workspace_premium_outlined,
            title: 'Subscriptions',
            subtitle: 'Manage paid-follower tiers',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PageSubscriptionsScreen(
                  pageId: widget.pageId,
                  pageName: pageName,
                ),
              ),
            ),
          ),
          _manageRow(
            icon: Icons.storefront_outlined,
            title: 'Marketplace',
            subtitle: 'Manage products and services for sale',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PageMarketplaceScreen(
                  pageId: widget.pageId,
                  pageName: pageName,
                ),
              ),
            ),
          ),
        ]));
      }

      if (_canEditSettings) {
        children.add(_section('Settings', [
          _manageRow(
            icon: Icons.settings_outlined,
            title: 'Page settings',
            subtitle: 'Name, description, category, contact details',
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PageSettingsScreen(pageId: widget.pageId),
                ),
              );
              if (mounted) _load();
            },
          ),
        ]));
      }

      body = ListView(
        padding: const EdgeInsets.only(bottom: PageTokens.spaceXxl),
        children: children,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Manage Page',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: body,
    );
  }
}

class _VisitorModerationScreen extends StatefulWidget {
  const _VisitorModerationScreen({
    required this.pageId,
    required this.initialPosts,
    required this.repo,
  });

  final String pageId;
  final List<Map<String, dynamic>> initialPosts;
  final PageLocalRepository repo;

  @override
  State<_VisitorModerationScreen> createState() => _VisitorModerationScreenState();
}

class _VisitorModerationScreenState extends State<_VisitorModerationScreen> {
  late List<Map<String, dynamic>> posts = [...widget.initialPosts];

  Future<void> _moderate(String id, String status) async {
    try {
      await widget.repo.moderateVisitorPost(id, status);
      if (!mounted) return;
      setState(() => posts.removeWhere((post) => post['id'] == id));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update post: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Visitor posts')),
        body: const Center(child: Text('No posts waiting for review.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Visitor posts')),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: posts.length,
        itemBuilder: (context, index) {
          final post = posts[index];
          final user = post['users'] is Map
              ? Map<String, dynamic>.from(post['users'] as Map)
              : <String, dynamic>{};
          final name = (user['display_name'] as String?)?.trim();
          final username = (user['username'] as String?)?.trim();
          final author = name?.isNotEmpty == true
              ? name!
              : '@${username ?? 'user'}';

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(author, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text(post['content'] as String? ?? ''),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => _moderate(post['id'] as String, 'removed'),
                        child: const Text('Remove'),
                      ),
                      OutlinedButton(
                        onPressed: () => _moderate(post['id'] as String, 'hidden'),
                        child: const Text('Hide'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => _moderate(post['id'] as String, 'published'),
                        child: const Text('Approve'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PageRulesScreen extends StatefulWidget {
  const _PageRulesScreen({required this.pageId, required this.repo});

  final String pageId;
  final PageLocalRepository repo;

  @override
  State<_PageRulesScreen> createState() => _PageRulesScreenState();
}

class _PageRulesScreenState extends State<_PageRulesScreen> {
  List<Map<String, dynamic>> rules = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await widget.repo.listRules(widget.pageId);
      if (mounted) setState(() => rules = result);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load rules: $e')),
        );
      }
    }
  }

  Future<void> _edit([Map<String, dynamic>? rule]) async {
    final title = TextEditingController(text: rule?['title'] as String? ?? '');
    final body = TextEditingController(text: rule?['body'] as String? ?? '');

    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(rule == null ? 'Add rule' : 'Edit rule'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: 'Rule title'),
                ),
                TextField(
                  controller: body,
                  maxLines: 5,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    labelText: 'What visitors should know',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  if (title.text.trim().isEmpty || body.text.trim().isEmpty) {
                    return;
                  }
                  await widget.repo.saveRule(
                    id: rule?['id'] as String?,
                    pageId: widget.pageId,
                    title: title.text,
                    body: body.text,
                    sortOrder: rule?['sort_order'] as int? ?? rules.length,
                  );
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext, true);
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      );

      if (saved == true) await _load();
    } finally {
      title.dispose();
      body.dispose();
    }
  }

  Future<void> _deactivate(String id) async {
    await widget.repo.deactivateRule(id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Page rules'),
        actions: [
          IconButton(
            onPressed: _edit,
            icon: const Icon(Icons.add),
            tooltip: 'Add rule',
          ),
        ],
      ),
      body: rules.isEmpty
          ? const Center(child: Text('No Page rules yet.'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: rules.length,
              itemBuilder: (context, index) {
                final rule = rules[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(rule['title'] as String? ?? ''),
                    subtitle: Text(rule['body'] as String? ?? ''),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'edit') _edit(rule);
                        if (value == 'deactivate') {
                          _deactivate(rule['id'] as String);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'edit',
                          child: Text('Edit'),
                        ),
                        PopupMenuItem(
                          value: 'deactivate',
                          child: Text('Deactivate'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _ManageRow extends StatelessWidget {
  const _ManageRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: PageTokens.spaceLg,
        vertical: 4,
      ),
      child: Material(
        color: PageColors.surfaceCard(context),
        borderRadius: BorderRadius.circular(PageTokens.radiusMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(PageTokens.radiusMd),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(PageTokens.spaceMd),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(PageTokens.radiusMd),
              border: Border.all(color: PageColors.border(context)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.brandTeal.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(PageTokens.radiusSm),
                  ),
                  child: Icon(
                    icon,
                    color: AppColors.brandTeal,
                    size: 20,
                  ),
                ),
                const SizedBox(width: PageTokens.spaceMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
