import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase_client.dart';
import '../../features/data/repositories.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/auth_redirects.dart';
import '../../shared/widgets/reusables.dart';

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
  final postCtrl = TextEditingController();
  final _scrollController = ScrollController();

  Set<String> liked = <String>{};
  Set<String> bookmarked = <String>{};
  List<PostModel> _posts = const [];
  int _nextPage = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _posting = false;
  String? _error;

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
      final posts = await _fetchPage(0);
      _posts = posts;
      _nextPage = 1;
      _hasMore = posts.length == _pageSize;
      await _refreshStates(_posts.map((e) => e.id).toList());
    } catch (e) {
      _error = 'Network failure. Check your connection and try again.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<PostModel>> _fetchPage(int page) async {
    final uid = SupabaseConfig.maybeClient?.auth.currentUser?.id;
    return repo.communityFeed(widget.communityId, userId: uid, page: page, pageSize: _pageSize);
  }

  Future<void> _refreshStates(List<String> ids) async {
    final uid = SupabaseConfig.maybeClient?.auth.currentUser?.id;
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
    // Preloading while there is still content below avoids layout jumps at the
    // end of the list and makes pagination observable under slow networks.
    if (_scrollController.position.extentAfter < _preloadExtent) _loadNextPage();
  }

  Future<void> _publishCommunityPost() async {
    final uid = SupabaseConfig.maybeClient?.auth.currentUser?.id;
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

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Community')),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(controller: postCtrl, decoration: const InputDecoration(labelText: 'Create post text')),
          ),
          ElevatedButton(
            onPressed: _posting ? null : _publishCommunityPost,
            child: _posting ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Post'),
          ),
          Expanded(
            child: _loading
                ? const FeedSkeletonList()
                : _error != null
                    ? ErrorRetryState(title: 'Unable to load community posts', message: _error!, onRetry: _load)
                    : _posts.isEmpty
                        ? RefreshIndicator(
                            onRefresh: _load,
                            child: const CustomScrollView(
                              physics: AlwaysScrollableScrollPhysics(),
                              slivers: [
                                SliverFillRemaining(
                                  child: EmptyState(icon: Icons.forum_outlined, title: 'No posts', message: 'Be the first to start this community conversation.'),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              controller: _scrollController,
                              physics: const AlwaysScrollableScrollPhysics(),
                              itemCount: _posts.length + (_loadingMore ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index >= _posts.length) {
                                  return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
                                }
                                final p = _posts[index];
                                return PostCard(
                                  post: p,
                                  liked: liked.contains(p.id) || p.isLiked,
                                  bookmarked: bookmarked.contains(p.id) || p.isBookmarked,
                                  onLike: () async {
                                    final uid = SupabaseConfig.maybeClient?.auth.currentUser?.id;
                                    if (uid == null) {
                                      redirectToLogin(context, redirect: '/community?id=${widget.communityId}', message: 'Please log in or create an account to like posts.');
                                      return;
                                    }
                                    if (liked.contains(p.id) || p.isLiked) {
                                      await repo.unlikePost(p.id, uid);
                                    } else {
                                      await repo.likePost(p.id, uid);
                                    }
                                    await _refreshStates(_posts.map((e) => e.id).toList());
                                    if (mounted) setState(() {});
                                  },
                                  onComment: () {
                                    final uid = SupabaseConfig.maybeClient?.auth.currentUser?.id;
                                    if (uid == null) {
                                      redirectToLogin(context, redirect: '/post?id=${p.id}', message: 'Please log in or create an account to comment.');
                                      return;
                                    }
                                    context.push('/post?id=${p.id}');
                                  },
                                  onBookmark: () async {
                                    final uid = SupabaseConfig.maybeClient?.auth.currentUser?.id;
                                    if (uid == null) {
                                      redirectToLogin(context, redirect: '/community?id=${widget.communityId}', message: 'Please log in or create an account to save posts.');
                                      return;
                                    }
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
          )
        ]),
      );
}
