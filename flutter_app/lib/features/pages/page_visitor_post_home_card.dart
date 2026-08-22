import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/supabase_client.dart';
import '../../shared/models/models.dart';
import '../../shared/utils/time_ago.dart';
import '../../shared/widgets/reusables.dart';
import 'page_media_gallery.dart';
import 'page_visitor_post_repository.dart';

class PageVisitorPostHomeCard extends StatefulWidget {
  const PageVisitorPostHomeCard({super.key, required this.post, required this.pageId, required this.pageName});
  final PostModel post;
  final String? pageId;
  final String pageName;

  @override
  State<PageVisitorPostHomeCard> createState() => _PageVisitorPostHomeCardState();
}

enum _PagePostMenuAction { report, copyLink }

class _PageVisitorPostHomeCardState extends State<PageVisitorPostHomeCard> {
  final _repo = PageVisitorPostRepository();
  final _commentCtrl = TextEditingController();
  final _commentFocus = FocusNode();
  late bool _liked;
  int _likeCount = 0;
  int _commentCount = 0;
  bool _busy = false;
  bool _commentsExpanded = false;
  bool _commentsLoading = false;
  bool _sendingComment = false;
  String? _replyingToId;
  String? _replyingToUsername;
  List<Map<String, dynamic>> _comments = const [];

  @override
  void initState() {
    super.initState();
    // get_home_feed_cursor() already returns each row's like state and
    // count, so there is no need for a per-card follow-up request here.
    // Previously every visitor-post card fired its own like-state query the
    // moment it mounted, so scrolling past a screenful of Page posts meant
    // a burst of individual network calls competing with image loads —
    // a direct contributor to stutter/jank while scrolling Home.
    _liked = widget.post.isLiked;
    _likeCount = widget.post.likeCount;
    _commentCount = widget.post.commentCount;
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    _commentFocus.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    if (_commentsLoading) return;
    setState(() => _commentsLoading = true);
    try {
      final comments = await _repo.listComments(widget.post.id);
      final count = await _repo.commentCount(widget.post.id);
      if (mounted) setState(() {
        _comments = comments;
        _commentCount = count;
      });
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not load comments. Please try again.')));
    } finally {
      if (mounted) setState(() => _commentsLoading = false);
    }
  }

  Future<void> _toggleComments() async {
    setState(() => _commentsExpanded = !_commentsExpanded);
    if (_commentsExpanded) await _loadComments();
  }

  void _startReply(Map<String, dynamic> comment) {
    setState(() {
      _replyingToId = comment['id']?.toString();
      final user = comment['users'] as Map<String, dynamic>?;
      _replyingToUsername = user?['username'] as String?;
      _commentsExpanded = true;
    });
    _loadComments();
    _commentFocus.requestFocus();
  }

  void _cancelReply() {
    setState(() {
      _replyingToId = null;
      _replyingToUsername = null;
    });
  }

  Future<void> _submitComment() async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) {
      if (mounted) context.push('/login');
      return;
    }
    final text = _commentCtrl.text.trim();
    if (text.isEmpty || _sendingComment) return;
    final pageId = widget.pageId;
    if (pageId == null || pageId.isEmpty) return;
    setState(() => _sendingComment = true);
    try {
      await _repo.addComment(widget.post.id, pageId, text, parentCommentId: _replyingToId);
      _commentCtrl.clear();
      _cancelReply();
      await _loadComments();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not post comment. Please try again.')));
    } finally {
      if (mounted) setState(() => _sendingComment = false);
    }
  }

  Future<void> _toggleLike() async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) {
      if (mounted) context.push('/login');
      return;
    }
    if (_busy) return;
    final previous = _liked;
    setState(() {
      _busy = true;
      _liked = !previous;
      _likeCount += previous ? -1 : 1;
    });
    try {
      await _repo.setLike(widget.post.id, !previous);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _liked = previous;
        _likeCount += previous ? 1 : -1;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not update like. Please try again.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _postLink() {
    final pageId = widget.pageId;
    if (pageId == null || pageId.isEmpty) return null;
    return 'https://eiquoab.xyz/page?id=$pageId&visitorPostId=${widget.post.id}';
  }

  Future<void> _copyLink() async {
    final link = _postLink();
    if (link == null) return;
    try {
      await Clipboard.setData(ClipboardData(text: link));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Post link copied.')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not copy the post link.')));
    }
  }

  void _reportPost() {
    context.push(Uri(path: '/report', queryParameters: {'postId': widget.post.id}).toString());
  }

  Future<void> _share() async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) {
      if (mounted) context.push('/login');
      return;
    }
    final pageId = widget.pageId;
    if (pageId == null || pageId.isEmpty) return;
    final poster = widget.post.authorUsername?.isNotEmpty == true ? '@${widget.post.authorUsername}' : 'Gather user';
    final text = widget.post.textContent.trim();
    final url = _postLink()!;
    final body = ['Posted by $poster on ${widget.pageName.isEmpty ? 'Page' : widget.pageName}', if (text.isNotEmpty) text, url].join('\n\n');
    try {
      await Share.share(body);
      await _repo.recordShare(widget.post.id, uid);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not share this post.')));
    }
  }

  void _handlePostMenuAction(_PagePostMenuAction action) {
    switch (action) {
      case _PagePostMenuAction.report:
        _reportPost();
      case _PagePostMenuAction.copyLink:
        _copyLink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authorName = widget.post.authorUsername?.isNotEmpty == true ? '@${widget.post.authorUsername}' : 'Gather user';
    final canCopyLink = _postLink() != null;
    final canViewPage = widget.pageId?.isNotEmpty == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: Theme.of(context).cardColor, border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor, width: 8))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ProfileAvatar(url: widget.post.authorAvatarUrl, radius: 20),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(authorName, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, children: [
                const Icon(Icons.arrow_forward, size: 13),
                Text(widget.pageName.isEmpty ? 'a Page' : widget.pageName, style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
                Text('• ${timeAgo(widget.post.createdAt)}'),
              ]),
            ])),
            PopupMenuButton<_PagePostMenuAction>(
              tooltip: 'Post options',
              onSelected: _handlePostMenuAction,
              itemBuilder: (_) => [
                const PopupMenuItem(value: _PagePostMenuAction.report, child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.flag_outlined), title: Text('Report post'))),
                PopupMenuItem(value: _PagePostMenuAction.copyLink, enabled: canCopyLink, child: const ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.link), title: Text('Copy link'))),
              ],
            ),
          ]),
          if (widget.post.textContent.trim().isNotEmpty) ...[const SizedBox(height: 12), Text(widget.post.textContent, style: Theme.of(context).textTheme.bodyLarge)],
          if (widget.post.mediaItems.isNotEmpty) ...[const SizedBox(height: 12), _PageVisitorMedia(items: widget.post.mediaItems)],
          const SizedBox(height: 6),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 2,
            runSpacing: 2,
            children: [
              _PageAction(icon: _liked ? Icons.favorite : Icons.favorite_border, label: _likeCount == 0 ? 'Like' : '$_likeCount', active: _liked, onTap: _busy ? null : _toggleLike),
              _PageAction(icon: _commentsExpanded ? Icons.mode_comment : Icons.mode_comment_outlined, label: _commentCount == 0 ? 'Comment' : '$_commentCount', active: _commentsExpanded, onTap: _toggleComments),
              _PageAction(icon: Icons.share_outlined, label: 'Share', onTap: _share),
              _PageAction(icon: Icons.open_in_new, label: 'View Page & post', onTap: canViewPage ? () => context.push('/page-profile?id=${widget.pageId}') : null),
            ],
          ),
          if (_commentsExpanded) ...[
            const SizedBox(height: 4),
            _PageComments(comments: _comments, loading: _commentsLoading, replyingToUsername: _replyingToUsername, commentController: _commentCtrl, commentFocus: _commentFocus, sending: _sendingComment, onReply: _startReply, onCancelReply: _cancelReply, onSubmit: _submitComment),
          ],
        ]),
      ),
    );
  }
}

class _PageAction extends StatelessWidget {
  const _PageAction({required this.icon, required this.label, required this.onTap, this.active = false});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: onTap,
    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7), minimumSize: const Size(0, 36), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
    icon: Icon(icon, size: 19, color: active ? Theme.of(context).colorScheme.primary : null),
    label: Text(label, style: TextStyle(color: active ? Theme.of(context).colorScheme.primary : null)),
  );
}

class _PageComments extends StatelessWidget {
  const _PageComments({required this.comments, required this.loading, required this.replyingToUsername, required this.commentController, required this.commentFocus, required this.sending, required this.onReply, required this.onCancelReply, required this.onSubmit});
  final List<Map<String, dynamic>> comments;
  final bool loading;
  final String? replyingToUsername;
  final TextEditingController commentController;
  final FocusNode commentFocus;
  final bool sending;
  final void Function(Map<String, dynamic>) onReply;
  final VoidCallback onCancelReply;
  final VoidCallback onSubmit;

  List<Map<String, dynamic>> _children(String? parentId) => comments.where((c) => c['parent_comment_id']?.toString() == parentId).toList();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (loading) const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
        if (!loading && comments.isEmpty) Padding(padding: const EdgeInsets.all(8), child: Text('No comments yet. Be the first to comment.', style: theme.textTheme.bodySmall)),
        if (!loading) ..._children(null).map((comment) => _RecursivePageComment(comment: comment, children: _children, onReply: onReply)),
        if (replyingToUsername != null) Padding(padding: const EdgeInsets.only(left: 40, bottom: 4), child: Row(children: [Expanded(child: Text('Replying to @${replyingToUsername!}', style: theme.textTheme.bodySmall)), IconButton(onPressed: onCancelReply, icon: const Icon(Icons.close, size: 16), visualDensity: VisualDensity.compact)])),
        Row(children: [
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              controller: commentController,
              focusNode: commentFocus,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSubmit(),
              decoration: InputDecoration(
                hintText: replyingToUsername == null ? 'Write a comment…' : 'Write a reply…',
                isDense: true,
                filled: true,
                fillColor: theme.colorScheme.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              ),
            ),
          ),
          IconButton(onPressed: sending ? null : onSubmit, icon: sending ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(Icons.send, color: theme.colorScheme.primary)),
        ]),
      ]),
    );
  }
}

class _RecursivePageComment extends StatelessWidget {
  const _RecursivePageComment({required this.comment, required this.children, required this.onReply});
  final Map<String, dynamic> comment;
  final List<Map<String, dynamic>> Function(String? parentId) children;
  final void Function(Map<String, dynamic>) onReply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = comment['users'] as Map<String, dynamic>?;
    final replies = children(comment['id']?.toString());
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ProfileAvatar(url: user?['profile_photo_url'] as String?, radius: 14),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7), decoration: BoxDecoration(color: theme.colorScheme.surface, borderRadius: BorderRadius.circular(12)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(user?['username'] as String? ?? 'User', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)), const SizedBox(height: 2), Text(comment['content'] as String? ?? '', style: theme.textTheme.bodyMedium)])),
            Padding(padding: const EdgeInsets.only(left: 10, top: 2), child: Row(children: [Text(timeAgo(DateTime.tryParse(comment['created_at']?.toString() ?? '') ?? DateTime.now()), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)), const SizedBox(width: 12), InkWell(onTap: () => onReply(comment), child: Text('Reply', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: theme.colorScheme.primary)))])),
          ])),
        ]),
        if (replies.isNotEmpty) Padding(padding: const EdgeInsets.only(left: 30), child: Column(children: replies.map((reply) => _RecursivePageComment(comment: reply, children: children, onReply: onReply)).toList())),
      ]),
    );
  }
}

class _PageVisitorMedia extends StatelessWidget {
  const _PageVisitorMedia({required this.items});
  final List<PostMediaItem> items;

  @override
  Widget build(BuildContext context) => PageMediaGallery(
    items: items.map((item) => <String, dynamic>{
      'type': item.mediaType,
      'url': item.mediaUrl,
      'name': item.mediaType.toUpperCase(),
    }).toList(),
  );
}
