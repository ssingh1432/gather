import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase_client.dart';
import '../../core/theme/app_theme.dart';
import '../../features/data/repositories.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/auth_redirects.dart';
import '../../shared/widgets/reusables.dart';
import 'community_theme.dart';

class CommunityDetailScreen extends StatefulWidget {
  const CommunityDetailScreen({super.key, this.communityId = ''});
  final String communityId;

  @override
  State<CommunityDetailScreen> createState() => _CommunityDetailScreenState();
}

class _CommunityDetailScreenState extends State<CommunityDetailScreen> {
  static const int _pageSize = 20;
  static const double _preloadExtent = 640;

  final repo = FeedRepository();
  final communityRepo = CommunityRepository();
  final postCtrl = TextEditingController();
  final _scrollController = ScrollController();

  Map<String, dynamic>? _community;
  String? _myRole;
  bool _joinRequestPending = false;
  List<String> _tags = const [];
  Map<String, dynamic>? _activitySummary;
  String? _announcementText;
  bool _canManagePosts = false;
  bool _canViewAnalytics = false;

  Set<String> liked = <String>{};
  Set<String> bookmarked = <String>{};
  List<PostModel> _posts = const [];
  int _nextPage = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _posting = false;
  bool _joining = false;
  String? _error;

  String? get _uid => SupabaseConfig.maybeClient?.auth.currentUser?.id;
  bool get _isMember => _myRole != null;
  bool get _canManage => _myRole == 'owner' || _myRole == 'admin' || _myRole == 'moderator';
  bool get _isPrivate => const {'private', 'secret', 'invite_only'}.contains(_community?['visibility']);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_maybePreloadNextPage);
    _load();
  }

  @override
  void dispose() {
    postCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _nextPage = 0;
      _hasMore = true;
    });
    try {
      final community = await communityRepo.getCommunity(widget.communityId);
      final uid = _uid;
      String? role;
      if (uid != null) role = await communityRepo.myRole(widget.communityId, uid);
      _community = community;
      _myRole = role;
      if (community != null) {
        _tags = await communityRepo.getCommunityTags(widget.communityId);
        _activitySummary = await communityRepo.getCommunityActivitySummary(widget.communityId);
        _canManagePosts = await communityRepo.hasPermission(widget.communityId, 'manage_posts');
        _canViewAnalytics = await communityRepo.hasPermission(widget.communityId, 'view_analytics');
        final announcementPostId = community['pinned_announcement_post_id'] as String?;
        _announcementText = announcementPostId == null ? null : await communityRepo.getPostPreview(announcementPostId);
      }
      if (!_isPrivate || _isMember) {
        final posts = await _fetchPage(0);
        _posts = posts;
        _nextPage = 1;
        _hasMore = posts.length == _pageSize;
        await _refreshStates(_posts.map((e) => e.id).toList());
      } else {
        _posts = const [];
        _hasMore = false;
      }
    } catch (e) {
      _error = 'Network failure. Check your connection and try again.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<PostModel>> _fetchPage(int page) async {
    return repo.communityFeed(widget.communityId, userId: _uid, page: page, pageSize: _pageSize);
  }

  Future<void> _refreshStates(List<String> ids) async {
    final uid = _uid;
    if (uid != null && ids.isNotEmpty) {
      liked = await repo.likedPostIds(uid, ids);
      bookmarked = await repo.bookmarkedPostIds(uid, ids);
    } else {
      liked = <String>{};
      bookmarked = <String>{};
    }
  }

  Future<void> _loadNextPage() async {
    if (_loading || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = _nextPage;
      final posts = await _fetchPage(page);
      final seen = _posts.map((p) => p.id).toSet();
      _posts = [..._posts, ...posts.where((p) => !seen.contains(p.id))];
      _nextPage = page + 1;
      _hasMore = posts.length == _pageSize;
      await _refreshStates(_posts.map((e) => e.id).toList());
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not load more posts.'),
            action: SnackBarAction(label: 'Retry', onPressed: _loadNextPage),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _maybePreloadNextPage() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter < _preloadExtent) _loadNextPage();
  }

  Future<void> _publishCommunityPost() async {
    final uid = _uid;
    if (uid == null) {
      redirectToLogin(context, redirect: '/community?id=${widget.communityId}', message: 'Please log in or create an account to create a post.');
      return;
    }
    if (postCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Post text cannot be empty.')));
      return;
    }
    setState(() => _posting = true);
    try {
      await PostRepository().createPost({'author_id': uid, 'community_id': widget.communityId, 'text_content': postCtrl.text.trim()});
      postCtrl.clear();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Post published.')));
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Upload failed. Check your connection and retry.'),
            action: SnackBarAction(label: 'Retry', onPressed: _publishCommunityPost),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _handleJoinLeave() async {
    final uid = _uid;
    if (uid == null) {
      redirectToLogin(context, redirect: '/community?id=${widget.communityId}', message: 'Please log in or create an account to join this community.');
      return;
    }
    setState(() => _joining = true);
    try {
      if (_isMember) {
        if (_myRole == 'owner') {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('As the owner, you can\'t leave. Delete the community instead if you want to shut it down.')),
            );
          }
          return;
        }
        await communityRepo.leaveCommunity(widget.communityId, uid);
      } else {
        final result = await communityRepo.requestJoin(widget.communityId);
        if (result == 'requested' && mounted) {
          setState(() => _joinRequestPending = true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Join request sent. An owner or admin will review it.')),
          );
        }
      }
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update membership: $e')));
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  Future<void> _openAnnouncementPicker() async {
    List<Map<String, dynamic>> recentPosts = const [];
    try {
      recentPosts = await communityRepo.listRecentCommunityPosts(widget.communityId);
    } catch (_) {
    }
    if (!mounted) return;
    final choice = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pinned announcement'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_announcementText != null)
                ListTile(
                  leading: const Icon(Icons.clear, color: Colors.red),
                  title: const Text('Clear announcement'),
                  onTap: () => Navigator.pop(ctx, ''),
                ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final p in recentPosts)
                      ListTile(
                        title: Text((p['text_content'] as String? ?? '').isEmpty ? '(no text)' : p['text_content'] as String, maxLines: 2, overflow: TextOverflow.ellipsis),
                        onTap: () => Navigator.pop(ctx, p['id'] as String),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel'))],
      ),
    );
    if (choice == null || !mounted) return;
    try {
      await communityRepo.setCommunityAnnouncement(widget.communityId, choice.isEmpty ? null : choice);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update announcement: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _community;
    return Scaffold(
      appBar: AppBar(
        title: Text(c?['name'] as String? ?? 'Community', style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          if (_canViewAnalytics)
            IconButton(icon: const Icon(Icons.insights_outlined), tooltip: 'Insights', onPressed: () => context.push('/community-analytics?id=${widget.communityId}&name=${Uri.encodeComponent(c?['name'] as String? ?? '')}')),
          IconButton(icon: const Icon(Icons.event_outlined), tooltip: 'Events', onPressed: () => context.push('/community-events?id=${widget.communityId}&name=${Uri.encodeComponent(c?['name'] as String? ?? '')}')),
          if (_isMember)
            IconButton(icon: const Icon(Icons.forum_outlined), tooltip: 'Chat', onPressed: () => context.push('/community-chat?id=${widget.communityId}&name=${Uri.encodeComponent(c?['name'] as String? ?? '')}')),
          if (_isMember)
            IconButton(icon: const Icon(Icons.people_outline), tooltip: 'Members', onPressed: () => context.push('/community-members?id=${widget.communityId}')),
          if (_canManagePosts)
            IconButton(icon: const Icon(Icons.campaign_outlined), tooltip: 'Manage announcement', onPressed: _openAnnouncementPicker),
          if (_canManage)
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Manage community',
              onPressed: () async {
                await context.push('/edit-community?id=${widget.communityId}');
                if (mounted) _load();
              },
            ),
        ],
      ),
      body: _loading
          ? const FeedSkeletonList()
          : _error != null
              ? ErrorRetryState(title: 'Unable to load community', message: _error!, onRetry: _load)
              : c == null
                  ? const EmptyState(icon: Icons.error_outline, title: 'Community not found')
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: CustomScrollView(
                        controller: _scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverToBoxAdapter(child: _Header(community: c, myRole: _myRole, joining: _joining, onJoinLeave: _handleJoinLeave, tags: _tags, announcementText: _announcementText, activitySummary: _activitySummary)),
                          if (_isMember)
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(CommunityTokens.spaceLg, CommunityTokens.spaceSm, CommunityTokens.spaceLg, CommunityTokens.spaceMd),
                                child: Container(
                                  padding: const EdgeInsets.all(CommunityTokens.spaceMd),
                                  decoration: BoxDecoration(
                                    color: CommunityColors.surfaceCard(context),
                                    borderRadius: BorderRadius.circular(CommunityTokens.radiusMd),
                                    border: Border.all(color: CommunityColors.border(context)),
                                    boxShadow: CommunityTokens.subtleShadow(context),
                                  ),
                                  child: Column(children: [
                                    TextField(
                                      controller: postCtrl,
                                      minLines: 1,
                                      maxLines: 5,
                                      decoration: InputDecoration(
                                        hintText: 'Share something with the community…',
                                        filled: true,
                                        fillColor: CommunityColors.surfaceMuted(context),
                                        contentPadding: const EdgeInsets.all(CommunityTokens.spaceMd),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(CommunityTokens.radiusSm),
                                          borderSide: BorderSide.none,
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(CommunityTokens.radiusSm),
                                          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: CommunityTokens.spaceSm),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: FilledButton(
                                        onPressed: _posting ? null : _publishCommunityPost,
                                        style: FilledButton.styleFrom(
                                          backgroundColor: Theme.of(context).colorScheme.primary,
                                          foregroundColor: Theme.of(context).colorScheme.onPrimary,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CommunityTokens.radiusPill)),
                                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                        ),
                                        child: _posting
                                            ? SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.onPrimary))
                                            : const Text('Post', style: TextStyle(fontWeight: FontWeight.w600)),
                                      ),
                                    ),
                                  ]),
                                ),
                              ),
                            ),
                          if (_isPrivate && !_isMember)
                            SliverFillRemaining(
                              child: EmptyState(
                                icon: Icons.lock_outline,
                                title: 'This community is private',
                                message: _joinRequestPending ? 'Your request to join has been sent.' : 'Request to join to see posts and take part in the conversation.',
                              ),
                            )
                          else if (_posts.isEmpty)
                            const SliverFillRemaining(child: EmptyState(icon: Icons.forum_outlined, title: 'No posts', message: 'Be the first to start this community conversation.'))
                          else
                            SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  if (index >= _posts.length) {
                                    return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
                                  }
                                  final p = _posts[index];
                                  return PostCard(
                                    post: p,
                                    liked: liked.contains(p.id) || p.isLiked,
                                    bookmarked: bookmarked.contains(p.id) || p.isBookmarked,
                                    onLike: () async {
                                      final uid = _uid;
                                      if (uid == null) {
                                        redirectToLogin(context, redirect: '/community?id=${widget.communityId}', message: 'Please log in or create an account to like posts.');
                                        return;
                                      }
                                      if (liked.contains(p.id) || p.isLiked) await repo.unlikePost(p.id, uid); else await repo.likePost(p.id, uid);
                                      await _refreshStates(_posts.map((e) => e.id).toList());
                                      if (mounted) setState(() {});
                                    },
                                    onComment: () {
                                      final uid = _uid;
                                      if (uid == null) {
                                        redirectToLogin(context, redirect: '/post?id=${p.id}', message: 'Please log in or create an account to comment.');
                                        return;
                                      }
                                      context.push('/post?id=${p.id}');
                                    },
                                    onBookmark: () async {
                                      final uid = _uid;
                                      if (uid == null) {
                                        redirectToLogin(context, redirect: '/community?id=${widget.communityId}', message: 'Please log in or create an account to save posts.');
                                        return;
                                      }
                                      if (bookmarked.contains(p.id) || p.isBookmarked) await repo.unbookmarkPost(p.id, uid); else await repo.bookmarkPost(p.id, uid);
                                      await _refreshStates(_posts.map((e) => e.id).toList());
                                      if (mounted) setState(() {});
                                    },
                                  );
                                },
                                childCount: _posts.length + (_loadingMore ? 1 : 0),
                              ),
                            ),
                        ],
                      ),
                    ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.community,
    required this.myRole,
    required this.joining,
    required this.onJoinLeave,
    this.tags = const [],
    this.announcementText,
    this.activitySummary,
  });

  final Map<String, dynamic> community;
  final String? myRole;
  final bool joining;
  final VoidCallback onJoinLeave;
  final List<String> tags;
  final String? announcementText;
  final Map<String, dynamic>? activitySummary;

  @override
  Widget build(BuildContext context) {
    final bannerUrl = community['banner_url'] as String?;
    final iconUrl = community['image_url'] as String?;
    final visibility = community['visibility'] as String? ?? 'public';
    final isPrivate = visibility != 'public';
    final memberCount = (community['member_count'] as num?)?.toInt() ?? 0;
    final isMember = myRole != null;
    final hasBanner = bannerUrl != null && bannerUrl.isNotEmpty;
    final hasIcon = iconUrl != null && iconUrl.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            AspectRatio(
              aspectRatio: 3,
              child: hasBanner ? Image.network(bannerUrl, fit: BoxFit.cover) : Container(decoration: BoxDecoration(gradient: CommunityColors.bannerFallbackGradient(context))),
            ),
            Positioned(
              left: CommunityTokens.spaceLg,
              bottom: -34,
              child: Container(
                width: 76,
                height: 76,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(shape: BoxShape.circle, color: Theme.of(context).scaffoldBackgroundColor),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: hasIcon ? null : CommunityColors.bannerFallbackGradient(context),
                    image: hasIcon ? DecorationImage(image: NetworkImage(iconUrl), fit: BoxFit.cover) : null,
                  ),
                  child: hasIcon ? null : const Icon(Icons.groups, color: Colors.white, size: 28),
                ),
              ),
            ),
          ],
        ),
        if (announcementText != null && announcementText!.trim().isNotEmpty)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(CommunityTokens.spaceLg, CommunityTokens.spaceLg, CommunityTokens.spaceLg, 0),
            padding: const EdgeInsets.all(CommunityTokens.spaceMd),
            decoration: BoxDecoration(
              color: AppColors.brandTealLight.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(CommunityTokens.radiusSm),
              border: Border.all(color: AppColors.brandTeal.withValues(alpha: 0.35)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.campaign, size: 18, color: AppColors.brandTeal),
                const SizedBox(width: 8),
                Expanded(child: Text(announcementText!, maxLines: 3, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(CommunityTokens.spaceLg, CommunityTokens.spaceLg, CommunityTokens.spaceLg, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(child: Text(community['name'] ?? '', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis)),
                if (isPrivate) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.lock_outline, size: 16)),
                if (community['is_verified'] == true) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.verified, size: 16, color: AppColors.brandTeal)),
              ]),
              if ((community['category'] as String?)?.isNotEmpty ?? false) ...[
                const SizedBox(height: 2),
                Text(community['category'] as String, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
              if ((community['description'] as String?)?.isNotEmpty ?? false) ...[
                const SizedBox(height: CommunityTokens.spaceSm),
                Text(community['description'], style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.4)),
              ],
              const SizedBox(height: CommunityTokens.spaceMd),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  CommunityStatChip(icon: Icons.groups_outlined, label: '$memberCount member${memberCount == 1 ? '' : 's'}'),
                  if (activitySummary != null) CommunityStatChip(icon: Icons.local_fire_department_outlined, label: '${activitySummary!['posts_last_24h'] ?? 0} posts today'),
                  if (activitySummary != null) CommunityStatChip(icon: Icons.person_add_alt_outlined, label: '${activitySummary!['new_members_last_7d'] ?? 0} new this week'),
                  if (myRole != null && myRole != 'member') CommunityStatChip(icon: Icons.shield_outlined, label: myRole!, color: AppColors.brandTeal),
                ],
              ),
              if (tags.isNotEmpty) ...[
                const SizedBox(height: CommunityTokens.spaceSm),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final t in tags)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(border: Border.all(color: CommunityColors.border(context)), borderRadius: BorderRadius.circular(CommunityTokens.radiusPill)),
                        child: Text('#$t', style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(CommunityTokens.spaceLg, CommunityTokens.spaceLg, CommunityTokens.spaceLg, CommunityTokens.spaceSm),
          child: SizedBox(
            width: double.infinity,
            child: myRole == 'owner'
                ? const SizedBox.shrink()
                : OutlinedButton(
                    onPressed: joining || (!isMember && visibility != 'public' && visibility != 'private') ? null : onJoinLeave,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CommunityTokens.radiusPill)),
                      side: BorderSide(color: isMember ? CommunityColors.border(context) : AppColors.brandTeal),
                      foregroundColor: isMember ? null : AppColors.brandTeal,
                    ),
                    child: joining ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Text(isMember ? 'Leave community' : (visibility == 'private' ? 'Request to join' : (isPrivate ? 'Ask for an invite' : 'Join community')), style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
          ),
        ),
        const Divider(height: CommunityTokens.spaceLg),
      ],
    );
  }
}
