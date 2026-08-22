import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../shared/models/models.dart';
import '../../shared/utils/time_ago.dart';
import '../../shared/widgets/reusables.dart';
import 'page_media_gallery.dart';

/// Home Feed renderer for Page-authored posts. Page content is represented by
/// the Page identity rather than the owner's personal-post card.
class PageOwnerPostHomeCard extends StatelessWidget {
  const PageOwnerPostHomeCard({super.key, required this.post, required this.pageId, required this.pageName});

  final PostModel post;
  final String? pageId;
  final String pageName;

  Future<void> _copyLink(BuildContext context) async {
    if (pageId == null || pageId!.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: 'https://eiquoab.xyz/page?id=$pageId'));
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Page link copied.')));
  }

  @override
  Widget build(BuildContext context) {
    final name = pageName.isEmpty ? 'Page' : pageName;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: Theme.of(context).cardColor, border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor, width: 8))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ProfileAvatar(url: post.authorAvatarUrl, radius: 20),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Flexible(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w800))), const SizedBox(width: 5), const Icon(Icons.verified_outlined, size: 17)]),
              const SizedBox(height: 2),
              Row(children: [Icon(Icons.campaign_outlined, size: 14, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 4), Text('Page post • ${timeAgo(post.createdAt)}')]),
            ])),
            PopupMenuButton<String>(
              tooltip: 'Post options',
              onSelected: (value) {
                if (value == 'copy') _copyLink(context);
                if (value == 'view' && pageId != null) context.push('/page-profile?id=$pageId');
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'copy', child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.link), title: Text('Copy Page link'))),
                PopupMenuItem(value: 'view', enabled: pageId != null && pageId!.isNotEmpty, child: const ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.open_in_new), title: Text('View Page'))),
              ],
            ),
          ]),
          if (post.textContent.trim().isNotEmpty) ...[const SizedBox(height: 12), Text(post.textContent, style: Theme.of(context).textTheme.bodyLarge)],
          if (post.mediaItems.isNotEmpty) ...[
            const SizedBox(height: 12),
            PageMediaGallery(items: post.mediaItems.map((item) => {'url': item.mediaUrl, 'type': item.mediaType, 'media_url': item.mediaUrl, 'media_type': item.mediaType, if (item.thumbnailUrl != null) 'thumbnail_url': item.thumbnailUrl}).toList()),
          ],
          const SizedBox(height: 7),
          Row(children: [
            const Icon(Icons.campaign_outlined, size: 18),
            const SizedBox(width: 6),
            const Expanded(child: Text('Published by this Page')),
            TextButton.icon(onPressed: pageId == null ? null : () => _copyLink(context), icon: const Icon(Icons.link, size: 18), label: const Text('Copy link')),
            TextButton.icon(onPressed: pageId == null ? null : () => context.push('/page-profile?id=$pageId'), icon: const Icon(Icons.open_in_new, size: 18), label: const Text('View Page')),
          ]),
        ]),
      ),
    );
  }
}
