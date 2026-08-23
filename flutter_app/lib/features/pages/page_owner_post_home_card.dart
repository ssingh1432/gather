import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/supabase_client.dart';
import '../../shared/models/models.dart';
import '../../shared/utils/time_ago.dart';
import '../../shared/widgets/reusables.dart';
import 'page_media_gallery.dart';
import 'page_owner_post_engagement_repository.dart';

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

  Future<void> _reportPost(BuildContext context) async {
    if (SupabaseConfig.currentUserId == null) {
      context.push('/login');
      return;
    }
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => const _PagePostReportDialog(),
    );
    if (result == null) return;
    try {
      await _repo.report(widget.post.id, result['category']!, reason: result['reason']);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report submitted.')));
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not submit report.')));
    }
  }

  Future<void> _toggleLike() async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) { context.push('/login'); return; }
    if (_busy) return;
    final previous = _liked;
    setState(() { _busy = true; _liked = !previous; _likes += previous ? -1 : 1; });
    try {
      await _repo.setLike(widget.post.id, !previous);
    } catch (_) {
      if (mounted) {
        setState(() { _liked = previous; _likes += previous ? 1 : -1; });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not update like.')));
      }
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _commentsSheet() async {
    await showModalBottomSheet(context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => _PageOwnerCommentsSheet(postId: widget.post.id));
    _loadEngagement();
  }

  Future<void> _share() async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) { context.push('/login'); return; }
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

  void _viewPost() {
    if (widget.pageId == null || widget.pageId!.isEmpty) return;
    context.push('/page-post?id=${widget.post.id}&pageId=${widget.pageId}');
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.pageName.isEmpty ? 'Page' : widget.pageName;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: Theme.of(context).cardColor, border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor, width: 8))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ProfileAvatar(url: widget.post.authorAvatarUrl, radius: 20),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Flexible(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w800))), const SizedBox(width: 5), const Icon(Icons.verified_outlined, size: 17)]),
              const SizedBox(height: 2),
              Row(children: [Icon(Icons.campaign_outlined, size: 14, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 4), Text('Page post • ${timeAgo(widget.post.createdAt)}')]),
            ])),
            PopupMenuButton<String>(
              tooltip: 'Post options',
              onSelected: (value) {
                if (value == 'copy') _copyLink(context);
                if (value == 'view') _viewPost();
                if (value == 'page' && widget.pageId != null) context.push('/page-profile?id=${widget.pageId}');
                if (value == 'report') _reportPost(context);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'view', child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.article_outlined), title: Text('View Post'))),
                const PopupMenuItem(value: 'page', child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.business_outlined), title: Text('View Page'))),
                const PopupMenuItem(value: 'copy', child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.link), title: Text('Copy post link'))),
                const PopupMenuItem(value: 'report', child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.flag_outlined), title: Text('Report'))),
              ],
            ),
          ]),
          if (widget.post.textContent.trim().isNotEmpty) ...[const SizedBox(height: 12), Text(widget.post.textContent, style: Theme.of(context).textTheme.bodyLarge)],
          if (widget.post.mediaItems.isNotEmpty) ...[
            const SizedBox(height: 12),
            PageMediaGallery(items: widget.post.mediaItems.map((item) => {'url': item.mediaUrl, 'type': item.mediaType, 'media_url': item.mediaUrl, 'media_type': item.mediaType, if (item.thumbnailUrl != null) 'thumbnail_url': item.thumbnailUrl}).toList()),
          ],
          const SizedBox(height: 4),
          Row(children: [
            TextButton.icon(onPressed: _toggleLike, icon: Icon(_liked ? Icons.favorite : Icons.favorite_border, size: 18), label: Text('$_likes')),
            TextButton.icon(onPressed: _commentsSheet, icon: const Icon(Icons.comment_outlined, size: 18), label: Text('$_comments')),
            TextButton.icon(onPressed: _share, icon: const Icon(Icons.share_outlined, size: 18), label: Text(_shares == 0 ? 'Share' : '$_shares')),
            const Spacer(),
            TextButton(onPressed: _viewPost, child: const Text('View Post')),
            TextButton(onPressed: widget.pageId == null ? null : () => context.push('/page-profile?id=${widget.pageId}'), child: const Text('View Page')),
          ]),
        ]),
      ),
    );
  }
}

class _PagePostReportDialog extends StatefulWidget {
  const _PagePostReportDialog();
  @override State<_PagePostReportDialog> createState() => _PagePostReportDialogState();
}
class _PagePostReportDialogState extends State<_PagePostReportDialog> {
  final _reason = TextEditingController();
  String _category = 'spam';
  @override void dispose() { _reason.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AlertDialog(
    title: const Text('Report Page post'),
    content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      DropdownButtonFormField<String>(value: _category, decoration: const InputDecoration(labelText: 'Reason'), items: const [
        DropdownMenuItem(value: 'spam', child: Text('Spam')),
        DropdownMenuItem(value: 'harassment', child: Text('Harassment or abuse')),
        DropdownMenuItem(value: 'misinformation', child: Text('False or misleading information')),
        DropdownMenuItem(value: 'inappropriate', child: Text('Inappropriate content')),
        DropdownMenuItem(value: 'other', child: Text('Other')),
      ], onChanged: (v) { if (v != null) setState(() => _category = v); }),
      const SizedBox(height: 12),
      TextField(controller: _reason, maxLines: 3, decoration: const InputDecoration(labelText: 'Additional details (optional)', border: OutlineInputBorder())),
    ])),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, {'category': _category, 'reason': _reason.text}), child: const Text('Report'))],
  );
}

class _PageOwnerCommentsSheet extends StatefulWidget {
  const _PageOwnerCommentsSheet({required this.postId});
  final String postId;
  @override State<_PageOwnerCommentsSheet> createState() => _PageOwnerCommentsSheetState();
}
class _PageOwnerCommentsSheetState extends State<_PageOwnerCommentsSheet> {
  final _repo = PageOwnerPostEngagementRepository();
  final _controller = TextEditingController();
  List<Map<String, dynamic>> _comments = const [];
  bool _loading = true;
  bool _sending = false;
  @override void initState() { super.initState(); _load(); }
  @override void dispose() { _controller.dispose(); super.dispose(); }
  Future<void> _load() async { try { _comments = await _repo.listComments(widget.postId); } catch (_) {} if (mounted) setState(() => _loading = false); }
  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    if (SupabaseConfig.currentUserId == null) { context.push('/login'); return; }
    setState(() => _sending = true);
    try { await _repo.addComment(widget.postId, text); _controller.clear(); _loading = true; await _load(); }
    catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not add comment.'))); }
    finally { if (mounted) setState(() => _sending = false); }
  }
  @override Widget build(BuildContext context) => SafeArea(child: SizedBox(height: MediaQuery.sizeOf(context).height * .65, child: Column(children: [
    const Padding(padding: EdgeInsets.all(12), child: Text('Comments', style: TextStyle(fontWeight: FontWeight.w700))),
    Expanded(child: _loading ? const Center(child: CircularProgressIndicator()) : _comments.isEmpty ? const Center(child: Text('No comments yet.')) : ListView.builder(itemCount: _comments.length, itemBuilder: (_, i) {
      final c = _comments[i]; final u = c['users'] is Map ? Map<String, dynamic>.from(c['users'] as Map) : <String,dynamic>{};
      final name = u['display_name']?.toString().trim(); final username = u['username']?.toString().trim();
      return ListTile(leading: ProfileAvatar(url: u['profile_photo_url']?.toString(), radius: 18), title: Text(name?.isNotEmpty == true ? name! : '@${username ?? 'user'}'), subtitle: Text(c['content']?.toString() ?? ''));
    })),
    Padding(padding: EdgeInsets.fromLTRB(12, 8, 12, MediaQuery.viewInsetsOf(context).bottom + 8), child: Row(children: [Expanded(child: TextField(controller: _controller, maxLines: 3, decoration: const InputDecoration(hintText: 'Write a comment…', border: OutlineInputBorder()))), IconButton(onPressed: _sending ? null : _send, icon: const Icon(Icons.send))]),),
  ]));
}
