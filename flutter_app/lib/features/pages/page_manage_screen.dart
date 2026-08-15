import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../data/repositories.dart';
import 'page_analytics_screen.dart';
import 'page_content_screen.dart';
import 'page_followers_screen.dart';
import 'page_inbox_screen.dart';
import 'page_marketplace_screen.dart';
import 'page_reviews_screen.dart';
import 'page_settings_screen.dart';
import 'page_subscriptions_screen.dart';
import 'page_team_screen.dart';
import 'pages_theme.dart';
import '../../shared/widgets/reusables.dart';

/// Page Management Hub — the single "start here" screen for a Page owner
/// or team member, replacing the five separate `IconButton`s that used to
/// live in [PageProfileScreen]'s app bar (Manage content, Inbox, Insights,
/// Manage team, Followers).
///
/// This screen doesn't add any new capability — every destination it links
/// to already existed. What it changes is *where you find them*: instead
/// of an owner needing to already know that an unlabeled icon on the
/// public-facing profile is theirs, they get one clearly-labeled "Manage"
/// entry point from the profile that leads here, and every management
/// screen is grouped and labeled by what it's for (matching the brief's
/// Content / Audience / Communication / Trust / Team / Insights / Business
/// / Settings mental model).
///
/// Permissions are loaded once, in parallel, and used only to decide what
/// to *show* — every destination screen independently re-checks its own
/// permission server-side, same as before.
class PageManageScreen extends StatefulWidget {
  const PageManageScreen({super.key, required this.pageId});
  final String pageId;

  @override
  State<PageManageScreen> createState() => _PageManageScreenState();
}

class _PageManageScreenState extends State<PageManageScreen> {
  final _repo = PageRepository();

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
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
        setState(() { _error = 'Page not found.'; _loading = false; });
        return;
      }
      setState(() {
        _page = page;
        _canManageContent = results[1] as bool;
        _canManageMessages = results[2] as bool;
        _canViewAnalytics = results[3] as bool;
        _canManageRoles = results[4] as bool;
        _canManageReviews = results[5] as bool;
        _canManageMonetization = results[6] as bool;
        _canEditSettings = results[7] as bool;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = 'Could not load this page. $e'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pageName = _page?['name'] as String? ?? 'Page';
    return Scaffold(
      appBar: AppBar(title: const Text('Manage page', style: TextStyle(fontWeight: FontWeight.w700))),
      body: _loading
          ? const FeedSkeletonList()
          : _error != null
              ? ErrorRetryState(title: 'Unable to load', message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.only(bottom: PageTokens.spaceXxl),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(PageTokens.spaceLg, PageTokens.spaceLg, PageTokens.spaceLg, 0),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: PageColors.surfaceMuted(context),
                            backgroundImage: _page?['logo_url'] != null ? NetworkImage(_page!['logo_url'] as String) : null,
                            child: _page?['logo_url'] == null ? const Icon(Icons.storefront) : null,
                          ),
                          const SizedBox(width: PageTokens.spaceMd),
                          Expanded(
                            child: Text(pageName, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    ),
                    if (_canManageContent) ...[
                      const PageSectionHeader(title: 'Content'),
                      _ManageRow(
                        icon: Icons.dashboard_customize_outlined,
                        title: 'Posts & events',
                        subtitle: 'Create, schedule, pin, and archive content',
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PageContentScreen(pageId: widget.pageId))),
                      ),
                    ],
                    if (_canViewAnalytics || _canManageContent) ...[
                      const PageSectionHeader(title: 'Audience'),
                      if (_canViewAnalytics)
                        _ManageRow(
                          icon: Icons.people_alt_outlined,
                          title: 'Followers',
                          subtitle: 'Roster, growth, and invites',
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PageFollowersScreen(pageId: widget.pageId))),
                        ),
                    ],
                    if (_canManageMessages) ...[
                      const PageSectionHeader(title: 'Communication'),
                      _ManageRow(
                        icon: Icons.inbox_outlined,
                        title: 'Inbox',
                        subtitle: 'Customer conversations and auto-reply settings',
                        onTap: () => Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => PageInboxScreen(pageId: widget.pageId, pageName: pageName))),
                      ),
                    ],
                    if (_canManageReviews) ...[
                      const PageSectionHeader(title: 'Trust'),
                      _ManageRow(
                        icon: Icons.star_outline,
                        title: 'Reviews',
                        subtitle: 'Respond to and moderate reviews',
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PageReviewsScreen(pageId: widget.pageId))),
                      ),
                    ],
                    if (_canManageRoles) ...[
                      const PageSectionHeader(title: 'Team'),
                      _ManageRow(
                        icon: Icons.group_outlined,
                        title: 'Team & roles',
                        subtitle: 'Add or remove team members',
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PageTeamScreen(pageId: widget.pageId))),
                      ),
                    ],
                    if (_canViewAnalytics) ...[
                      const PageSectionHeader(title: 'Insights'),
                      _ManageRow(
                        icon: Icons.insights_outlined,
                        title: 'Analytics',
                        subtitle: 'Reach, engagement, and follower growth',
                        onTap: () => Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => PageAnalyticsScreen(pageId: widget.pageId, pageName: pageName))),
                      ),
                    ],
                    if (_canManageMonetization) ...[
                      const PageSectionHeader(title: 'Business'),
                      _ManageRow(
                        icon: Icons.workspace_premium_outlined,
                        title: 'Subscriptions',
                        subtitle: 'Manage paid-follower tiers',
                        onTap: () => Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => PageSubscriptionsScreen(pageId: widget.pageId, pageName: pageName))),
                      ),
                      _ManageRow(
                        icon: Icons.storefront_outlined,
                        title: 'Marketplace',
                        subtitle: 'Manage products and services for sale',
                        onTap: () => Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => PageMarketplaceScreen(pageId: widget.pageId, pageName: pageName))),
                      ),
                    ],
                    if (_canEditSettings) ...[
                      const PageSectionHeader(title: 'Settings'),
                      _ManageRow(
                        icon: Icons.settings_outlined,
                        title: 'Page settings',
                        subtitle: 'Name, description, category, contact details',
                        onTap: () async {
                          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PageSettingsScreen(pageId: widget.pageId)));
                          _load();
                        },
                      ),
                    ],
                  ],
                ),
    );
  }
}

class _ManageRow extends StatelessWidget {
  const _ManageRow({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: PageTokens.spaceLg, vertical: 4),
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
                  decoration: BoxDecoration(color: AppColors.brandTeal.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(PageTokens.radiusSm)),
                  child: Icon(icon, color: AppColors.brandTeal, size: 20),
                ),
                const SizedBox(width: PageTokens.spaceMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(subtitle, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
