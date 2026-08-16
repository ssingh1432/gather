import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/supabase_client.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/utils/external_link.dart';
import '../../shared/utils/time_ago.dart';
import '../../shared/widgets/reusables.dart';
import '../data/repositories.dart';
import 'donate_sheet.dart';
import 'page_chat_screen.dart';
import 'page_local_repository.dart';
import 'page_manage_screen.dart';
import 'page_preview_screen.dart' show PageInfoRow;
import 'pages_theme.dart';

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
  List<Map<String, dynamic>> _posts = const [];
  List<Map<String, dynamic>> _visitorPosts = const [];
  List<Map<String, dynamic>> _events = const [];
  String? _error;

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
      final uid = SupabaseConfig.currentUserId;
      final followState = uid == null ? null : await _repo.getFollowState(widget.pageId);
      final role = uid == null ? null : await _repo.currentUserPageRole(widget.pageId);
      final canViewFollowers = uid == null
          ? false
          : await _repo.hasPagePermission(widget.pageId, 'view_analytics');
      final posts = await _repo.listPagePosts(widget.pageId, status: 'published');
      final events = await _repo.listPageEvents(widget.pageId);
      final hasTiers = await _repo.hasVisibleSubscriptionTiers(widget.pageId);
      final hasItems = await _repo.hasVisibleMarketplaceItems(widget.pageId);
      final visitorSettings = await _localRepo.getVisitorPostingSettings(widget.pageId);
      final visitorPosts = await _localRepo.listVisitorPosts(widget.pageId);

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
        _posts = posts;
        _visitorPosts = visitorPosts;
        _events = events
            .where(
              (event) => DateTime.parse(event['start_time'] as String).isAfter(
                DateTime.now().subtract(const Duration(days: 1)),
              ),
            )
            .toList();
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

  Future<void> _createVisitorPost() async {
    if (SupabaseConfig.currentUserId == null) {
      context.push('/login');
      return;
    }

    final controller = TextEditingController();
    try {
      final submitted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          final user = SupabaseConfig.currentUser;
          final displayName = user?.userMetadata?['display_name']?.toString().trim();
          final username = user?.userMetadata?['username']?.toString().trim();
          final authorLabel = (displayName?.isNotEmpty == true)
              ? displayName!
              : (username?.isNotEmpty == true ? '@$username' : 'Your account');
          final pageName = _page?['name']?.toString() ?? 'this Page';

          return AlertDialog(
            title: Text('Post on $pageName'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(dialogContext).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.person_outline),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              const TextSpan(text: 'Posting as '),
                              TextSpan(
                                text: authorLabel,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              const TextSpan(text: ' on '),
                              TextSpan(
                                text: pageName,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_visitorPostsRequireApproval) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'This Page reviews visitor posts before they become public.',
                    style: TextStyle(fontSize: 13),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLines: 6,
                  maxLength: 5000,
                  decoration: const InputDecoration(
                    hintText: 'Write something for this Page…',
                    border: OutlineInputBorder(),
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
                  final content = controller.text.trim();
                  if (content.isEmpty) return;
                  try {
                    await _localRepo.createVisitorPost(widget.pageId, content);
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext, true);
                    }
                  } catch (e) {
                    if (dialogContext.mounted) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(content: Text('Could not post: $e')),
                      );
                    }
                  }
                },
                child: Text(_visitorPostsRequireApproval ? 'Submit for review' : 'Post'),
              ),
            ],
          );
        },
      );

      if (submitted == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _visitorPostsRequireApproval
                  ? 'Your post was sent to ${{_page?['name'] ?? 'this Page'}} for review.'
                  : 'Your post is now visible on ${_page?['name'] ?? 'this Page'}.',
            ),
          ),
        );
        await _load();
      }
    } finally {
      controller.dispose();
    }
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

  Future<void> _enableMonetization() async {
    try {
      final eligibility = await _repo.checkPageMonetizationEligibility(widget.pageId);
      if (eligibility['eligible'] != true) {
        final reasons = (eligibility['reasons'] as List?)?.cast<String>() ??
            const ['Not eligible yet'];
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Not eligible yet'),
            content: Text(reasons.join('\n')),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }

      await _repo.updatePage(widget.pageId, {
        'monetization_enabled': true,
        'monetization_status': 'approved',
      });

      if (!mounted) return;
      setState(() {
        _page = {
          ..._page!,
          'monetization_enabled': true,
          'monetization_status': 'approved',
        };
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not enable donations: $e')),
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
                        padding: const EdgeInsets.only(
                          bottom: PageTokens.spaceXxl,
                        ),
                        children: [
                          PageCoverAndLogo(page: page),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: PageTokens.spaceLg,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 40),
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        page['name'] as String,
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineSmall
                                            ?.copyWith(fontWeight: FontWeight.w800),
                                      ),
                                    ),
                                    if (page['verification_status'] == 'verified') ...[
                                      const SizedBox(width: 6),
                                      const Icon(
                                        Icons.verified,
                                        color: AppColors.brandTeal,
                                        size: 20,
                                      ),
                                    ],
                                  ],
                                ),
                                Text(
                                  '@${page['username']}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                ),
                                const SizedBox(height: PageTokens.spaceSm),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    PageStatChip(
                                      icon: Icons.category_outlined,
                                      label: _pageTypeLabel,
                                    ),
                                    InkWell(
                                      borderRadius: BorderRadius.circular(
                                        PageTokens.radiusPill,
                                      ),
                                      onTap: _canViewFollowers
                                          ? () => context.push(
                                                '/page-followers?id=${widget.pageId}',
                                              )
                                          : null,
                                      child: PageStatChip(
                                        icon: Icons.people_alt_outlined,
                                        label:
                                            '${page['follower_count'] ?? 0} follower${(page['follower_count'] ?? 0) == 1 ? '' : 's'}',
                                      ),
                                    ),
                                    if (page['location'] != null)
                                      PageStatChip(
                                        icon: Icons.place_outlined,
                                        label: page['location'] as String,
                                      ),
                                    InkWell(
                                      borderRadius: BorderRadius.circular(
                                        PageTokens.radiusPill,
                                      ),
                                      onTap: () => context.push(
                                        '/page-reviews?id=${widget.pageId}',
                                      ),
                                      child: PageStatChip(
                                        icon: Icons.star_outline,
                                        color: (page['rating_count'] ?? 0) > 0
                                            ? AppColors.brandTeal
                                            : null,
                                        label: (page['rating_count'] ?? 0) > 0
                                            ? '${((page['rating_avg'] as num?) ?? 0).toStringAsFixed(1)} (${page['rating_count']})'
                                            : 'No reviews yet',
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: PageTokens.spaceLg),
                                _CtaRow(
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
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      onPressed: _createVisitorPost,
                                      icon: const Icon(Icons.edit_outlined),
                                      label: const Text('Post on this Page'),
                                    ),
                                  ),
                                ],
                                if (_hasSubscriptionTiers || _hasMarketplaceItems) ...[
                                  const SizedBox(height: PageTokens.spaceSm),
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      if (_hasSubscriptionTiers)
                                        TextButton.icon(
                                          onPressed: () => context.push(
                                            '/page-subscriptions?id=${widget.pageId}&name=${Uri.encodeComponent(page['name'] as String? ?? 'Page')}',
                                          ),
                                          icon: const Icon(Icons.workspace_premium_outlined, size: 16),
                                          label: const Text('Subscriptions'),
                                        ),
                                      if (_hasMarketplaceItems)
                                        TextButton.icon(
                                          onPressed: () => context.push(
                                            '/page-marketplace?id=${widget.pageId}&name=${Uri.encodeComponent(page['name'] as String? ?? 'Page')}',
                                          ),
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
                                      onPressed: _enableMonetization,
                                      icon: const Icon(Icons.favorite_outline),
                                      label: const Text('Support this Page'),
                                    ),
                                  ),
                                ],
                                if ((page['description'] as String?)?.isNotEmpty == true) ...[
                                  const SizedBox(height: PageTokens.spaceXl),
                                  Text(
                                    page['description'] as String,
                                    style: Theme.of(context).textTheme.bodyLarge,
                                  ),
                                ],
                                if ((page['category'] as String?)?.isNotEmpty == true) ...[
                                  const SizedBox(height: PageTokens.spaceSm),
                                  PageInfoRow(
                                    icon: Icons.label_outline,
                                    label: 'Category',
                                    value: page['category'] as String,
                                  ),
                                ],
                                if ((page['phone'] as String?)?.isNotEmpty == true) ...[
                                  const SizedBox(height: PageTokens.spaceSm),
                                  PageInfoRow(
                                    icon: Icons.phone_outlined,
                                    label: 'Phone',
                                    value: page['phone'] as String,
                                    onTap: () => _launchOrSnack(Uri.parse('tel:${page['phone']}')),
                                  ),
                                ],
                                if ((page['email'] as String?)?.isNotEmpty == true) ...[
                                  const SizedBox(height: PageTokens.spaceSm),
                                  PageInfoRow(
                                    icon: Icons.email_outlined,
                                    label: 'Email',
                                    value: page['email'] as String,
                                    onTap: () => _launchOrSnack(Uri.parse('mailto:${page['email']}')),
                                  ),
                                ],
                                if ((page['website'] as String?)?.isNotEmpty == true) ...[
                                  const SizedBox(height: PageTokens.spaceSm),
                                  PageInfoRow(
                                    icon: Icons.language_outlined,
                                    label: 'Website',
                                    value: page['website'] as String,
                                    onTap: () => _launchOrSnack(Uri.parse(normalizeExternalUrl(page['website'] as String))),
                                  ),
                                ],
                                if (_socialLinks.isNotEmpty) ...[
                                  const SizedBox(height: PageTokens.spaceSm),
                                  ..._socialLinks.entries.map(
                                    (entry) => Padding(
                                      padding: const EdgeInsets.only(bottom: PageTokens.spaceSm),
                                      child: PageInfoRow(
                                        icon: Icons.link,
                                        label: entry.key,
                                        value: entry.value,
                                        onTap: () => _launchOrSnack(Uri.parse(normalizeExternalUrl(entry.value))),
                                      ),
                                    ),
                                  ),
                                ],
                                if (_businessHoursNote != null) ...[
                                  const SizedBox(height: PageTokens.spaceSm),
                                  PageInfoRow(
                                    icon: Icons.schedule_outlined,
                                    label: 'Hours',
                                    value: _businessHoursNote!,
                                  ),
                                ],
                                if (_events.isNotEmpty) ...[
                                  const SizedBox(height: PageTokens.spaceXl),
                                  Text(
                                    'Upcoming events',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: PageTokens.spaceSm),
                                  ..._events.map((event) => _EventCard(event: event)),
                                ],
                                const SizedBox(height: PageTokens.spaceXl),
                                Text(
                                  'Posts',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: PageTokens.spaceSm),
                                if (_posts.isEmpty)
                                  const PageEmptyState(
                                    icon: Icons.article_outlined,
                                    title: 'No posts yet',
                                    message: 'This Page has not published anything yet.',
                                  )
                                else
                                  ..._posts.map((post) => _PagePostCard(post: post)),
                                if (_allowVisitorPosts) ...[
                                  const SizedBox(height: PageTokens.spaceXl),
                                  Text(
                                    'Posts by visitors',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: PageTokens.spaceSm),
                                  if (_visitorPosts.isEmpty)
                                    const PageEmptyState(
                                      icon: Icons.forum_outlined,
                                      title: 'No visitor posts yet',
                                      message: 'Be the first to post on this Page.',
                                    )
                                  else
                                    ..._visitorPosts.map(
                                      (post) => _VisitorPostCard(post: post),
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

class _CtaRow extends StatelessWidget {
  const _CtaRow({
    required this.following,
    required this.favorite,
    required this.busy,
    required this.onFollow,
    required this.onFavorite,
    required this.onMessage,
  });

  final bool following;
  final bool favorite;
  final bool busy;
  final VoidCallback onFollow;
  final VoidCallback? onFavorite;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: busy ? null : onFollow,
            icon: Icon(following ? Icons.check : Icons.add),
            label: Text(following ? 'Following' : 'Follow'),
          ),
        ),
        const SizedBox(width: PageTokens.spaceSm),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onMessage,
            icon: const Icon(Icons.message_outlined),
            label: const Text('Message'),
          ),
        ),
        if (following && onFavorite != null) ...[
          const SizedBox(width: PageTokens.spaceSm),
          IconButton(
            tooltip: favorite ? 'Remove favorite' : 'Add favorite',
            onPressed: onFavorite,
            icon: Icon(favorite ? Icons.star : Icons.star_border),
          ),
        ],
      ],
    );
  }
}

class _PagePostCard extends StatelessWidget {
  const _PagePostCard({required this.post});
  final Map<String, dynamic> post;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: PageTokens.spaceSm),
      child: Padding(
        padding: const EdgeInsets.all(PageTokens.spaceMd),
        child: Text(post['content'] as String? ?? ''),
      ),
    );
  }
}

class _VisitorPostCard extends StatelessWidget {
  const _VisitorPostCard({required this.post});
  final Map<String, dynamic> post;

  @override
  Widget build(BuildContext context) {
    final author = post['users'] is Map ? post['users'] as Map : const <String, dynamic>{};
    final displayName = author['display_name']?.toString();
    final username = author['username']?.toString();
    final authorLabel = (displayName?.isNotEmpty == true)
        ? displayName!
        : (username?.isNotEmpty == true ? '@$username' : 'Gather user');

    return Card(
      margin: const EdgeInsets.only(bottom: PageTokens.spaceSm),
      child: Padding(
        padding: const EdgeInsets.all(PageTokens.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              authorLabel,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (username?.isNotEmpty == true && displayName?.isNotEmpty == true)
              Text(
                '@$username',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: 6),
            Text(post['content'] as String? ?? ''),
          ],
        ),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event});
  final Map<String, dynamic> event;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: PageTokens.spaceSm),
      child: ListTile(
        leading: const Icon(Icons.event_outlined),
        title: Text(event['title'] as String? ?? 'Event'),
        subtitle: Text(event['description'] as String? ?? ''),
      ),
    );
  }
}
