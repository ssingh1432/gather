import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/supabase_client.dart';
import '../../shared/models/models.dart';
import '../../shared/utils/time_ago.dart';
import '../../shared/widgets/reusables.dart';
import 'page_comments_ux.dart';
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
  Map<String, dynamic>? _replyingTo;
  List<Map<String, dynamic>> _comments = const [];

  @override
  void initState() {
    super.initState();
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
      final rows = await _repo.listComments(widget.post.id);
      final count = await _repo.commentCount(widget.post.id);
      if (mounted) {
        setState(() {
          _comments = rows;
          _commentCount = count;
        });
      }
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
      _replyingTo = comment;
      _commentsExpanded = true;
    });
    _loadComments();
    _commentFocus.requestFocus();
  }

  void _cancelReply() => setState(() => _replyingTo = null);

  Future<void> _submitComment() async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) {
      context.push('/login');
      return;
    }
    final text = _commentCtrl.text.trim();
    if (text.isEmpty || _sendingComment) return;
    final pageId = widget.pageId;
    if (pageId == null || pageId.isEmpty) return;
    setState(() => _sendingComment = true);
    try {
      await _repo.addComment(widget.post.id, pageId, text, parentCommentId: _replyingTo?['id']?.toString());
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
    if (SupabaseConfig.currentUserId == null) {
      context.push('/login');
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
      if (mounted) {
        setState(() {
          _liked = previous;
          _likeCount += previous ? 1 : -1;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not update like. Please try again.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _postLink() {
    final id = widget.pageId;
    if (id == null || id.isEmpty) return null;
    return 'https://eiquoab.xyz/page?id=$id&visitorPostId=${widget.post.id}';
  }

  Future<void> _copyLink() async {
    final link = _postLink();
    if (link == null) return;
    await Clipboard.setData(ClipboardData(text: link));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Post link copied.')));
  }

  void _reportPost() => context.push(Uri(path: '/report', queryParameters: {'postId': widget.post.id}).toString());

  Future<void> _share() async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) {
      context.push('/login');
      return;
    }
    final link = _postLink();
    if (link == null) return;
    final poster = widget.post.authorUsername?.isNotEmpty == true ? '@${widget.post.authorUsername}' : 'Gather user';
    final text = widget.post.textContent.trim();
    try {
      await Share.share(['Posted by $poster on ${widget.pageName.isEmpty ? 'Page' : widget.pageName}', if (text.isNotEmpty) text, link].join('\n\n'));
      await _repo.recordShare(widget.post.id, uid);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not share this post.')));
    }
  }

  void _handleMenu(_PagePostMenuAction action) {
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
    final canViewPage = widget.pageId?.isNotEmpty == true;
    final media = widget.post.mediaItems.map((item) => <String, dynamic>{'type': item.mediaType, 'url': item.mediaUrl, 'name': item.mediaType.toUpperCase()}).toList();

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
              Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, children: [const Icon(Icons.arrow_forward, size: 13), Text(widget.pageName.isEmpty ? 'a Page' : widget.pageName, style: TextStyle(fontWeight: FontWeight.w600)), Text('• ${timeAgo(widget.post.createdAt)}')]),
            ])),
            PopupMenuButton<_PagePostMenuAction>(tooltip: 'Post options', onSelected: _handleMenu, itemBuilder: (_) => [
              const PopupMenuItem(value: _PagePostMenuAction.report, child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.flag_outlined), title: Text('Report post'))),
              PopupMenuItem(value: _PagePostMenuAction.copyLink, enabled: _postLink() != null, child: const ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.link), title: Text('Copy link'))),
            ]),
          ]),
          if (widget.post.textContent.trim().isNotEmpty) ...[const SizedBox(height: 12), Text(widget.post.textContent, style: Theme.of(context).textTheme.bodyLarge)],
          if (media.isNotEmpty) ...[const SizedBox(height: 12), PageMediaGallery(items: media)],
          const SizedBox(height: 6),
          Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 2, runSpacing: 2, children: [
            _PageAction(icon: _liked ? Icons.favorite : Icons.favorite_border, label: _likeCount == 0 ? 'Like' : '$_likeCount', active: _liked, onTap: _busy ? null : _toggleLike),
            _PageAction(icon: _commentsExpanded ? Icons.mode_comment : Icons.mode_comment_outlined, label: _commentCount == 0 ? 'Comment' : '$_commentCount', active: _commentsExpanded, onTap: _toggleComments),
            _PageAction(icon: Icons.share_outlined, label: 'Share', onTap: _share),
            _PageAction(icon: Icons.open_in_new, label: 'View Page & post', onTap: canViewPage ? () => context.push('/page-profile?id=${widget.pageId}') : null),
          ]),
          if (_commentsExpanded) ...[
            const SizedBox(height: 4),
            PageCommentsUx(
              comments: _comments,
              loading: _commentsLoading,
              sending: _sendingComment,
              replyingTo: _replyingTo,
              onReply: _startReply,
              onCancelReply: _cancelReply,
              onSubmit: _submitComment,
              controller: _commentCtrl,
              focusNode: _commentFocus,
            ),
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
