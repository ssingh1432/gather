import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase_client.dart';
import '../../features/data/repositories.dart';
import '../../shared/models/models.dart';
import '../../shared/services/analytics_service.dart';
import '../../shared/services/beta_error_logging_service.dart';
import '../../shared/services/feed_realtime_service.dart';
import '../../shared/widgets/auth_redirects.dart';
import '../../shared/widgets/reusables.dart';
import '../../shared/widgets/composer_prompt.dart';
import '../../shared/widgets/people_you_may_know.dart';
import '../../shared/widgets/feed_ad_card.dart';
import '../../shared/services/remote_config_service.dart';

class HomeFeedScreen extends ConsumerStatefulWidget {
  const HomeFeedScreen({super.key});
  @override
  ConsumerState<HomeFeedScreen> createState() => _S();
}

class _S extends ConsumerState<HomeFeedScreen> {
  static const int _pageSize = 20;
  static const double _preloadExtent = 640;

  final repo = FeedRepository();
  final _scrollController = ScrollController();

  Set<String> liked = <String>{};
  Set<String> bookmarked = <String>{};
  List<PostModel> _posts = const [];
  int _nextPage = 0;
  bool _loadingInitial = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  Timer? _noInteractionTimer;
  bool _feedInteracted = false;

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

  /// Live like/comment/share counts patch the matching post in place;
  /// a new post from someone else surfaces as a "New posts" pill rather
  /// than silently reordering the list under the person's thumb.
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

  Future<void> _refreshFromRealtimeBanner() async {
    setState(() => _newPostsAvailable = false);
    await _loadInitial();
  }

  Future<void> _guardBannedUser() async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) return;
    final client = SupabaseConfig.maybeClient;
    if (client == null) return;
    try {
      final user = await client.from('users').select('status').eq('id', uid).maybeSingle();
      if (user?['status'] == 'banned' && mounted) {
        await client.auth.signOut();
        if (mounted) context.go('/login');
      }
    } catch (error, stackTrace) {
      BetaErrorLoggingService.instance.record(error, stackTrace, context: 'home_feed_banned_user_guard');
      // Feed loading owns the visible offline/error state; do not crash here.
    }
  }

  Future<List<PostModel>> _fetchPage(int page) async {
    final client = SupabaseConfig.maybeClient;
    if (client == null) return [];
    final uid = client.auth.currentUser?.id;
    if (uid == null) return repo.publicFeed(page: page, pageSize: _pageSize);
    return repo.homeFeed(uid, page: page, pageSize: _pageSize);
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loadingInitial = true;
      _error = null;
      _hasMore = true;
      _nextPage = 0;
    });
    try {
      final posts = await _fetchPage(0);
      _posts = posts;
      _nextPage = 1;
      _hasMore = posts.length == _pageSize;
      await _refreshStates(posts.map((e) => e.id).toList());
      _scheduleNoInteractionSignal(posts.length);
    } catch (e, stackTrace) {
      BetaErrorLoggingService.instance.record(e, stackTrace, context: 'home_feed_initial_load');
      _error = 'Network failure. Check your connection and try again.';
    } finally {
      if (mounted) setState(() => _loadingInitial = false);
    }
  }

  Future<void> _loadNextPage() async {
    if (_loadingInitial || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = _nextPage;
      final posts = await _fetchPage(page);
      final seen = _posts.map((p) => p.id).toSet();
      _posts = [..._posts, ...posts.where((p) => !seen.contains(p.id))];
      _nextPage = page + 1;
      _hasMore = posts.length == _pageSize;
      await _refreshStates(_posts.map((e) => e.id).toList());
    } catch (error, stackTrace) {
      BetaErrorLoggingService.instance.record(error, stackTrace, context: 'home_feed_next_page', metadata: {'page': _nextPage});
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
    final position = _scrollController.position;
    // Start loading before the user hits the end so slow networks do not leave
    // a blank gap or force a full-screen spinner during ordinary scrolling.
    if (position.extentAfter < _preloadExtent) _loadNextPage();
  }

  void _scheduleNoInteractionSignal(int visiblePostCount) {
    _noInteractionTimer?.cancel();
    _feedInteracted = false;
    AnalyticsService.instance.feedViewed(visiblePostCount: visiblePostCount);
    _noInteractionTimer = Timer(const Duration(seconds: 20), () {
      if (!_feedInteracted) {
        AnalyticsService.instance.feedNoInteraction(visiblePostCount: visiblePostCount);
      }
    });
  }

  void _markFeedInteracted() {
    _feedInteracted = true;
    _noInteractionTimer?.cancel();
  }

  Future<void> _refreshStates(List<String> ids) async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null || ids.isEmpty) {
      liked = <String>{};
      bookmarked = <String>{};
      return;
    }
    liked = await repo.likedPostIds(uid, ids);
    bookmarked = await repo.bookmarkedPostIds(uid, ids);
  }

  /// Posts with ad slots interleaved every `adsFeedInterval` posts. An ad
  /// slot is represented as `null`. Returns just the posts (no ads mixed
  /// in) whenever ads are disabled/unsupported — which is the default, so
  /// this is a no-op today.
  List<PostModel?> _feedRows() {
    final adsSupportedPlatform =
        !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
    final adsOn = RemoteConfigService.instance.adsEnabled && adsSupportedPlatform;
    if (!adsOn) return _posts;
    final interval = RemoteConfigService.instance.adsFeedInterval;
    final rows = <PostModel?>[];
    for (var i = 0; i < _posts.length; i++) {
      rows.add(_posts[i]);
      if ((i + 1) % interval == 0) rows.add(null);
    }
    return rows;
  }

  @override
  Widget build(BuildContext c) {
    final uid = SupabaseConfig.currentUserId;
    final feedRows = _feedRows();
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/brand/gather_mark.png', width: 28, height: 28),
            const SizedBox(width: 8),
            const Text('Gather'),
          ],
        ),
      ),
      body: Stack(
        children: [
          _loadingInitial
              ? const FeedSkeletonList()
          : _error != null
              ? ErrorRetryState(title: 'Unable to load posts', message: _error!, onRetry: _loadInitial)
              : _posts.isEmpty
                  ? RefreshIndicator(
                      onRefresh: _loadInitial,
                      child: CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: const [
                          SliverToBoxAdapter(child: ComposerPrompt()),
                          SliverToBoxAdapter(child: PeopleYouMayKnow()),
                          SliverFillRemaining(
                            child: EmptyState(icon: Icons.dynamic_feed_outlined, title: 'No posts yet', message: 'Pull to refresh or check back soon.'),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadInitial,
                      child: ListView.builder(
                        controller: _scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: 2 + feedRows.length + (_loadingMore ? 1 : 0),
                        itemBuilder: (context, rawIndex) {
                          if (rawIndex == 0) return const ComposerPrompt();
                          if (rawIndex == 1) return const PeopleYouMayKnow();
                          final index = rawIndex - 2;
                          if (index >= feedRows.length) {
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          final rowPost = feedRows[index];
                          if (rowPost == null) return const FeedAdCard();
                          final p = rowPost;
                          return PostCard(
                            post: p,
                            liked: liked.contains(p.id) || p.isLiked,
                            bookmarked: bookmarked.contains(p.id) || p.isBookmarked,
                            onLike: () async {
                              if (uid == null) {
                                redirectToLogin(context, redirect: '/', message: 'Please log in or create an account to like posts.');
                                return;
                              }
                              _markFeedInteracted();
                              AnalyticsService.instance.firstActionCompleted(action: 'post_liked');
                              if (liked.contains(p.id) || p.isLiked) {
                                await repo.unlikePost(p.id, uid);
                              } else {
                                await repo.likePost(p.id, uid);
                              }
                              await _refreshStates(_posts.map((e) => e.id).toList());
                              if (mounted) setState(() {});
                            },
                            onComment: () {
                              if (uid == null) {
                                redirectToLogin(context, redirect: '/post?id=${p.id}', message: 'Please log in or create an account to comment.');
                                return;
                              }
                              _markFeedInteracted();
                              context.push('/post?id=${p.id}');
                            },
                            onBookmark: () async {
                              if (uid == null) {
                                redirectToLogin(context, redirect: '/', message: 'Please log in or create an account to save posts.');
                                return;
                              }
                              _markFeedInteracted();
                              AnalyticsService.instance.firstActionCompleted(action: 'post_bookmarked');
                              if (bookmarked.contains(p.id) || p.isBookmarked) {
                                await repo.unbookmarkPost(p.id, uid);
                              } else {
                                await repo.bookmarkPost(p.id, uid);
                              }
                              await _refreshStates(_posts.map((e) => e.id).toList());
                              if (mounted) setState(() {});
                            },
                          );
                        },
                      ),
                    ),
          if (_newPostsAvailable)
            Positioned(
              top: 8,
              left: 0,
              right: 0,
              child: Center(
                child: Material(
                  elevation: 3,
                  borderRadius: BorderRadius.circular(20),
                  color: Theme.of(c).colorScheme.primary,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: _refreshFromRealtimeBanner,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.arrow_upward, size: 16, color: Theme.of(c).colorScheme.onPrimary),
                          const SizedBox(width: 6),
                          Text('New posts', style: TextStyle(color: Theme.of(c).colorScheme.onPrimary, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
