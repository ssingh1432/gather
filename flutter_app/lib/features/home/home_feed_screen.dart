import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase_client.dart';
import '../../features/data/repositories.dart';
import '../../shared/models/models.dart';
import '../../shared/services/analytics_service.dart';
import '../../shared/services/beta_error_logging_service.dart';
import '../../shared/services/feed_offline_cache.dart';
import '../../shared/services/feed_realtime_service.dart';
import '../../shared/widgets/auth_redirects.dart';
import '../../shared/widgets/reusables.dart';
import '../../shared/widgets/composer_prompt.dart';
import '../../shared/widgets/people_you_may_know.dart';
import '../../shared/widgets/suggested_communities.dart';
import '../../shared/widgets/suggested_pages.dart';
import '../../shared/widgets/inline_post_comments.dart';
import '../../shared/widgets/feed_ad_card.dart';
import '../../shared/widgets/story_bar.dart';
import '../../shared/widgets/top_bar_profile_link.dart';
import '../../shared/widgets/notification_bell.dart';
import '../pages/page_visitor_post_home_card.dart';
import '../pages/page_owner_post_home_card.dart';
import '../../shared/providers/app_providers.dart';
import '../../shared/services/remote_config_service.dart';

class HomeFeedScreen extends ConsumerStatefulWidget {
  const HomeFeedScreen({super.key});
  @override
  ConsumerState<HomeFeedScreen> createState() => _S();
}

class _AdSlot { const _AdSlot(this.postId); final String postId; }
class _PYMKSlot { const _PYMKSlot(); }
class _SuggestedCommunitiesSlot { const _SuggestedCommunitiesSlot(); }
class _SuggestedPagesSlot { const _SuggestedPagesSlot(); }

class _S extends ConsumerState<HomeFeedScreen> {
  static const int _pageSize = 20;
  static const double _preloadExtent = 640;
  final repo = FeedRepository();
  final _scrollController = ScrollController();
  Set<String> liked = <String>{};
  Set<String> bookmarked = <String>{};
  final Set<String> _expandedComments = <String>{};
  List<PostModel> _posts = const [];
  FeedCursor? _cursor;
  int _anonPage = 0;
  bool _loadingInitial = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  Timer? _noInteractionTimer;
  bool _feedInteracted = false;
  DateTime? _cachedAsOf;
  final _realtime = FeedRealtimeService();
  StreamSubscription<FeedRealtimeEvent>? _realtimeSub;
  bool _newPostsAvailable = false;

  @override
  void initState() {
    super.initState();
    _guardBannedUser();
    _scrollController.addListener(_maybePreloadNextPage);
    _loadInitial();
    _realtimeSub = _realtime.subscribe().listen(_handleRealtimeEvent);
  }

  @override
  void dispose() {
    _noInteractionTimer?.cancel();
    _scrollController.dispose();
    _realtimeSub?.cancel();
    _realtime.dispose();
    super.dispose();
  }

  void _handleRealtimeEvent(FeedRealtimeEvent event) {
    if (!mounted) return;
    final uid = SupabaseConfig.currentUserId;
    if (event.type == FeedRealtimeEventType.newPost) {
      if (event.authorId != null && event.authorId == uid) return;
      setState(() => _newPostsAvailable = true);
      return;
    }
    final postId = event.postId;
    if (postId == null) return;
    final index = _posts.indexWhere((p) => p.id == postId);
    if (index == -1) return;
    final post = _posts[index];
    setState(() {
      final updated = switch (event.type) {
        FeedRealtimeEventType.likeCountDelta => post.copyWith(likeCount: post.likeCount + event.delta < 0 ? 0 : post.likeCount + event.delta),
        FeedRealtimeEventType.commentCountDelta => post.copyWith(commentCount: post.commentCount + event.delta < 0 ? 0 : post.commentCount + event.delta),
        FeedRealtimeEventType.shareCountDelta => post.copyWith(shareCount: post.shareCount + event.delta < 0 ? 0 : post.shareCount + event.delta),
        FeedRealtimeEventType.newPost => post,
      };
      _posts = [..._posts.sublist(0, index), updated, ..._posts.sublist(index + 1)];
    });
  }

  Future<void> _refreshFromRealtimeBanner() async { setState(() => _newPostsAvailable = false); await _loadInitial(); }

  Future<void> _guardBannedUser() async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) return;
    final client = SupabaseConfig.maybeClient;
    if (client == null) return;
    try {
      final user = await client.from('users').select('status').eq('id', uid).maybeSingle();
      if (user?['status'] == 'banned' && mounted) { await client.auth.signOut(); if (mounted) context.go('/login'); }
    } catch (error, stackTrace) { BetaErrorLoggingService.instance.record(error, stackTrace, context: 'home_feed_banned_user_guard'); }
  }

  Future<List<PostModel>> _fetchInitial() async {
    final client = SupabaseConfig.maybeClient;
    if (client == null) return [];
    final uid = client.auth.currentUser?.id;
    if (uid == null) { _anonPage = 0; return repo.publicFeed(page: 0, pageSize: _pageSize); }
    return repo.homeFeedCursor(uid, pageSize: _pageSize);
  }

  Future<List<PostModel>> _fetchNext() async {
    final client = SupabaseConfig.maybeClient;
    if (client == null) return [];
    final uid = client.auth.currentUser?.id;
    if (uid == null) { _anonPage += 1; return repo.publicFeed(page: _anonPage, pageSize: _pageSize); }
    return repo.homeFeedCursor(uid, pageSize: _pageSize, cursor: _cursor);
  }

  Future<void> _loadInitial() async {
    setState(() { _loadingInitial = true; _error = null; _hasMore = true; _cursor = null; _anonPage = 0; _cachedAsOf = null; });
    try {
      final posts = await _fetchInitial();
      _posts = posts;
      if (posts.isNotEmpty) _cursor = FeedCursor.fromLastPost(posts.last);
      _hasMore = posts.length == _pageSize;
      await _refreshStates(posts.map((e) => e.id).toList());
      _scheduleNoInteractionSignal(posts.length);
      _prefetchMedia(posts);
      unawaited(FeedOfflineCache.save(posts));
      _cachedAsOf = null;
    } catch (e, stackTrace) {
      BetaErrorLoggingService.instance.record(e, stackTrace, context: 'home_feed_initial_load');
      final cached = await FeedOfflineCache.load();
      if (cached != null && cached.posts.isNotEmpty) { _posts = cached.posts; _hasMore = false; _cachedAsOf = cached.savedAt; _error = "You're offline — showing posts from your last visit."; }
      else { _error = 'Network failure. Check your connection and try again.'; }
    } finally { if (mounted) setState(() => _loadingInitial = false); }
  }

  Future<void> _loadNextPage() async {
    if (_loadingInitial || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final posts = await _fetchNext();
      final seen = _posts.map((p) => p.id).toSet();
      final newPosts = posts.where((p) => !seen.contains(p.id)).toList();
      _posts = [..._posts, ...newPosts];
      if (posts.isNotEmpty) _cursor = FeedCursor.fromLastPost(posts.last);
      _hasMore = posts.length == _pageSize;
      await _mergeStates(newPosts.map((e) => e.id).toList());
      _prefetchMedia(newPosts);
    } catch (error, stackTrace) {
      BetaErrorLoggingService.instance.record(error, stackTrace, context: 'home_feed_next_page');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Could not load more posts.'), action: SnackBarAction(label: 'Retry', onPressed: _loadNextPage)));
    } finally { if (mounted) setState(() => _loadingMore = false); }
  }

  void _prefetchMedia(List<PostModel> posts) {
    if (!mounted) return;
    final ctx = context;
    for (final post in posts.take(_pageSize)) {
      final url = post.displayImageUrl;
      if (url == null) continue;
      unawaited(precacheImage(CachedNetworkImageProvider(url), ctx).catchError((_) {}));
    }
  }

  void _maybePreloadNextPage() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter < _preloadExtent) _loadNextPage();
  }

  void _scheduleNoInteractionSignal(int visiblePostCount) {
    _noInteractionTimer?.cancel();
    _feedInteracted = false;
    AnalyticsService.instance.feedViewed(visiblePostCount: visiblePostCount);
    _noInteractionTimer = Timer(const Duration(seconds: 20), () { if (!_feedInteracted) AnalyticsService.instance.feedNoInteraction(visiblePostCount: visiblePostCount); });
  }

  void _markFeedInteracted() { _feedInteracted = true; _noInteractionTimer?.cancel(); }

  Future<void> _refreshStates(List<String> ids) async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null || ids.isEmpty) { liked = <String>{}; bookmarked = <String>{}; return; }
    liked = await repo.likedPostIds(uid, ids);
    bookmarked = await repo.bookmarkedPostIds(uid, ids);
  }

  Future<void> _mergeStates(List<String> newIds) async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null || newIds.isEmpty) return;
    final newLiked = await repo.likedPostIds(uid, newIds);
    final newBookmarked = await repo.bookmarkedPostIds(uid, newIds);
    liked = {...liked, ...newLiked};
    bookmarked = {...bookmarked, ...newBookmarked};
  }

  List<Object> _feedRows() {
    final adsSupportedPlatform = !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
    final adsOn = RemoteConfigService.instance.adsEnabled && adsSupportedPlatform;
    if (!adsOn) return _posts;
    final interval = RemoteConfigService.instance.adsFeedInterval;
    final rows = <Object>[];
    var postsSinceLastAd = 0;
    for (final post in _posts) {
      rows.add(post); postsSinceLastAd++;
      if (post.authorAdsEligible && postsSinceLastAd >= interval) { rows.add(_AdSlot(post.id)); postsSinceLastAd = 0; }
    }
    return rows;
  }

  bool _isNewAccount(WidgetRef ref) {
    final profile = ref.watch(currentUserProfileProvider).asData?.value;
    final createdAt = profile != null ? DateTime.tryParse(profile['created_at']?.toString() ?? '') : null;
    if (createdAt == null) return false;
    return DateTime.now().difference(createdAt) < const Duration(days: 3);
  }

  List<Object> _rowsWithSuggestions(List<Object> feedRows, bool isNewAccount) {
    if (SupabaseConfig.currentUserId == null) return feedRows;
    List<Object> withCommunities;
    if (isNewAccount || feedRows.length <= 3) {
      final withPymk = [const _PYMKSlot(), ...feedRows];
      withCommunities = withPymk.length <= 8 ? [...withPymk, const _SuggestedCommunitiesSlot()] : [...withPymk.sublist(0, 8), const _SuggestedCommunitiesSlot(), ...withPymk.sublist(8)];
    } else {
      final withPymk = [...feedRows.sublist(0, 3), const _PYMKSlot(), ...feedRows.sublist(3)];
      withCommunities = withPymk.length <= 10 ? [...withPymk, const _SuggestedCommunitiesSlot()] : [...withPymk.sublist(0, 10), const _SuggestedCommunitiesSlot(), ...withPymk.sublist(10)];
    }
    if (withCommunities.length <= 18) return [...withCommunities, const _SuggestedPagesSlot()];
    return [...withCommunities.sublist(0, 18), const _SuggestedPagesSlot(), ...withCommunities.sublist(18)];
  }

  @override
  Widget build(BuildContext c) {
    final uid = SupabaseConfig.currentUserId;
    final rows = _rowsWithSuggestions(_feedRows(), _isNewAccount(ref));
    return Scaffold(
      appBar: AppBar(title: Row(mainAxisSize: MainAxisSize.min, children: [Image.asset('assets/brand/gather_mark.png', width: 28, height: 28), const SizedBox(width: 8), const Text('Gather')]), actions: const [NotificationBell(), TopBarProfileLink()], bottom: appBarBottomBorder(c)),
      body: Stack(children: [
        _loadingInitial
            ? const FeedSkeletonList()
            : _error != null && _posts.isEmpty
                ? ErrorRetryState(title: 'Unable to load posts', message: _error!, onRetry: _loadInitial)
                : _posts.isEmpty
                    ? RefreshIndicator(onRefresh: _loadInitial, child: CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: const [
                        SliverToBoxAdapter(child: StoryBar()), SliverToBoxAdapter(child: ComposerPrompt()), SliverToBoxAdapter(child: PeopleYouMayKnow()), SliverToBoxAdapter(child: SuggestedCommunities()), SliverToBoxAdapter(child: SuggestedPages()),
                        SliverFillRemaining(child: EmptyState(icon: Icons.dynamic_feed_outlined, title: 'No posts yet', message: 'Pull to refresh or check back soon.')),
                      ]))
                    : RefreshIndicator(
                        onRefresh: _loadInitial,
                        child: ListView.builder(
                          controller: _scrollController,
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: 2 + rows.length + (_loadingMore ? 1 : 0),
                          itemBuilder: (context, rawIndex) {
                            if (rawIndex == 0) return const StoryBar();
                            if (rawIndex == 1) return const ComposerPrompt();
                            final index = rawIndex - 2;
                            if (index >= rows.length) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
                            final rowPost = rows[index];
                            if (rowPost is _PYMKSlot) return const PeopleYouMayKnow(key: ValueKey('pymk'));
                            if (rowPost is _SuggestedCommunitiesSlot) return const SuggestedCommunities(key: ValueKey('suggested-communities'));
                            if (rowPost is _SuggestedPagesSlot) return const SuggestedPages(key: ValueKey('suggested-pages'));
                            if (rowPost is _AdSlot) return FeedAdCard(key: ValueKey('ad-${rowPost.postId}'), postId: rowPost.postId);
                            final p = rowPost as PostModel;

                            if (p.contentType == 'page_owner') {
                              final location = p.location ?? '';
                              const prefix = 'Posted on ';
                              final pageName = location.startsWith(prefix) ? location.substring(prefix.length) : (p.authorUsername ?? 'Page');
                              return PageOwnerPostHomeCard(key: ValueKey('page-owner-${p.id}'), post: p, pageId: p.communityId, pageName: pageName);
                            }

                            if (p.contentType == 'page_visitor') {
                              final location = p.location ?? '';
                              const prefix = 'Posted on ';
                              final pageName = location.startsWith(prefix) ? location.substring(prefix.length) : 'Page';
                              return PageVisitorPostHomeCard(key: ValueKey('page-visitor-${p.id}'), post: p, pageId: p.communityId, pageName: pageName);
                            }

                            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              PostCard(
                                key: ValueKey('post-${p.id}'), post: p,
                                liked: liked.contains(p.id) || p.isLiked,
                                bookmarked: bookmarked.contains(p.id) || p.isBookmarked,
                                showBottomDivider: false,
                                onLike: () async {
                                  if (uid == null) { redirectToLogin(context, redirect: '/', message: 'Please log in or create an account to like posts.'); return; }
                                  _markFeedInteracted();
                                  AnalyticsService.instance.firstActionCompleted(action: 'post_liked');
                                  final wasLiked = liked.contains(p.id) || p.isLiked;
                                  setState(() => wasLiked ? liked.remove(p.id) : liked.add(p.id));
                                  try { if (wasLiked) await repo.unlikePost(p.id, uid); else await repo.likePost(p.id, uid); }
                                  catch (_) { if (mounted) setState(() => wasLiked ? liked.add(p.id) : liked.remove(p.id)); }
                                },
                                onComment: () {
                                  if (uid == null) { redirectToLogin(context, redirect: '/', message: 'Please log in or create an account to comment.'); return; }
                                  _markFeedInteracted();
                                  setState(() { if (_expandedComments.contains(p.id)) _expandedComments.remove(p.id); else _expandedComments.add(p.id); });
                                },
                                onBookmark: () async {
                                  if (uid == null) { redirectToLogin(context, redirect: '/', message: 'Please log in or create an account to save posts.'); return; }
                                  _markFeedInteracted();
                                  AnalyticsService.instance.firstActionCompleted(action: 'post_bookmarked');
                                  final wasBookmarked = bookmarked.contains(p.id) || p.isBookmarked;
                                  setState(() => wasBookmarked ? bookmarked.remove(p.id) : bookmarked.add(p.id));
                                  try { if (wasBookmarked) await repo.unbookmarkPost(p.id, uid); else await repo.bookmarkPost(p.id, uid); }
                                  catch (_) { if (mounted) setState(() => wasBookmarked ? bookmarked.add(p.id) : bookmarked.remove(p.id)); }
                                },
                              ),
                              InlinePostComments(key: ValueKey('comments-${p.id}'), post: p, expanded: _expandedComments.contains(p.id), onToggleExpanded: () => setState(() { if (_expandedComments.contains(p.id)) _expandedComments.remove(p.id); else _expandedComments.add(p.id); })),
                            ]);
                          },
                        ),
                      ),
        if (_newPostsAvailable) Positioned(top: 8, left: 0, right: 0, child: Center(child: Material(elevation: 3, borderRadius: BorderRadius.circular(20), color: Theme.of(c).colorScheme.primary, child: InkWell(borderRadius: BorderRadius.circular(20), onTap: _refreshFromRealtimeBanner, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.arrow_upward, size: 16, color: Theme.of(c).colorScheme.onPrimary), const SizedBox(width: 6), Text('New posts', style: TextStyle(color: Theme.of(c).colorScheme.onPrimary, fontWeight: FontWeight.w600))]))))),
        if (_cachedAsOf != null && _posts.isNotEmpty) Positioned(top: 8, left: 0, right: 0, child: Center(child: Material(elevation: 3, borderRadius: BorderRadius.circular(20), color: Theme.of(c).colorScheme.errorContainer, child: InkWell(borderRadius: BorderRadius.circular(20), onTap: _loadInitial, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.cloud_off_outlined, size: 16, color: Theme.of(c).colorScheme.onErrorContainer), const SizedBox(width: 6), Text('Offline — tap to retry', style: TextStyle(color: Theme.of(c).colorScheme.onErrorContainer, fontWeight: FontWeight.w600))]))))),
      ]),
    );
  }
}
