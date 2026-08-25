import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/supabase_client.dart';
import '../../shared/utils/time_ago.dart';
import 'page_comments_ux.dart';
import 'page_media_gallery.dart';
import 'page_visitor_post_repository.dart';

// Page-only post card. Keep Page UX isolated from normal/community posts.
class PageVisitorPostCard extends StatefulWidget {
  const PageVisitorPostCard({super.key, required this.post, required this.page});
  final Map<String, dynamic> post;
  final Map<String, dynamic> page;

  @override
  State<PageVisitorPostCard> createState() => _PageVisitorPostCardState();
}

class _PageVisitorPostCardState extends State<PageVisitorPostCard> {
  final _repo = PageVisitorPostRepository();
  bool _liked = false;
  int _likes = 0;
  int _comments = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _likes = (widget.post['like_count'] as int?) ?? 0;
    _comments = (widget.post['comment_count'] as int?) ?? 0;
    _loadLikeState();
  }

  Future<void> _loadLikeState() async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) return;
    try {
      final liked = await _repo.getLikeState(widget.post['id'] as String, uid);
      if (mounted) setState(() => _liked = liked);
    } catch (_) {}
  }

  Future<void> _toggleLike() async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) {
      context.push('/login');
      return;
    }
    if (_busy) return;
    final previous = _liked;
    setState(() {
      _busy = true;
      _liked = !previous;
      _likes += previous ? -1 : 1;
    });
    try {
      await _repo.setLike(widget.post['id'] as String, !previous);
    } catch (_) {
      if (mounted) {
        setState(() {
          _liked = previous;
          _likes += previous ? 1 : -1;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not update like.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _commentsSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CommentsSheet(postId: widget.post['id'] as String, pageId: widget.post['page_id'] as String),
    );
    if (!mounted) return;
    try {
      final count = await _repo.commentCount(widget.post['id'] as String);
      if (mounted) setState(() => _comments = count);
    } catch (_) {}
  }

  Future<void> _share() async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) {
      context.push('/login');
      return;
    }

    final id = widget.post['id'] as String;
    final pageId = widget.post['page_id'] as String;
    final text = (widget.post['content'] as String?)?.trim();
    final pageName = widget.page['name']?.toString() ?? 'Page';
    final author = widget.post['users'] is Map
        ? Map<String, dynamic>.from(widget.post['users'] as Map)
        : <String, dynamic>{};
    final authorName = author['display_name']?.toString().trim();
    final poster = authorName?.isNotEmpty == true ? authorName! : 'Gather user';
    final url = 'https://eiquoab.xyz/page?id=$pageId&visitorPostId=$id';
    final body = ['Posted by $poster on $pageName', if (text?.isNotEmpty == true) text!, url].join('\n\n');

    try {
      await Share.share(body);
      await _repo.recordShare(id, uid);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not share this post.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final author = widget.post['users'] is Map
        ? Map<String, dynamic>.from(widget.post['users'] as Map)
        : <String, dynamic>{};
    final name = author['display_name']?.toString().trim();
    final username = author['username']?.toString().trim();
    final poster = name?.isNotEmpty == true
        ? name!
        : username?.isNotEmpty == true
            ? '@$username'
            : 'Gather user';
    final media = widget.post['media'] is List
        ? List<Map<String, dynamic>>.from((widget.post['media'] as List).whereType<Map>())
        : const <Map<String, dynamic>>[];
    final event = widget.post['page_events'] is Map
        ? Map<String, dynamic>.from(widget.post['page_events'] as Map)
        : null;
    final created = widget.post['created_at']?.toString();
    final pageName = widget.page['name']?.toString() ?? 'Page';
    final authorSubtitle = username?.isNotEmpty == true && name?.isNotEmpty == true ? '@$username' : null;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                _Avatar(url: author['profile_photo_url']?.toString(), icon: Icons.person_outline),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(poster, style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text('posted on $pageName', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      if (authorSubtitle != null)
                        Text(authorSubtitle, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                _Avatar(url: widget.page['logo_url']?.toString(), icon: Icons.flag_outlined),
              ],
            ),
          ),
          if (created != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(timeAgo(DateTime.parse(created)), style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
          if ((widget.post['content'] as String?)?.trim().isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Text(widget.post['content'] as String),
            ),
          if (media.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: PageMediaGallery(
                items: media,
                onOpen: (index) => showPageMediaViewer(context, media, initialIndex: index),
              ),
            ),
          if (event != null) PageEventAttachmentCard(event: event),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
            child: Row(
              children: [
                Expanded(child: _ActionButton(icon: _liked ? Icons.thumb_up : Icons.thumb_up_outlined, label: 'Like', count: _likes, active: _liked, onTap: _toggleLike)),
                Expanded(child: _ActionButton(icon: Icons.mode_comment_outlined, label: 'Comment', count: _comments, onTap: _commentsSheet)),
                Expanded(child: _ActionButton(icon: Icons.share_rounded, label: 'Share', onTap: _share)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.label, required this.onTap, this.count, this.active = false});
  final IconData icon;
  final String label;
  final int? count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 19, color: color),
              const SizedBox(width: 5),
              Flexible(child: Text(count == null ? label : '$label $count', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color))),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.icon});
  final String? url;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    if (url?.isNotEmpty == true) {
      return ClipOval(
        child: PageNetworkImage(url: url!, width: 36, height: 36, errorWidget: (_) => CircleAvatar(radius: 18, child: Icon(icon, size: 18))),
      );
    }
    return CircleAvatar(radius: 18, child: Icon(icon, size: 18));
  }
}

class _CommentsSheet extends StatefulWidget {
  const _CommentsSheet({required this.postId, required this.pageId});
  final String postId;
  final String pageId;

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final _repo = PageVisitorPostRepository();
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  List<Map<String, dynamic>> _comments = const [];
  Map<String, dynamic>? _replyingTo;
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await _repo.listComments(widget.postId);
      if (!mounted) return;
      setState(() {
        _comments = rows;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startReply(Map<String, dynamic> comment) {
    setState(() => _replyingTo = comment);
    _focusNode.requestFocus();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    if (SupabaseConfig.currentUserId == null) {
      context.push('/login');
      return;
    }
    setState(() => _sending = true);
    try {
      // Preserve the exact reply target. A reply to a reply must reference
      // that reply, rather than being silently redirected to the root comment.
      await _repo.addComment(widget.postId, widget.pageId, text, parentCommentId: _replyingTo?['id']?.toString());
      _controller.clear();
      setState(() => _replyingTo = null);
      await _load();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not post comment. Please retry.')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * .72;
    return SafeArea(
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: PageCommentsUx(
            comments: _comments,
            loading: _loading,
            sending: _sending,
            replyingTo: _replyingTo,
            onReply: _startReply,
            onCancelReply: () => setState(() => _replyingTo = null),
            onSubmit: _send,
            controller: _controller,
            focusNode: _focusNode,
          ),
        ),
      ),
    );
  }
}
