import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/supabase_client.dart';
import '../../shared/utils/external_link.dart';
import '../../shared/widgets/reusables.dart';
import '../data/repositories.dart';
import 'donate_sheet.dart';
import 'page_chat_screen.dart';
import 'page_content_composer_screen.dart';
import 'page_local_repository.dart';
import 'page_manage_screen.dart';
import 'page_preview_screen.dart' show PageInfoRow;
import 'page_profile_widgets.dart';
import 'page_public_posts_section.dart';
import 'page_visitor_post_composer_screen.dart';
import 'pages_theme.dart';

export 'page_profile_widgets.dart' show PageVisitorPostFollowGate;

class PageProfileScreen extends StatefulWidget {
  const PageProfileScreen({super.key, required this.pageId});

  final String pageId;

  @override
  State<PageProfileScreen> createState() => _PageProfileScreenState();
}

class _PageProfileScreenState extends State<PageProfileScreen> {
  final _repo = PageRepository();
  final _localRepo = PageLocalRepository();

  Map<String, dynamic>? _page;
  bool _loading = true;
  bool _following = false;
  bool _followBusy = false;
  bool _favorite = false;
  bool _canManage = false;
  bool _canViewFollowers = false;
  bool _hasSubscriptionTiers = false;
  bool _hasMarketplaceItems = false;
  bool _allowVisitorPosts = false;
  bool _visitorPostsRequireApproval = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      // Keep the Page shell independent from post/media loading. The public
      // posts section owns its own loading/error state so a single post,
      // media, or visitor-post failure cannot tear down the entire Page.
      final page = await _repo.getPage(widget.pageId);
      final uid = SupabaseConfig.currentUserId;
      final followState = uid == null ? null : await _repo.getFollowState(widget.pageId);
      final role = uid == null ? null : await _repo.currentUserPageRole(widget.pageId);
      final canViewFollowers = uid == null
          ? false
          : await _repo.hasPagePermission(widget.pageId, 'view_analytics');
      final hasTiers = await _repo.hasVisibleSubscriptionTiers(widget.pageId);
      final hasItems = await _repo.hasVisibleMarketplaceItems(widget.pageId);
      final visitorSettings = await _localRepo.getVisitorPostingSettings(widget.pageId);

      if (!mounted) return;

      setState(() {
        _page = page;
        _following = followState != null;
        _favorite = followState?['favorite'] as bool? ?? false;
        _canManage = role != null;
        _canViewFollowers = canViewFollowers;
        _hasSubscriptionTiers = hasTiers;
        _hasMarketplaceItems = hasItems;
        _allowVisitorPosts = visitorSettings['allow_visitor_posts'] == true;
        _visitorPostsRequireApproval = visitorSettings['visitor_posts_require_approval'] == true;
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

  Future<void> _openPostComposer() async {
    if (SupabaseConfig.currentUserId == null) {
      context.push('/login');
      return;
    }

    final Widget composer = _canManage
        ? PageContentComposerScreen(pageId: widget.pageId)
        : PageVisitorPostComposerScreen(
            pageId: widget.pageId,
            pageName: _page?['name']?.toString() ?? 'this Page',
            requireApproval: _visitorPostsRequireApproval,
          );

    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => composer),
    );
    if (created == true && mounted) await _load();
  }

  Future<void> _toggleFollow() async {
    if (SupabaseConfig.currentUserId == null) {
      context.push('/login');
      return;
    }

    final wasFollowing = _following;
    setState(() {
      _followBusy = true;
      _following = !wasFollowing;
      final count = (_page?['follower_count'] as int?) ?? 0;
      _page = {
        ..._page!,
        'follower_count': wasFollowing ? count - 1 : count + 1,
      };
    });

    try {
      if (wasFollowing) {
        await _repo.unfollowPage(widget.pageId);
      } else {
        await _repo.followPage(widget.pageId);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _following = wasFollowing;
        final count = (_page?['follower_count'] as int?) ?? 0;
        _page = {
          ..._page!,
          'follower_count': wasFollowing ? count + 1 : count - 1,
        };
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update follow status: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _followBusy = false;
          if (!_following) _favorite = false;
        });
      }
    }
  }

  Future<void> _toggleFavorite() async {
    if (!_following) return;

    final wasFavorite = _favorite;
    setState(() => _favorite = !wasFavorite);
    try {
      await _repo.setPageFavorite(widget.pageId, !wasFavorite);
    } catch (e) {
      if (!mounted) return;
      setState(() => _favorite = wasFavorite);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update favorite: $e')),
      );
    }
  }

  String get _pageTypeLabel {
    final type = _page?['page_type'] as String?;
    return kPageTypes[type] ?? type ?? 'Other';
  }

  String? get _businessHoursNote {
    final hours = _page?['business_hours'];
    if (hours is Map) {
      final note = hours['note'];
      if (note is String && note.isNotEmpty) return note;
    }
    return null;
  }

  Future<void> _launchOrSnack(Uri uri) async {
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open this link.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open this link.')),
        );
      }
    }
  }

  Map<String, String> get _socialLinks {
    final links = _page?['social_links'];
    if (links is Map) {
      final result = <String, String>{};
      for (final entry in links.entries) {
        final value = entry.value?.toString() ?? '';
        if (value.isNotEmpty) result[entry.key.toString()] = value;
      }
      return result;
    }
    return const {};
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          page?['name'] as String? ?? 'Page',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          if (_canManage)
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Manage Page',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PageManageScreen(pageId: widget.pageId),
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const FeedSkeletonList()
          : _error != null
              ? ErrorRetryState(
                  title: 'Unable to load Page',
                  message: _error!,
                  onRetry: _load,
                )
              : page == null
                  ? const Center(child: Text('Page not found'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.only(bottom: PageTokens.spaceXxl),
                        children: [
                          PageCoverAndLogo(page: page),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: PageTokens.spaceLg),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 40),
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        page['name'] as String,
                                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                                      ),
                                    ),
                                    if (page['verification_status'] == 'verified') ...[
                                      const SizedBox(width: 6),
                                      const Icon(Icons.verified, color: AppColors.brandTeal, size: 20),
                                    ],
                                  ],
                                ),
                                Text(
                                  '@${page['username']}',
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                ),
                                const SizedBox(height: PageTokens.spaceSm),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    PageStatChip(icon: Icons.category_outlined, label: _pageTypeLabel),
                                    InkWell(
                                      borderRadius: BorderRadius.circular(PageTokens.radiusPill),
                                      onTap: _canViewFollowers ? () => context.push('/page-followers?id=${widget.pageId}') : null,
                                      child: PageStatChip(
                                        icon: Icons.people_alt_outlined,
                                        label: '${page['follower_count'] ?? 0} follower${(page['follower_count'] ?? 0) == 1 ? '' : 's'}',
                                      ),
                                    ),
                                    if (page['location'] != null)
                                      PageStatChip(icon: Icons.place_outlined, label: page['location'] as String),
                                    InkWell(
                                      borderRadius: BorderRadius.circular(PageTokens.radiusPill),
                                      onTap: () => context.push('/page-reviews?id=${widget.pageId}'),
                                      child: PageStatChip(
                                        icon: Icons.star_outline,
                                        color: (page['rating_count'] ?? 0) > 0 ? AppColors.brandTeal : null,
                                        label: (page['rating_count'] ?? 0) > 0
                                            ? '${((page['rating_avg'] as num?) ?? 0).toStringAsFixed(1)} (${page['rating_count']})'
                                            : 'No reviews yet',
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: PageTokens.spaceLg),
                                PageCtaRow(
                                  following: _following,
                                  favorite: _favorite,
                                  busy: _followBusy,
                                  onFollow: _toggleFollow,
                                  onFavorite: _following ? _toggleFavorite : null,
                                  onMessage: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => PageChatScreen(
                                        pageId: widget.pageId,
                                        pageName: page['name'] as String? ?? 'Page',
                                      ),
                                    ),
                                  ),
                                ),
                                if (_allowVisitorPosts) ...[
                                  const SizedBox(height: PageTokens.spaceMd),
                                  if (_canManage || _following)
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        onPressed: _openPostComposer,
                                        icon: const Icon(Icons.edit_outlined),
                                        label: Text(_canManage ? 'Create Page post' : 'Post on this Page'),
                                      ),
                                    )
                                  else
                                    PageVisitorPostFollowGate(busy: _followBusy, onFollow: _toggleFollow),
                                ],
                                if (_hasSubscriptionTiers || _hasMarketplaceItems) ...[
                                  const SizedBox(height: PageTokens.spaceSm),
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      if (_hasSubscriptionTiers)
                                        TextButton.icon(
                                          onPressed: () => context.push('/page-subscriptions?id=${widget.pageId}&name=${Uri.encodeComponent(page['name'] as String? ?? 'Page')}'),
                                          icon: const Icon(Icons.workspace_premium_outlined, size: 16),
                                          label: const Text('Subscriptions'),
                                        ),
                                      if (_hasMarketplaceItems)
                                        TextButton.icon(
                                          onPressed: () => context.push('/page-marketplace?id=${widget.pageId}&name=${Uri.encodeComponent(page['name'] as String? ?? 'Page')}'),
                                          icon: const Icon(Icons.storefront_outlined, size: 16),
                                          label: const Text('Shop'),
                                        ),
                                    ],
                                  ),
                                ],
                                if (page['monetization_enabled'] == true) ...[
                                  const SizedBox(height: PageTokens.spaceMd),
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      onPressed: () => showDonateSheet(
                                        context,
                                        pageId: widget.pageId,
                                        pageName: page['name'] as String? ?? 'this Page',
                                      ),
                                      icon: const Icon(Icons.volunteer_activism_outlined, size: 18),
                                      label: const Text('Support this Page'),
                                    ),
                                  ),
                                ],
                                if ((page['description'] as String?)?.isNotEmpty ?? false) ...[
                                  const SizedBox(height: PageTokens.spaceLg),
                                  Text(page['description'] as String),
                                ],
                                PagePublicPostsSection(pageId: widget.pageId, page: page),
                                const SizedBox(height: PageTokens.spaceLg),
                                const Divider(),
                                const SizedBox(height: PageTokens.spaceSm),
                                if (page['website'] != null)
                                  InkWell(
                                    onTap: () => openExternalLink(context, page['website'] as String),
                                    child: PageInfoRow(icon: Icons.link, text: page['website'] as String),
                                  ),
                                if (page['phone'] != null)
                                  InkWell(
                                    onTap: () => _launchOrSnack(Uri(scheme: 'tel', path: page['phone'] as String)),
                                    child: PageInfoRow(icon: Icons.phone_outlined, text: page['phone'] as String),
                                  ),
                                if (page['email'] != null)
                                  InkWell(
                                    onTap: () => _launchOrSnack(Uri(scheme: 'mailto', path: page['email'] as String)),
                                    child: PageInfoRow(icon: Icons.email_outlined, text: page['email'] as String),
                                  ),
                                if (page['country'] != null) PageInfoRow(icon: Icons.public, text: page['country'] as String),
                                if (_businessHoursNote != null) PageInfoRow(icon: Icons.schedule_outlined, text: _businessHoursNote!),
                                if (_socialLinks.isNotEmpty) ...[
                                  const SizedBox(height: PageTokens.spaceMd),
                                  Text('Social', style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      for (final entry in _socialLinks.entries)
                                        TextButton.icon(
                                          onPressed: () => openExternalLink(context, entry.value),
                                          icon: const Icon(Icons.open_in_new, size: 16),
                                          label: Text(entry.key),
                                        ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
    );
  }
}
