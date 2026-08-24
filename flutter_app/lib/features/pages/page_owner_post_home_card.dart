import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/supabase_client.dart';
import '../../shared/models/models.dart';
import '../../shared/providers/app_providers.dart';
import '../../shared/utils/time_ago.dart';
import '../../shared/widgets/reusables.dart';
import 'page_media_gallery.dart';
import 'page_owner_post_engagement_repository.dart';

/// Home Feed renderer for Page-authored posts. Page content is represented by
/// the Page identity rather than the owner's personal-post card.
class PageOwnerPostHomeCard extends StatefulWidget {
  const PageOwnerPostHomeCard({super.key, required this.post, required this.pageId, required this.pageName});
  final PostModel post;
  final String? pageId;
  final String pageName;

  @override
  State<PageOwnerPostHomeCard> createState() => _PageOwnerPostHomeCardState();
}

class _PageOwnerPostHomeCardState extends State<PageOwnerPostHomeCard> {
  final _repo = PageOwnerPostEngagementRepository();
  bool _liked = false;
  int _likes = 0;
  int _comments = 0;
  int _shares = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _likes = widget.post.likeCount;
    _comments = widget.post.commentCount;
    _shares = widget.post.shareCount;
    _liked = widget.post.isLiked;
    _loadEngagement();
  }

  Future<void> _loadEngagement() async {
    try {
      final e = await _repo.getEngagement(widget.post.id);
      if (!mounted) return;
      setState(() {
        _likes = e['likes'] as int;
        _comments = e['comments'] as int;
        _shares = e['shares'] as int;
        _liked = e['liked'] as bool;
      });
    } catch (_) {}
  }

  Future<void> _copyLink(BuildContext context) async {
    if (widget.pageId == null || widget.pageId!.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: 'https://eiquoab.xyz/page?id=${widget.pageId}&postId=${widget.post.id}'));
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Post link copied.')));
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
      await _repo.setLike(widget.post.id, !previous);
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
      builder: (_) => _PageOwnerCommentsSheet(postId: widget.post.id),
    );
    _loadEngagement();
  }

  Future<void> _share() async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) {
      context.push('/login');
      return;
    }
    if (widget.pageId == null || widget.pageId!.isEmpty) return;
    final url = 'https://eiquoab.xyz/page?id=${widget.pageId}&postId=${widget.post.id}';
    final text = widget.post.textContent.trim();
    try {
      await Share.share([if (text.isNotEmpty) text, url].join('\n\n'));
      await _repo.recordShare(widget.post.id);
      if (mounted) setState(() => _shares++);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not share this post.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.pageName.isEmpty ? 'Page' : widget.pageName;
    final mediaItems = widget.post.mediaItems.map((item) => <String, dynamic>{
      'url': item.mediaUrl,
      'type': item.mediaType,
      'media_url': item.mediaUrl,
      'media_type': item.mediaType,
      if (item.thumbnailUrl != null) 'thumbnail_url': item.thumbnailUrl,
    }).toList();
    final viewerItems = mediaItems.where((item) => item['type'] != 'event').toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor, width: 8)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ProfileAvatar(url: widget.post.authorAvatarUrl, radius: 20),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w800))),
                const SizedBox(width: 5),
                const Icon(Icons.verified_outlined, size: 17),
              ]),
              const SizedBox(height: 2),
              Row(children: [
                Icon(Icons.campaign_outlined, size: 14, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 4),
                Text('Page post • ${timeAgo(widget.post.createdAt)}'),
              ]),
            ])),
            PopupMenuButton<String>(
              tooltip: 'Post options',
              onSelected: (value) {
                if (value == 'copy') _copyLink(context);
                if (value == 'page' && widget.pageId != null) context.push('/page-profile?id=${widget.pageId}');
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'page', child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.business_outlined), title: Text('View Page'))),
                PopupMenuItem(value: 'copy', child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.link), title: Text('Copy post link'))),
              ],
            ),
          ]),
          if (widget.post.textContent.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(widget.post.textContent, style: Theme.of(context).textTheme.bodyLarge),
          ],
          if (mediaItems.isNotEmpty) ...[
            const SizedBox(height: 12),
            PageMediaGallery(
              items: mediaItems,
              onOpen: viewerItems.isEmpty ? null : (index) => showPageMediaViewer(context, viewerItems, initialIndex: index),
            ),
          ],
          const SizedBox(height: 4),
          Row(children: [
            TextButton.icon(
              onPressed: _toggleLike,
              icon: Icon(_liked ? Icons.favorite : Icons.favorite_border, size: 18),
              label: Text('$_likes'),
            ),
            TextButton.icon(
              onPressed: _commentsSheet,
              icon: const Icon(Icons.comment_outlined, size: 18),
              label: Text('$_comments'),
            ),
            TextButton.icon(
              onPressed: _share,
              icon: const Icon(Icons.share_outlined, size: 18),
              label: Text(_shares == 0 ? 'Share' : '$_shares'),
            ),
            const Spacer(),
            TextButton(
              onPressed: widget.pageId == null ? null : () => context.push('/page-profile?id=${widget.pageId}'),
              child: const Text('View Page'),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _PageOwnerCommentsSheet extends StatefulWidget {
  const _PageOwnerCommentsSheet({required this.postId});
  final String postId;

  @override
  State<_PageOwnerCommentsSheet> createState() => _PageOwnerCommentsSheetState();
}

class _PageOwnerCommentsSheetState extends State<_PageOwnerCommentsSheet> {
  final _repo = PageOwnerPostEngagementRepository();
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
      setState(() => _comments = rows);
    } catch (_) {
      if (mounted) setState(() => _comments = const []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _childrenOf(String? parentId) => _comments
      .where((comment) => comment['parent_comment_id']?.toString() == parentId)
      .toList();

  String _displayName(Map<String, dynamic> comment) {
    final users = comment['users'] is Map ? Map<String, dynamic>.from(comment['users'] as Map) : <String, dynamic>{};
    final name = users['display_name']?.toString().trim();
    final username = users['username']?.toString().trim();
    if (name?.isNotEmpty == true) return name!;
    if (username?.isNotEmpty == true) return '@$username';
    return 'User';
  }

  String? _avatarUrl(Map<String, dynamic> comment) {
    final users = comment['users'] is Map ? Map<String, dynamic>.from(comment['users'] as Map) : <String, dynamic>{};
    return users['profile_photo_url']?.toString();
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
      final parentId = _replyingTo?['id']?.toString();
      await _repo.addComment(widget.postId, text, parentCommentId: parentId);
      _controller.clear();
      setState(() => _replyingTo = null);
      await _load();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not add comment.')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _startReply(Map<String, dynamic> comment) {
    setState(() => _replyingTo = comment);
    _focusNode.requestFocus();
  }

  Widget _commentRow(BuildContext context, Map<String, dynamic> comment) {
    final theme = Theme.of(context);
    final created = DateTime.tryParse(comment['created_at']?.toString() ?? '');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () {
              final userId = comment['user_id']?.toString();
              if (userId != null && userId.isNotEmpty) context.push('/user?id=$userId');
            },
            child: ProfileAvatar(url: _avatarUrl(comment), radius: 14),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_displayName(comment), style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 1),
                  Text(comment['content']?.toString() ?? '', style: theme.textTheme.bodyMedium),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 10, top: 2),
                child: Row(children: [
                  if (created != null) Text(timeAgo(created.toLocal()), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                  if (created != null) const SizedBox(width: 12),
                  InkWell(
                    onTap: () => _startReply(comment),
                    child: Text('Reply', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: theme.colorScheme.primary)),
                  ),
                ]),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _commentTree(BuildContext context, Map<String, dynamic> comment, {int depth = 0, Set<String>? ancestors}) {
    final id = comment['id']?.toString();
    final path = {...?ancestors, if (id != null) id};
    final children = id == null || path.length > 32
        ? const <Map<String, dynamic>>[]
        : _childrenOf(id).where((child) => !path.contains(child['id']?.toString())).toList();
    final left = depth == 0 ? 0.0 : depth.clamp(1, 5).toDouble() * 28.0;
    return Padding(
      padding: EdgeInsets.only(left: left),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _commentRow(context, comment),
        for (final child in children) _commentTree(context, child, depth: depth + 1, ancestors: path),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topLevel = _childrenOf(null);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .72,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Row(children: [
              const Expanded(child: Text('Comments', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18))),
              Text('${_comments.length}', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : topLevel.isEmpty
                    ? Center(child: Text('No comments yet. Be the first to reply.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)))
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        children: [for (final comment in topLevel) _commentTree(context, comment)],
                      ),
          ),
          if (_replyingTo != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Row(children: [
                Expanded(child: Text('Replying to ${_displayName(_replyingTo!)}', style: theme.textTheme.bodySmall)),
                IconButton(icon: const Icon(Icons.close, size: 16), visualDensity: VisualDensity.compact, onPressed: () => setState(() => _replyingTo = null)),
              ]),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(12, 6, 12, MediaQuery.viewInsetsOf(context).bottom + 10),
            child: Row(children: [
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
                    controller: _controller,
                    focusNode: _focusNode,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: 'Comment as ${username ?? 'you'}',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                    ),
                    onSubmitted: (_) => _send(),
                  );
                }),
              ),
              IconButton(
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(Icons.send, color: theme.colorScheme.primary),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
