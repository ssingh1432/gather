import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/supabase_client.dart';
import '../../shared/utils/time_ago.dart';
import 'page_media_gallery.dart';
import 'page_post_media_ux.dart';
import 'page_visitor_post_repository.dart';

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
      builder: (_) => _CommentsSheet(postId: widget.post['id'] as String),
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
          if (media.isNotEmpty) PagePostMediaAttachmentList(items: media),
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
  const _CommentsSheet({required this.postId});
  final String postId;

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final _repo = PageVisitorPostRepository();
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  List<Map<String, dynamic>> _comments = const [];
  bool _loading = true;
  bool _sending = false;
  Map<String, dynamic>? _replyingTo;

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
      _comments = await _repo.listComments(widget.postId);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  List<Map<String, dynamic>> get _topLevel => _comments.where((c) => c['parent_comment_id'] == null).toList();
  List<Map<String, dynamic>> _repliesTo(String id) => _comments.where((c) => c['parent_comment_id'] == id).toList();

  String _displayName(Map<String, dynamic> comment) {
    final user = comment['users'] is Map ? Map<String, dynamic>.from(comment['users'] as Map) : <String, dynamic>{};
    final name = user['display_name']?.toString().trim();
    final username = user['username']?.toString().trim();
    return name?.isNotEmpty == true ? name! : '@${username?.isNotEmpty == true ? username : 'user'}';
  }

  String _username(Map<String, dynamic> comment) {
    final user = comment['users'] is Map ? Map<String, dynamic>.from(comment['users'] as Map) : <String, dynamic>{};
    final username = user['username']?.toString().trim();
    return username?.isNotEmpty == true ? username! : 'user';
  }

  String _userId(Map<String, dynamic> comment) => comment['user_id']?.toString() ?? '';

  void _startReply(Map<String, dynamic> comment) {
    setState(() => _replyingTo = comment);
    _focusNode.requestFocus();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) {
      context.push('/login');
      return;
    }

    setState(() => _sending = true);
    try {
      final parentId = _replyingTo == null ? null : (_replyingTo!['parent_comment_id']?.toString() ?? _replyingTo!['id']?.toString());
      await _repo.addComment(widget.postId, '', text, parentCommentId: parentId);
      _controller.clear();
      setState(() => _replyingTo = null);
      _loading = true;
      await _load();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not post comment. Please retry.')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .78,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: Row(
                children: [
                  const Expanded(child: Text('Comments', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17))),
                  Text('${_comments.length}', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _topLevel.isEmpty
                      ? const Center(child: Text('No comments yet. Be the first to reply.'))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                          itemCount: _topLevel.length,
                          itemBuilder: (_, i) {
                            final comment = _topLevel[i];
                            return _PageCommentThread(
                              comment: comment,
                              replies: _repliesTo(comment['id']?.toString() ?? ''),
                              displayName: _displayName,
                              username: _username,
                              userId: _userId,
                              onReply: _startReply,
                            );
                          },
                        ),
            ),
            if (_replyingTo != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 2, 14, 4),
                child: Row(
                  children: [
                    Expanded(child: Text('Replying to @${_username(_replyingTo!)}', style: theme.textTheme.bodySmall)),
                    IconButton(icon: const Icon(Icons.close, size: 17), visualDensity: VisualDensity.compact, onPressed: () => setState(() => _replyingTo = null)),
                  ],
                ),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(12, 6, 12, MediaQuery.viewInsetsOf(context).bottom + 10),
              child: Row(
                children: [
                  const CircleAvatar(radius: 15, child: Icon(Icons.person_outline, size: 17)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: _replyingTo == null ? 'Write a comment…' : 'Write a reply…',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .5),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  IconButton(
                    onPressed: _sending ? null : _send,
                    icon: _sending ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(Icons.send_rounded, color: theme.colorScheme.primary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageCommentThread extends StatefulWidget {
  const _PageCommentThread({required this.comment, required this.replies, required this.displayName, required this.username, required this.userId, required this.onReply});
  final Map<String, dynamic> comment;
  final List<Map<String, dynamic>> replies;
  final String Function(Map<String, dynamic>) displayName;
  final String Function(Map<String, dynamic>) username;
  final String Function(Map<String, dynamic>) userId;
  final void Function(Map<String, dynamic>) onReply;

  @override
  State<_PageCommentThread> createState() => _PageCommentThreadState();
}

class _PageCommentThreadState extends State<_PageCommentThread> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final replyCount = widget.replies.length;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PageCommentRow(
            comment: widget.comment,
            displayName: widget.displayName(widget.comment),
            username: widget.username(widget.comment),
            userId: widget.userId(widget.comment),
            onReply: () => widget.onReply(widget.comment),
          ),
          if (replyCount > 0)
            Padding(
              padding: const EdgeInsets.only(left: 42, top: 2),
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
                    _PageCommentRow(
                      comment: reply,
                      displayName: widget.displayName(reply),
                      username: widget.username(reply),
                      userId: widget.userId(reply),
                      replyToName: widget.username(widget.comment),
                      onReply: () => widget.onReply(reply),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PageCommentRow extends StatelessWidget {
  const _PageCommentRow({required this.comment, required this.displayName, required this.username, required this.userId, required this.onReply, this.replyToName});
  final Map<String, dynamic> comment;
  final String displayName;
  final String username;
  final String userId;
  final String? replyToName;
  final VoidCallback onReply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = comment['users'] is Map ? Map<String, dynamic>.from(comment['users'] as Map) : <String, dynamic>{};
    final avatar = user['profile_photo_url']?.toString();
    final content = comment['content']?.toString() ?? '';
    final created = DateTime.tryParse(comment['created_at']?.toString() ?? '');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: userId.isEmpty ? null : () => context.push('/user?id=$userId'),
            child: avatar?.isNotEmpty == true
                ? ClipOval(child: PageNetworkImage(url: avatar!, width: 30, height: 30))
                : const CircleAvatar(radius: 15, child: Icon(Icons.person_outline, size: 17)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                  decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .5), borderRadius: BorderRadius.circular(13)),
                  child: RichText(
                    text: TextSpan(
                      style: theme.textTheme.bodyMedium,
                      children: [
                        if (replyToName != null)
                          WidgetSpan(
                            alignment: PlaceholderAlignment.baseline,
                            baseline: TextBaseline.alphabetic,
                            child: GestureDetector(
                              onTap: userId.isEmpty ? null : () => context.push('/user?id=$userId'),
                              child: Text('@$replyToName ', style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
                            ),
                          ),
                        TextSpan(text: displayName, style: const TextStyle(fontWeight: FontWeight.w600)),
                        const TextSpan(text: '\n'),
                        TextSpan(text: content),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 10, top: 2),
                  child: Row(
                    children: [
                      if (created != null) Text(timeAgo(created), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                      const SizedBox(width: 12),
                      InkWell(onTap: onReply, child: Text('Reply', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: theme.colorScheme.primary))),
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
