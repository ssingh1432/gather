import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/models/models.dart';
import '../../shared/utils/time_ago.dart';
import '../../shared/widgets/reusables.dart';

/// Visitor-post presentation used when a published Page visitor post is
/// surfaced in Home. This remains Page-specific and does not alter the
/// normal post card or engagement infrastructure.
class PageVisitorPostHomeCard extends StatelessWidget {
  const PageVisitorPostHomeCard({super.key, required this.post, required this.pageId, required this.pageName});
  final PostModel post;
  final String? pageId;
  final String pageName;

  @override
  Widget build(BuildContext context) {
    final authorName = (post.authorUsername == null || post.authorUsername!.isEmpty) ? 'Gather user' : '@${post.authorUsername}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: Theme.of(context).cardColor, border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor, width: 8))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ProfileAvatar(url: post.authorAvatarUrl, radius: 20), const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(authorName, style: const TextStyle(fontWeight: FontWeight.w700)), const SizedBox(height: 2),
              Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, children: [
                const Icon(Icons.arrow_forward, size: 13),
                Text(pageName.isEmpty ? 'a Page' : pageName, style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
                Text('• ${timeAgo(post.createdAt)}'),
              ]),
            ])),
            const Tooltip(message: 'Visitor post', child: Icon(Icons.campaign_outlined, size: 20)),
          ]),
          if (post.textContent.trim().isNotEmpty) ...[const SizedBox(height: 12), Text(post.textContent, style: Theme.of(context).textTheme.bodyLarge)],
          if (post.mediaItems.isNotEmpty) ...[const SizedBox(height: 12), _PageVisitorMedia(items: post.mediaItems)],
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: OutlinedButton.icon(
            onPressed: pageId == null || pageId!.isEmpty ? null : () => context.push('/page-profile?id=$pageId'),
            icon: const Icon(Icons.open_in_new, size: 18), label: const Text('View Page & post'),
          )),
        ]),
      ),
    );
  }
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
