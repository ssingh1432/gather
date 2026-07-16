import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase_client.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/reusables.dart';
import '../data/repositories.dart';

/// The reverse of a quote-post's embedded original: shown from a post's
/// "N replies" action, this lists every post that quoted/replied to it —
/// Facebook-style, so the reply and the post it targets are visible
/// together in both directions.
class PostRepliesScreen extends StatefulWidget {
  const PostRepliesScreen({super.key, required this.postId});
  final String postId;

  @override
  State<PostRepliesScreen> createState() => _PostRepliesScreenState();
}

class _PostRepliesScreenState extends State<PostRepliesScreen> {
  late Future<List<PostModel>> _future = FeedRepository().repliesTo(widget.postId);

  void _retry() => setState(() => _future = FeedRepository().repliesTo(widget.postId));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Replies')),
      body: FutureBuilder<List<PostModel>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const FeedSkeletonList(itemCount: 3);
          if (snapshot.hasError) {
            return ErrorRetryState(title: 'Unable to load replies', message: 'Network failure. Check your connection and try again.', onRetry: _retry);
          }
          final replies = snapshot.data ?? const [];
          if (replies.isEmpty) {
            return const EmptyState(icon: Icons.forum_outlined, title: 'No replies yet', message: 'Replies and quotes of this post will show up here.');
          }
          final uid = SupabaseConfig.maybeClient?.auth.currentUser?.id;
          return RefreshIndicator(
            onRefresh: () async => _retry(),
            child: ListView.builder(
              itemCount: replies.length,
              itemBuilder: (context, i) {
                final post = replies[i];
                return PostCard(
                  post: post,
                  liked: uid != null && post.isLiked,
                  bookmarked: uid != null && post.isBookmarked,
                  onLike: () async {
                    if (uid == null) return;
                    if (post.isLiked) {
                      await FeedRepository().unlikePost(post.id, uid);
                    } else {
                      await FeedRepository().likePost(post.id, uid);
                    }
                    _retry();
                  },
                  onBookmark: () async {
                    if (uid == null) return;
                    if (post.isBookmarked) {
                      await FeedRepository().unbookmarkPost(post.id, uid);
                    } else {
                      await FeedRepository().bookmarkPost(post.id, uid);
                    }
                    _retry();
                  },
                  onComment: () => context.push('/post?id=${post.id}'),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
