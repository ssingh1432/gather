import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase_client.dart';
import '../../features/data/repositories.dart';
import '../models/models.dart';
import '../providers/app_providers.dart';
import '../utils/time_ago.dart';
import 'auth_redirects.dart';
import 'reusables.dart';

/// Shown under every post card in the feed, in place of navigating to
/// PostDetailScreen when the comment icon is tapped. PostDetailScreen
/// itself is untouched and still used everywhere else a post is opened
/// full-screen (notifications, quoted-post taps, community detail, the
/// reply-to-post screen) — this widget only changes what happens from the
/// feed's own comment icon.
///
/// Two things are always visible regardless of [expanded]: the single
/// latest top-level comment (if any), and a comment input with a
/// "Comment as `username`" placeholder. Tapping the comment icon (which
/// toggles [expanded] from the parent, the same way liked/bookmarked are
/// lifted into HomeFeedScreen's own state) reveals the rest of the thread
/// in an AnimatedSize "opens downward" reveal instead of navigating away.
class InlinePostComments extends ConsumerStatefulWidget {
  const InlinePostComments({super.key, required this.post, required this.expanded, required this.onToggleExpanded});
  final PostModel post;
  final bool expanded;
  final VoidCallback onToggleExpanded;

  @override
  ConsumerState<InlinePostComments> createState() => _InlinePostCommentsState();
}

class _InlinePostCommentsState extends ConsumerState<InlinePostComments> {
  final _repo = FeedRepository();
  final _commentCtrl = TextEditingController();
  final _focusNode = FocusNode();

  List<CommentModel>? _comments;
  bool _sending = false;
  CommentModel? _replyingTo;

  @override
  void initState() {
    super.initState();
    // Loaded unconditionally (not gated on widget.expanded) so the latest
    // comment preview appears automatically, per the request — the
    // full-thread reveal is the only thing gated on expand state.
    _load();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final comments = await _repo.comments(widget.post.id);
      if (mounted) setState(() => _comments = comments);
    } catch (_) {
      // Silent — a feed row failing to preview comments shouldn't show an
      // error banner under every post; the input below still lets the
      // person try posting, and pull-to-refresh will retry the load.
    }
  }

  List<CommentModel> get _topLevel => (_comments ?? const []).where((c) => c.parentCommentId == null).toList();
  List<CommentModel> _repliesTo(String id) => (_comments ?? const []).where((c) => c.parentCommentId == id).toList();

  void _startReply(CommentModel comment) {
    setState(() => _replyingTo = comment);
    if (!widget.expanded) widget.onToggleExpanded();
    _focusNode.requestFocus();
  }

  Future<void> _submit() async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) {
      redirectToLogin(context, redirect: '/', message: 'Please log in or create an account to comment.');
      return;
    }
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;

    setState(() => _sending = true);
    try {
      final parentId = _replyingTo == null ? null : (_replyingTo!.parentCommentId ?? _replyingTo!.id);
      await _repo.addComment(widget.post.id, uid, text, parentCommentId: parentId);
      _commentCtrl.clear();
      _replyingTo = null;
      await _load();
      if (!widget.expanded) widget.onToggleExpanded();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not post comment. Please retry.')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topLevel = _topLevel;
    final latest = topLevel.isEmpty ? null : topLevel.reduce((a, b) => a.createdAt.isAfter(b.createdAt) ? a : b);
    final remainingCount = widget.post.commentCount - (latest == null ? 0 : 1);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(bottom: BorderSide(color: theme.dividerColor, width: 8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(height: 1, thickness: 1, color: theme.dividerColor.withValues(alpha: 0.5)),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!widget.expanded && latest != null)
            // The whole preview area is tappable to expand — not just the
            // small "N comments" hint — so a light touch anywhere near the
            // latest comment reveals the full thread, rather than
            // requiring a precise tap on a small link. The Reply link and
            // avatar inside _CommentRow still resolve to their own taps
            // first (innermost hit-test wins), so they aren't swallowed.
            InkWell(
              onTap: widget.onToggleExpanded,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _CommentRow(comment: latest, onReply: () => _startReply(latest)),
                    if (remainingCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(left: 40, top: 1),
                        child: Text(
                          '${widget.post.commentCount} comments',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline.withValues(alpha: 0.7)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !widget.expanded
                ? const SizedBox(width: double.infinity)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_comments == null)
                        const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: SkeletonBox(height: 40))
                      else if (topLevel.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text('No comments yet. Be the first to reply.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                        )
                      else
                        for (final comment in topLevel) _InlineCommentThread(comment: comment, replies: _repliesTo(comment.id), onReply: _startReply),
                    ],
                  ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_replyingTo != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 40, bottom: 4),
                    child: Row(children: [
                      Expanded(child: Text('Replying to @${_replyingTo!.username ?? 'user'}', style: theme.textTheme.bodySmall)),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(() => _replyingTo = null),
                      ),
                    ]),
                  ),
                Row(children: [
                  Consumer(builder: (context, ref, _) {
                    final profileAsync = ref.watch(currentUserProfileProvider);
                    final avatarUrl = profileAsync.asData?.value?['profile_photo_url'] as String?;
                    return ProfileAvatar(url: avatarUrl, radius: 15);
                  }),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Consumer(builder: (context, ref, _) {
                      final profileAsync = ref.watch(currentUserProfileProvider);
                      final username = profileAsync.asData?.value?['username'] as String?;
                      return TextField(
                        controller: _commentCtrl,
                        focusNode: _focusNode,
                        minLines: 1,
                        maxLines: 4,
                        onTap: () {
                          if (!widget.expanded) widget.onToggleExpanded();
                        },
                        decoration: InputDecoration(
                          hintText: 'Comment as ${username ?? 'you'}',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          filled: true,
                          fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                        ),
                        onSubmitted: (_) => _submit(),
                      );
                    }),
                  ),
                  IconButton(
                    onPressed: _sending ? null : _submit,
                    icon: _sending
                        ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(Icons.send, color: theme.colorScheme.primary),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
          ),
        ],
      ),
    );
  }
}

class _InlineCommentThread extends StatefulWidget {
  const _InlineCommentThread({required this.comment, required this.replies, required this.onReply});
  final CommentModel comment;
  final List<CommentModel> replies;
  final void Function(CommentModel comment) onReply;

  @override
  State<_InlineCommentThread> createState() => _InlineCommentThreadState();
}

class _InlineCommentThreadState extends State<_InlineCommentThread> {
  bool _repliesShown = false;

  @override
  Widget build(BuildContext context) {
    final replyCount = widget.replies.length;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CommentRow(comment: widget.comment, onReply: () => widget.onReply(widget.comment)),
          if (replyCount > 0)
            Padding(
              padding: const EdgeInsets.only(left: 40),
              child: TextButton(
                onPressed: () => setState(() => _repliesShown = !_repliesShown),
                style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                child: Text(_repliesShown ? 'Hide replies' : 'View $replyCount ${replyCount == 1 ? 'reply' : 'replies'}'),
              ),
            ),
          if (_repliesShown)
            Padding(
              padding: const EdgeInsets.only(left: 32),
              child: Column(children: [for (final reply in widget.replies) _CommentRow(comment: reply, onReply: () => widget.onReply(reply))]),
            ),
        ],
      ),
    );
  }
}

/// A single comment line — avatar, bubble, timestamp + Reply. Deliberately
/// separate from PostDetailScreen's own `_CommentTile` (same visual shape,
/// but that one is private to that file and also renders the
/// hide/unhide-comment control for post owners, which this compact feed
/// preview intentionally leaves out to stay lightweight).
class _CommentRow extends StatelessWidget {
  const _CommentRow({required this.comment, required this.onReply});
  final CommentModel comment;
  final VoidCallback onReply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => context.push('/user?id=${comment.userId}'),
            child: ProfileAvatar(url: comment.avatarUrl, radius: 14),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(comment.username ?? 'User', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 1),
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
                  ]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
