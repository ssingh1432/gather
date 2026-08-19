import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/models/models.dart';
import '../../shared/utils/time_ago.dart';
import '../../shared/widgets/reusables.dart';
import 'page_visitor_post_repository.dart';

/// Page-only Home presentation. Normal post cards and shared engagement
/// infrastructure remain unchanged.
class PageVisitorPostHomeCard extends StatefulWidget {
  const PageVisitorPostHomeCard({super.key, required this.post, required this.pageId, required this.pageName});
  final PostModel post;
  final String? pageId;
  final String pageName;

  @override
  State<PageVisitorPostHomeCard> createState() => _PageVisitorPostHomeCardState();
}

class _PageVisitorPostHomeCardState extends State<PageVisitorPostHomeCard> {
  final _repo = PageVisitorPostRepository();
  bool _liked = false;
  int _likeCount = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _likeCount = widget.post.likeCount;
    _loadLikeState();
  }

  Future<void> _loadLikeState() async {
    final uid = _currentUserId;
    if (uid == null) return;
    try {
      final liked = await _repo.getLikeState(widget.post.id, uid);
      if (mounted) setState(() => _liked = liked);
    } catch (_) {}
  }

  String? get _currentUserId => SupabaseConfig.currentUserId;

  Future<void> _toggleLike() async {
    final uid = _currentUserId;
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

  @override
  Widget build(BuildContext context) {
    final authorName = (widget.post.authorUsername == null || widget.post.authorUsername!.isEmpty) ? 'Gather user' : '@${widget.post.authorUsername}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: Theme.of(context).cardColor, border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor, width: 8))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ProfileAvatar(url: widget.post.authorAvatarUrl, radius: 20), const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(authorName, style: const TextStyle(fontWeight: FontWeight.w700)), const SizedBox(height: 2),
              Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, children: [
                const Icon(Icons.arrow_forward, size: 13),
                Text(widget.pageName.isEmpty ? 'a Page' : widget.pageName, style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
                Text('• ${timeAgo(widget.post.createdAt)}'),
              ]),
            ])),
            const Tooltip(message: 'Visitor post', child: Icon(Icons.campaign_outlined, size: 20)),
          ]),
          if (widget.post.textContent.trim().isNotEmpty) ...[const SizedBox(height: 12), Text(widget.post.textContent, style: Theme.of(context).textTheme.bodyLarge)],
          if (widget.post.mediaItems.isNotEmpty) ...[const SizedBox(height: 12), _PageVisitorMedia(items: widget.post.mediaItems)],
          const SizedBox(height: 8),
          Row(children: [
            _PageAction(icon: _liked ? Icons.favorite : Icons.favorite_border, label: _likeCount == 0 ? 'Like' : '$_likeCount', active: _liked, onTap: _busy ? null : _toggleLike),
            const Spacer(),
          ]),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: OutlinedButton.icon(
            onPressed: widget.pageId == null || widget.pageId!.isEmpty ? null : () => context.push('/page-profile?id=${widget.pageId}'),
            icon: const Icon(Icons.open_in_new, size: 18), label: const Text('View Page & post'),
          )),
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
    icon: Icon(icon, size: 20, color: active ? Theme.of(context).colorScheme.primary : null),
    label: Text(label, style: TextStyle(color: active ? Theme.of(context).colorScheme.primary : null)),
  );
}

class _PageVisitorMedia extends StatelessWidget {
  const _PageVisitorMedia({required this.items});
  final List<PostMediaItem> items;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: Column(children: items.map((item) {
      final isImage = item.mediaType == 'image' || item.mediaType == 'gif';
      if (!isImage) {
        return Container(width: double.infinity, padding: const EdgeInsets.all(16), color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Row(children: [Icon(_iconFor(item.mediaType)), const SizedBox(width: 10), Expanded(child: Text(item.mediaType.toUpperCase()))]));
      }
      return Padding(padding: const EdgeInsets.only(bottom: 4), child: Image.network(item.mediaUrl, width: double.infinity, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const SizedBox(height: 120, child: Center(child: Icon(Icons.broken_image_outlined)))));
    }).toList()),
  );

  IconData _iconFor(String type) => switch (type) {
    'video' => Icons.play_circle_outline,
    'document' => Icons.description_outlined,
    _ => Icons.attach_file,
  };
}
