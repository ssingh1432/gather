import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/models/models.dart';
import '../../shared/utils/time_ago.dart';
import '../../shared/widgets/reusables.dart';

/// Visitor-post presentation used when a Page visitor post is surfaced in
/// Home. Visitor posts are not rows in `posts`, so they deliberately do not
/// expose the normal post Like/Comment/Bookmark controls.
class PageVisitorPostHomeCard extends StatelessWidget {
  const PageVisitorPostHomeCard({
    super.key,
    required this.post,
    required this.pageId,
    required this.pageName,
  });

  final PostModel post;
  final String? pageId;
  final String pageName;

  @override
  Widget build(BuildContext context) {
    final authorName = (post.authorUsername == null || post.authorUsername!.isEmpty)
        ? 'Gather user'
        : '@${post.authorUsername}';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor, width: 8),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ProfileAvatar(url: post.authorAvatarUrl, radius: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        authorName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 4,
                        children: [
                          const Icon(Icons.arrow_forward, size: 13),
                          Text(
                            pageName.isEmpty ? 'a Page' : pageName,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          Text('• ${timeAgo(post.createdAt)}'),
                        ],
                      ),
                    ],
                  ),
                ),
                const Tooltip(
                  message: 'Visitor post',
                  child: Icon(Icons.campaign_outlined, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              post.textContent,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: pageId == null || pageId!.isEmpty
                      ? null
                      : () => context.push('/page-profile?id=$pageId'),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('View Page'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: pageId == null || pageId!.isEmpty
                      ? null
                      : () => context.push('/page-profile?id=$pageId'),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Post on Page'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
