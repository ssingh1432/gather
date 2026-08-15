import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/supabase_client.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/utils/external_link.dart';
import '../../shared/widgets/reusables.dart';
import '../../shared/utils/time_ago.dart';
import '../data/repositories.dart';
import 'page_chat_screen.dart';
import 'page_manage_screen.dart';
import 'donate_sheet.dart';
import 'page_preview_screen.dart' show PageInfoRow;
import 'pages_theme.dart';

/// The premium, public-facing Page profile (Step 6 of the brief) — what
/// anyone visiting a *published* page sees, as opposed to [PagePreviewScreen]
/// which is the owner/team-only draft view reused for "preview before
/// publishing". Reviews (Step 10) and full analytics (Step 11) are
/// separate, later steps; this screen is the identity/contact layer
/// (cover, logo, verified badge, category/location, description, contact
/// info, business hours, social links, Follow/Favorite CTA) plus a
/// read-only preview of published content (Step 7: pinned/recent posts,
/// upcoming events) and a rating chip linking into Reviews (Step 10) so a
/// visitor doesn't have to leave the profile to see them. The follower-count
/// chip deep-links into the Followers screen for anyone with
/// `view_analytics`.
///
/// Management tools (content, inbox, insights, team, settings) used to be
/// five separate, unlabeled `IconButton`s living right here in the public
/// app bar — indistinguishable from visitor-facing icons unless you already
/// knew which ones were yours. They're now consolidated into a single
/// labeled "Manage" entry point that opens [PageManageScreen], per the
/// Pages UX audit: this screen stays focused on being a clean, trustworthy
/// public identity page, and page owners get one obvious place to start
/// instead of a scavenger hunt across the app bar.
class PageProfileScreen extends StatefulWidget {
  const PageProfileScreen({super.key, required this.pageId});
  final String pageId;

  @override
  State<PageProfileScreen> createState() => _PageProfileScreenState();
}

class _PageProfileScreenState extends State<PageProfileScreen> {
  final _repo = PageRepository();
  Map<String, dynamic>? _page;
  bool _loading = true;
  bool _following = false;
  bool _followBusy = false;
  bool _favorite = false;
  bool _canManage = false;
  bool _canViewFollowers = false;
  List<Map<String, dynamic>> _posts = const [];
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
      final canViewFollowers = uid == null ? false : await _repo.hasPagePermission(widget.pageId, 'view_analytics');
      final posts = await _repo.listPagePosts(widget.pageId, status: 'published');
      final events = await _repo.listPageEvents(widget.pageId);
      if (!mounted) return;
      setState(() {
        _page = page;
        _following = followState != null;
        _favorite = followState?['favorite'] as bool? ?? false;
        _canManage = role != null;
        _canViewFollowers = canViewFollowers;
        _posts = posts;
        _events = events.where((e) => DateTime.parse(e['start_time'] as String).isAfter(DateTime.now().subtract(const Duration(days: 1)))).toList();
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load this page. $e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _toggleFollow() async {
    if (SupabaseConfig.currentUserId == null) {
      context.push('/login');
      return;
    }
    setState(() => _followBusy = true);
    final wasFollowing = _following;
    // Optimistic: flip immediately, and nudge the local follower_count so
    // the UI doesn't wait on a round trip + refetch to feel responsive.
    setState(() {
      _following = !wasFollowing;
      final count = (_page?['follower_count'] as int?) ?? 0;
      _page = {..._page!, 'follower_count': wasFollowing ? count - 1 : count + 1};
    });
    try {
      if (wasFollowing) {
        await _repo.unfollowPage(widget.pageId);
      } else {
        await _repo.followPage(widget.pageId);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _following = wasFollowing;
          final count = (_page?['follower_count'] as int?) ?? 0;
          _page = {..._page!, 'follower_count': wasFollowing ? count + 1 : count - 1};
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update follow status: $e')));
      }
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
      if (mounted) {
        setState(() => _favorite = wasFavorite);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update favorite: $e')));
      }
    }
  }

  /// Owner-only: flips on the "Support this page" donate button (Step 15b),
  /// after checking the same eligibility bar check_page_monetization_
  /// eligibility enforces server-side (published, 100+ followers, 30+ days
  /// old) — checked here too so the person gets a clear reason instead of
  /// a raw RLS/constraint failure.
  Future<void> _enableMonetization() async {
    try {
      final eligibility = await _repo.checkPageMonetizationEligibility(widget.pageId);
      if (eligibility['eligible'] != true) {
        final reasons = (eligibility['reasons'] as List?)?.cast<String>() ?? const ['Not eligible yet'];
        if (mounted) {
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Not eligible yet'),
              content: Text(reasons.join('\n')),
              actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
            ),
          );
        }
        return;
      }
      await _repo.updatePage(widget.pageId, {'monetization_enabled': true, 'monetization_status': 'approved'});
      if (mounted) setState(() => _page = {..._page!, 'monetization_enabled': true, 'monetization_status': 'approved'});
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not enable donations: $e')));
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open this link.')));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open this link.')));
    }
  }

  Map<String, String> get _socialLinks {
    final links = _page?['social_links'];
    if (links is Map) {
      return links.map((k, v) => MapEntry(k.toString(), v.toString())).cast<String, String>()
        ..removeWhere((_, v) => v.isEmpty);
    }
    return const {};
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_page?['name'] as String? ?? 'Page', style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          if (_canManage)
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Manage page',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => PageManageScreen(pageId: widget.pageId)),
              ),
            ),
        ],
      ),
      body: _loading
          ? const FeedSkeletonList()
          : _error != null
              ? ErrorRetryState(title: 'Unable to load page', message: _error!, onRetry: _load)
              : _page == null
                  ? const Center(child: Text('Page not found'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.only(bottom: PageTokens.spaceXxl),
                        children: [
                          PageCoverAndLogo(page: _page!),
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
                                        _page!['name'] as String,
                                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                                      ),
                                    ),
                                    if (_page!['verification_status'] == 'verified') ...[
                                      const SizedBox(width: 6),
                                      const Icon(Icons.verified, color: AppColors.brandTeal, size: 20),
                                    ],
                                  ],
                                ),
                                Text(
                                  '@${_page!['username']}',
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
                                        label: '${_page!['follower_count'] ?? 0} follower${(_page!['follower_count'] ?? 0) == 1 ? '' : 's'}',
                                      ),
                                    ),
                                    if (_page!['location'] != null) PageStatChip(icon: Icons.place_outlined, label: _page!['location'] as String),
                                    InkWell(
                                      borderRadius: BorderRadius.circular(PageTokens.radiusPill),
                                      onTap: () => context.push('/page-reviews?id=${widget.pageId}'),
                                      child: PageStatChip(
                                        icon: Icons.star_outline,
                                        color: (_page!['rating_count'] ?? 0) > 0 ? AppColors.brandTeal : null,
                                        label: (_page!['rating_count'] ?? 0) > 0
                                            ? '${((_page!['rating_avg'] as num?) ?? 0).toStringAsFixed(1)} (${_page!['rating_count']})'
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
                                    MaterialPageRoute(builder: (_) => PageChatScreen(pageId: widget.pageId, pageName: _page!['name'] as String? ?? 'Page')),
                                  ),
                                  page: _page!,
                                ),
                                const SizedBox(height: PageTokens.spaceSm),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    TextButton.icon(
                                      onPressed: () => context.push('/page-subscriptions?id=${widget.pageId}&name=${Uri.encodeComponent(_page!['name'] as String? ?? 'Page')}'),
                                      icon: const Icon(Icons.workspace_premium_outlined, size: 16),
                                      label: const Text('Subscriptions'),
                                    ),
                                    TextButton.icon(
                                      onPressed: () => context.push('/page-marketplace?id=${widget.pageId}&name=${Uri.encodeComponent(_page!['name'] as String? ?? 'Page')}'),
                                      icon: const Icon(Icons.storefront_outlined, size: 16),
                                      label: const Text('Shop'),
                                    ),
                                  ],
                                ),
                                if (_page!['monetization_enabled'] == true) ...[
                                  const SizedBox(height: PageTokens.spaceMd),
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      onPressed: () => showDonateSheet(context, pageId: widget.pageId, pageName: _page!['name'] as String? ?? 'this page'),
                                      icon: const Icon(Icons.volunteer_activism_outlined, size: 18),
                                      label: const Text('Support this page'),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PageTokens.radiusPill)),
                                      ),
                                    ),
                                  ),
                                ] else if (_page!['owner_id'] == SupabaseConfig.currentUserId) ...[
                                  const SizedBox(height: PageTokens.spaceMd),
                                  TextButton.icon(
                                    onPressed: _enableMonetization,
                                    icon: const Icon(Icons.volunteer_activism_outlined, size: 16),
                                    label: const Text('Enable donations for this page'),
                                  ),
                                ],
                                if ((_page!['description'] as String?)?.isNotEmpty ?? false) ...[
                                  const SizedBox(height: PageTokens.spaceLg),
                                  Text(_page!['description'] as String),
                                ],
                                const SizedBox(height: PageTokens.spaceLg),
                                const Divider(),
                                const SizedBox(height: PageTokens.spaceSm),
                                if (_page!['website'] != null)
                                  InkWell(
                                    onTap: () => openExternalLink(context, _page!['website'] as String),
                                    child: PageInfoRow(icon: Icons.link, text: _page!['website'] as String),
                                  ),
                                if (_page!['phone'] != null)
                                  InkWell(
                                    onTap: () => _launchOrSnack(Uri(scheme: 'tel', path: _page!['phone'] as String)),
                                    child: PageInfoRow(icon: Icons.phone_outlined, text: _page!['phone'] as String),
                                  ),
                                if (_page!['email'] != null)
                                  InkWell(
                                    onTap: () => _launchOrSnack(Uri(scheme: 'mailto', path: _page!['email'] as String)),
                                    child: PageInfoRow(icon: Icons.email_outlined, text: _page!['email'] as String),
                                  ),
                                if (_page!['country'] != null) PageInfoRow(icon: Icons.public, text: _page!['country'] as String),
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
                                        ActionChip(
                                          avatar: const Icon(Icons.public, size: 16),
                                          label: Text(entry.key),
                                          onPressed: () => openExternalLink(context, entry.value),
                                        ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (_events.isNotEmpty) ...[
                            const Divider(height: PageTokens.spaceXl),
                            PageSectionHeader(title: 'Upcoming events'),
                            for (final e in _events)
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: PageTokens.spaceLg, vertical: 4),
                                child: _ProfileEventCard(event: e),
                              ),
                          ],
                          if (_posts.isNotEmpty) ...[
                            const Divider(height: PageTokens.spaceXl),
                            PageSectionHeader(title: 'Posts'),
                            for (final p in _posts)
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: PageTokens.spaceLg, vertical: 4),
                                child: _ProfilePostCard(post: p),
                              ),
                          ],
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
    required this.page,
  });
  final bool following;
  final bool favorite;
  final bool busy;
  final VoidCallback onFollow;
  final VoidCallback? onFavorite;
  final VoidCallback onMessage;
  final Map<String, dynamic> page;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: following
              ? OutlinedButton.icon(
                  onPressed: busy ? null : onFollow,
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Following'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PageTokens.radiusPill)),
                  ),
                )
              : FilledButton.icon(
                  onPressed: busy ? null : onFollow,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Follow'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brandTeal,
                    foregroundColor: AppColors.onBrandTeal,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PageTokens.radiusPill)),
                  ),
                ),
        ),
        if (following) ...[
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: PageColors.border(context)),
              borderRadius: BorderRadius.circular(PageTokens.radiusPill),
            ),
            child: IconButton(
              onPressed: onFavorite,
              icon: Icon(favorite ? Icons.star : Icons.star_border),
              color: favorite ? Colors.amber[700] : Theme.of(context).colorScheme.onSurfaceVariant,
              tooltip: favorite ? 'Unfavorite' : 'Favorite',
            ),
          ),
        ],
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onMessage,
            icon: const Icon(Icons.chat_bubble_outline, size: 18),
            label: const Text('Message'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PageTokens.radiusPill)),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfilePostCard extends StatefulWidget {
  const _ProfilePostCard({required this.post});
  final Map<String, dynamic> post;

  @override
  State<_ProfilePostCard> createState() => _ProfilePostCardState();
}

class _ProfilePostCardState extends State<_ProfilePostCard> {
  final _analytics = PageAnalyticsRepository();
  Map<String, dynamic> get post => widget.post;

  @override
  void initState() {
    super.initState();
    // Best-effort, fire-and-forget impression recording (Step 11 analytics)
    // — the profile feed isn't lazily built, so this fires when the post
    // card is composed into the tree, which is a reasonable proxy for "the
    // post rendered on screen" for this list size.
    final id = post['id'] as String?;
    if (id != null) _analytics.recordImpression(id);
  }

  @override
  Widget build(BuildContext context) {
    final type = post['post_type'] as String;
    final pinned = post['pinned'] as bool? ?? false;
    final content = post['content'] as String? ?? '';
    final media = post['media'];
    final imageUrl = media is List && media.isNotEmpty && media.first is Map ? (media.first as Map)['url'] as String? : null;
    final publishedAt = post['published_at'] as String? ?? post['created_at'] as String?;

    return Container(
      padding: const EdgeInsets.all(PageTokens.spaceMd),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: PageColors.surfaceCard(context),
        borderRadius: BorderRadius.circular(PageTokens.radiusMd),
        border: Border.all(color: PageColors.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (pinned) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.push_pin, size: 14, color: AppColors.brandTeal)),
              PageStatChip(icon: kPagePostTypeIcons[type] ?? Icons.article_outlined, label: kPagePostTypes[type] ?? type),
              const Spacer(),
              if (publishedAt != null) Text(timeAgo(DateTime.parse(publishedAt)), style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
          if (content.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(content),
          ],
          if (imageUrl != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(PageTokens.radiusSm),
              child: Image.network(imageUrl, width: double.infinity, height: 180, fit: BoxFit.cover),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProfileEventCard extends StatelessWidget {
  const _ProfileEventCard({required this.event});
  final Map<String, dynamic> event;

  @override
  Widget build(BuildContext context) {
    final start = DateTime.parse(event['start_time'] as String).toLocal();
    return Container(
      padding: const EdgeInsets.all(PageTokens.spaceMd),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: PageColors.surfaceCard(context),
        borderRadius: BorderRadius.circular(PageTokens.radiusMd),
        border: Border.all(color: PageColors.border(context)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.brandTeal.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(PageTokens.radiusSm)),
            child: const Icon(Icons.event, color: AppColors.brandTeal, size: 20),
          ),
          const SizedBox(width: PageTokens.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event['title'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  '${start.day}/${start.month}/${start.year} · ${TimeOfDay.fromDateTime(start).format(context)}${event['location'] != null ? ' · ${event['location']}' : ''}',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
