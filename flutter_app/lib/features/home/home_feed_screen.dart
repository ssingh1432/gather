import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase_client.dart';
import '../../features/data/repositories.dart';
import '../../shared/models/models.dart';
import '../../shared/services/analytics_service.dart';
import '../../shared/services/beta_error_logging_service.dart';
import '../../shared/widgets/auth_redirects.dart';
import '../../shared/widgets/reusables.dart';
import '../../shared/widgets/composer_prompt.dart';

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

  @override
  void initState() {
    super.initState();
    _guardBannedUser();
    _scrollController.addListener(_maybePreloadNextPage);
    _loadInitial();
  }

  @override
  void dispose() {
    _noInteractionTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext c) {
    final uid = SupabaseConfig.currentUserId;
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: _loadingInitial
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
                        itemCount: 1 + _posts.length + (_loadingMore ? 1 : 0),
                        itemBuilder: (context, rawIndex) {
                          if (rawIndex == 0) return const ComposerPrompt();
                          final index = rawIndex - 1;
                          if (index >= _posts.length) {
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          final p = _posts[index];
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
    );
  }
}
