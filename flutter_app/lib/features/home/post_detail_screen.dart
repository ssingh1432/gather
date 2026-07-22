import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase_client.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/auth_redirects.dart';
import '../../shared/widgets/reusables.dart';
import '../../shared/utils/time_ago.dart';
import '../data/repositories.dart';

/// Full post view with a threaded "comment loop": top-level comments each
/// support one level of replies, mirroring the reply-to-post pattern used
/// on the home feed.
class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({super.key, required this.postId});
  final String postId;

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final repo = FeedRepository();
  final _commentCtrl = TextEditingController();
  final _focusNode = FocusNode();

  PostModel? _post;
  List<CommentModel> _comments = const [];
  bool _liked = false;
  bool _bookmarked = false;
  bool _loading = true;
  bool _sending = false;
  String? _error;

  /// When set, the composer submits a reply nested under this comment
  /// instead of a new top-level comment.
  CommentModel? _replyingTo;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([repo.getPost(widget.postId), repo.comments(widget.postId)]);
      final post = results[0] as PostModel;
      final comments = results[1] as List<CommentModel>;
      final uid = SupabaseConfig.currentUserId;
      bool liked = post.isLiked;
      bool bookmarked = post.isBookmarked;
      if (uid != null) {
        final likedIds = await repo.likedPostIds(uid, [post.id]);
        final bookmarkedIds = await repo.bookmarkedPostIds(uid, [post.id]);
        liked = likedIds.contains(post.id);
        bookmarked = bookmarkedIds.contains(post.id);
      }
      if (!mounted) return;
      setState(() {
        _post = post;
        _comments = comments;
        _liked = liked;
        _bookmarked = bookmarked;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Network failure. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<CommentModel> get _topLevel => _comments.where((c) => c.parentCommentId == null).toList();

  List<CommentModel> _repliesTo(String commentId) => _comments.where((c) => c.parentCommentId == commentId).toList();

  /// Only the post owner sees the control that calls this — enforced again
  /// server-side by set_comment_hidden regardless.
  Future<void> _toggleCommentHidden(CommentModel comment) async {
    try {
      await repo.setCommentHidden(comment.id, !comment.isHidden);
      final comments = await repo.comments(widget.postId);
      if (mounted) setState(() => _comments = comments);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not update this comment. Please try again.')));
      }
    }
  }

  void _startReply(CommentModel comment) {
    setState(() => _replyingTo = comment);
    _focusNode.requestFocus();
  }

  void _cancelReply() => setState(() => _replyingTo = null);

  Future<void> _submitComment() async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) {
      redirectToLogin(context, redirect: '/post?id=${widget.postId}', message: 'Please log in or create an account to comment.');
      return;
    }
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;

    setState(() => _sending = true);
    try {
      // Replying to a reply still nests one level deep, under that reply's
      // own parent — keeps the thread flat and easy to scan.
      final parentId = _replyingTo == null ? null : (_replyingTo!.parentCommentId ?? _replyingTo!.id);
      await repo.addComment(widget.postId, uid, text, parentCommentId: parentId);
      _commentCtrl.clear();
      setState(() => _replyingTo = null);
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not post comment. Please retry.')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _toggleLike() async {
    final uid = SupabaseConfig.currentUserId;
    final post = _post;
    if (uid == null || post == null) {
      redirectToLogin(context, redirect: '/post?id=${widget.postId}', message: 'Please log in or create an account to like posts.');
      return;
    }
    setState(() => _liked = !_liked);
    if (_liked) {
      await repo.likePost(post.id, uid);
    } else {
      await repo.unlikePost(post.id, uid);
    }
    await _load();
  }

  Future<void> _toggleBookmark() async {
    final uid = SupabaseConfig.currentUserId;
    final post = _post;
    if (uid == null || post == null) {
      redirectToLogin(context, redirect: '/post?id=${widget.postId}', message: 'Please log in or create an account to save posts.');
      return;
    }
    setState(() => _bookmarked = !_bookmarked);
    if (_bookmarked) {
      await repo.bookmarkPost(post.id, uid);
    } else {
      await repo.unbookmarkPost(post.id, uid);
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Post')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ErrorRetryState(title: 'Unable to load post', message: _error!, onRetry: _load)
              : _post == null
                  ? const EmptyState(icon: Icons.error_outline, title: 'Post not found')
                  : Column(
                      children: [
                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: _load,
                            child: ListView(
                              padding: const EdgeInsets.only(bottom: 12),
                              children: [
                                PostCard(
                                  post: _post!,
                                  liked: _liked,
                                  bookmarked: _bookmarked,
                                  onLike: _toggleLike,
                                  onBookmark: _toggleBookmark,
                                  onComment: () => _focusNode.requestFocus(),
                                ),
                                const Padding(
                                  padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
                                  child: Divider(),
                                ),
                                if (_topLevel.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Text('No comments yet. Be the first to reply.'),
                                  )
                                else
                                  for (final comment in _topLevel)
                                    _CommentThread(
                                      comment: comment,
                                      replies: _repliesTo(comment.id),
                                      onReply: _startReply,
                                      isPostOwner: _post?.authorId == SupabaseConfig.currentUserId,
                                      onToggleHidden: _toggleCommentHidden,
                                    ),
                              ],
                            ),
                          ),
                        ),
                        SafeArea(
                          top: false,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_replyingTo != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Row(children: [
                                      Expanded(child: Text('Replying to @${_replyingTo!.username ?? 'user'}', style: Theme.of(context).textTheme.bodySmall)),
                                      IconButton(icon: const Icon(Icons.close, size: 18), onPressed: _cancelReply, visualDensity: VisualDensity.compact),
                                    ]),
                                  ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _commentCtrl,
                                        focusNode: _focusNode,
                                        minLines: 1,
                                        maxLines: 4,
                                        decoration: InputDecoration(
                                          hintText: _replyingTo == null ? 'Add a comment...' : 'Write a reply...',
                                          isDense: true,
                                        ),
                                        onSubmitted: (_) => _submitComment(),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton.filled(
                                      onPressed: _sending ? null : _submitComment,
                                      icon: _sending
                                          ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                          : const Icon(Icons.send),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
    );
  }
}

class _CommentThread extends StatefulWidget {
  const _CommentThread({
    required this.comment,
    required this.replies,
    required this.onReply,
    required this.isPostOwner,
    required this.onToggleHidden,
  });
  final CommentModel comment;
  final List<CommentModel> replies;
  final void Function(CommentModel comment) onReply;
  final bool isPostOwner;
  final void Function(CommentModel comment) onToggleHidden;

  @override
  State<_CommentThread> createState() => _CommentThreadState();
}

class _CommentThreadState extends State<_CommentThread> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final replyCount = widget.replies.length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CommentTile(
            comment: widget.comment,
            onReply: () => widget.onReply(widget.comment),
            isPostOwner: widget.isPostOwner,
            onToggleHidden: widget.onToggleHidden,
          ),
          if (replyCount > 0)
            Padding(
              padding: const EdgeInsets.only(left: 40),
              child: TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                child: Text(_expanded ? 'Hide replies' : 'View $replyCount ${replyCount == 1 ? 'reply' : 'replies'}'),
              ),
            ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(left: 32),
              child: Column(
                children: [
                  for (final reply in widget.replies)
                    _CommentTile(
                      comment: reply,
                      onReply: () => widget.onReply(reply),
                      isPostOwner: widget.isPostOwner,
                      onToggleHidden: widget.onToggleHidden,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.onReply,
    this.isPostOwner = false,
    this.onToggleHidden,
  });
  final CommentModel comment;
  final VoidCallback onReply;
  final bool isPostOwner;
  final void Function(CommentModel comment)? onToggleHidden;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => context.push('/user?id=${comment.userId}'),
            child: ProfileAvatar(url: comment.avatarUrl, radius: 15),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(comment.username ?? 'User', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(comment.content, style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 10, top: 2),
                  child: Row(children: [
                    Text(timeAgo(comment.createdAt), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                    const SizedBox(width: 12),
                    InkWell(
                      onTap: onReply,
                      child: Text('Reply', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: theme.colorScheme.primary)),
                    ),
                    if (comment.isHidden) ...[
                      const SizedBox(width: 12),
                      Icon(Icons.visibility_off_outlined, size: 13, color: theme.colorScheme.error),
                      const SizedBox(width: 3),
                      Text(
                        'Hidden — only you and they can see this',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                      ),
                    ],
                  ]),
                ),
              ],
            ),
          ),
          if (isPostOwner)
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(comment.isHidden ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
              tooltip: comment.isHidden ? 'Unhide comment' : 'Hide comment',
              onPressed: onToggleHidden == null ? null : () => onToggleHidden!(comment),
            ),
        ],
      ),
    );
  }
}
