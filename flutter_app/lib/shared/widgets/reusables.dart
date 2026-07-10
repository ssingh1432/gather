import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/supabase_client.dart';
import '../../features/data/repositories.dart';
import '../models/models.dart';
import '../utils/time_ago.dart';
import 'auth_redirects.dart';

class ProfileAvatar extends StatelessWidget {
  final String? url;
  final double radius;
  const ProfileAvatar({super.key, this.url, this.radius = 20});
  @override
  Widget build(BuildContext context) => CircleAvatar(
        radius: radius,
        backgroundImage: (url != null && url!.isNotEmpty) ? CachedNetworkImageProvider(url!) : null,
        child: url == null || url!.isEmpty ? Icon(Icons.person, size: radius) : null,
      );
}

/// Rich, highly-interactive feed post card: avatar + name + timestamp,
/// location/feeling line, hashtag-style tags, an optional embedded preview
/// of a quoted/replied-to post, an image, and a full action bar (like,
/// comment, share, bookmark) plus a report/quote-share overflow menu.
class PostCard extends StatelessWidget {
  final PostModel post;
  final VoidCallback onLike;
  final VoidCallback onBookmark;
  final VoidCallback onComment;
  final bool liked;
  final bool bookmarked;

  const PostCard({
    super.key,
    required this.post,
    required this.onLike,
    required this.onBookmark,
    required this.onComment,
    this.liked = false,
    this.bookmarked = false,
  });

  void _openAuthorProfile(BuildContext context) {
    if (post.authorId.isEmpty) return;
    context.push('/user?id=${post.authorId}');
  }

  Future<void> _openShareSheet(BuildContext context) async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) {
      redirectToLogin(context, redirect: '/', message: 'Please log in or create an account to share posts.');
      return;
    }
    if (!context.mounted) return;
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: const Text('Share to...'),
              subtitle: const Text('System share sheet or copy link'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final snippet = post.textContent.isNotEmpty ? post.textContent : 'Check out this post on Gather';
                await Share.share('$snippet\n\nhttps://eiquoab.xyz/post?id=${post.id}');
                await FeedRepository().sharePost(post.id, uid, target: 'external');
              },
            ),
            ListTile(
              leading: const Icon(Icons.repeat),
              title: const Text('Share to your feed'),
              subtitle: const Text('Post this to your own feed with a comment'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await FeedRepository().sharePost(post.id, uid, target: 'feed');
                if (context.mounted) context.push('/create-post?quotePostId=${post.id}');
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openOverflowMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('Copy link'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await Clipboard.setData(ClipboardData(text: 'https://eiquoab.xyz/post?id=${post.id}'));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied.')));
                }
              },
            ),
            ListTile(
              leading: Icon(Icons.flag_outlined, color: Theme.of(context).colorScheme.error),
              title: Text('Report post', style: TextStyle(color: Theme.of(context).colorScheme.error)),
              onTap: () {
                Navigator.pop(sheetContext);
                final uid = SupabaseConfig.currentUserId;
                if (uid == null) {
                  redirectToLogin(context, redirect: '/', message: 'Please log in or create an account to report content.');
                  return;
                }
                context.push('/report?postId=${post.id}');
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _PostHeader(post: post, onTapAuthor: () => _openAuthorProfile(context), onTapMore: () => _openOverflowMenu(context)),
            if (post.location != null && post.location!.isNotEmpty || post.feeling != null && post.feeling!.isNotEmpty) ...[
              const SizedBox(height: 6),
              _FeelingLocationLine(post: post),
            ],
            if (post.textContent.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(post.textContent),
            ],
            if (post.tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              _TagChips(tags: post.tags),
            ],
            if (post.replyTo != null) ...[
              const SizedBox(height: 10),
              _QuotedPostCard(quoted: post.replyTo!),
            ],
            if (post.displayImageUrl != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(
                    imageUrl: post.displayImageUrl!,
                    cacheKey: post.imageCacheKey,
                    height: 220,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    memCacheWidth: 1080,
                    fadeInDuration: const Duration(milliseconds: 120),
                    placeholder: (context, url) => const SkeletonBox(height: 220),
                    errorWidget: (context, url, error) => const SizedBox(
                      height: 220,
                      child: Center(child: Icon(Icons.broken_image_outlined)),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 4),
            _PostActionBar(
              post: post,
              liked: liked,
              bookmarked: bookmarked,
              onLike: onLike,
              onComment: onComment,
              onBookmark: onBookmark,
              onShare: () => _openShareSheet(context),
            ),
          ]),
        ),
      );
}

class _PostHeader extends StatelessWidget {
  final PostModel post;
  final VoidCallback onTapAuthor;
  final VoidCallback onTapMore;
  const _PostHeader({required this.post, required this.onTapAuthor, required this.onTapMore});

  @override
  Widget build(BuildContext context) => Row(children: [
        GestureDetector(
          onTap: onTapAuthor,
          child: ProfileAvatar(url: post.authorAvatarUrl, radius: 19),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: onTapAuthor,
                child: Text(post.authorUsername ?? 'Unknown', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              ),
              Row(children: [
                Text(timeAgo(post.createdAt), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline)),
                if (post.communityId != null) ...[
                  Text(' · community', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline)),
                ],
              ]),
            ],
          ),
        ),
        IconButton(onPressed: onTapMore, icon: const Icon(Icons.more_horiz), tooltip: 'More'),
      ]);
}

class _FeelingLocationLine extends StatelessWidget {
  final PostModel post;
  const _FeelingLocationLine({required this.post});

  @override
  Widget build(BuildContext context) {
    final parts = <String>[];
    if (post.feeling != null && post.feeling!.isNotEmpty) parts.add('is feeling ${post.feeling}');
    if (post.location != null && post.location!.isNotEmpty) parts.add('📍 ${post.location}');
    if (parts.isEmpty) return const SizedBox.shrink();
    return Text(
      parts.join('  ·  '),
      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline, fontStyle: FontStyle.italic),
    );
  }
}

class _TagChips extends StatelessWidget {
  final List<String> tags;
  const _TagChips({required this.tags});

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 6,
        runSpacing: -6,
        children: [
          for (final tag in tags)
            ActionChip(
              label: Text('#$tag', style: const TextStyle(fontSize: 12)),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              onPressed: () => context.push('/search?q=${Uri.encodeComponent(tag)}'),
            ),
        ],
      );
}

/// Embedded preview shown when a post is a quote/reply-share of another
/// post — tapping it opens the original.
class _QuotedPostCard extends StatelessWidget {
  final QuotedPostPreview quoted;
  const _QuotedPostCard({required this.quoted});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (quoted.removed) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text('Original post is no longer available.', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
      );
    }
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => context.push('/post?id=${quoted.id}'),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ProfileAvatar(url: quoted.authorAvatarUrl, radius: 13),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(
                        quoted.authorUsername ?? 'Unknown',
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text('  ·  ${timeAgo(quoted.createdAt)}', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                  ]),
                  if (quoted.textContent.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(quoted.textContent, maxLines: 3, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                    ),
                ],
              ),
            ),
            if (quoted.imageUrl != null) ...[
              const SizedBox(width: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: CachedNetworkImage(imageUrl: quoted.imageUrl!, width: 44, height: 44, fit: BoxFit.cover),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PostActionBar extends StatelessWidget {
  final PostModel post;
  final bool liked;
  final bool bookmarked;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onBookmark;
  final VoidCallback onShare;

  const _PostActionBar({
    required this.post,
    required this.liked,
    required this.bookmarked,
    required this.onLike,
    required this.onComment,
    required this.onBookmark,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(children: [
      _ActionButton(
        icon: liked ? Icons.favorite : Icons.favorite_border,
        color: liked ? Colors.redAccent : null,
        label: post.likeCount > 0 ? '${post.likeCount}' : null,
        onTap: onLike,
      ),
      const SizedBox(width: 4),
      _ActionButton(
        icon: Icons.mode_comment_outlined,
        label: post.commentCount > 0 ? '${post.commentCount}' : null,
        onTap: onComment,
      ),
      const SizedBox(width: 4),
      _ActionButton(
        icon: Icons.repeat,
        label: post.shareCount > 0 ? '${post.shareCount}' : null,
        onTap: onShare,
      ),
      const Spacer(),
      IconButton(
        onPressed: onBookmark,
        icon: Icon(bookmarked ? Icons.bookmark : Icons.bookmark_border, color: bookmarked ? theme.colorScheme.primary : null),
        tooltip: 'Save',
      ),
    ]);
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String? label;
  final Color? color;
  final VoidCallback onTap;
  const _ActionButton({required this.icon, required this.onTap, this.label, this.color});

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(children: [
            Icon(icon, size: 20, color: color),
            if (label != null) ...[
              const SizedBox(width: 4),
              Text(label!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color)),
            ],
          ]),
        ),
      );
}

class CommunityCard extends StatelessWidget {
  final Map<String, dynamic> community;
  final VoidCallback onOpen;
  final VoidCallback onJoinLeave;
  final bool joined;
  const CommunityCard({super.key, required this.community, required this.onOpen, required this.onJoinLeave, required this.joined});
  @override
  Widget build(BuildContext context) => ListTile(
        onTap: onOpen,
        title: Text(community['name'] ?? ''),
        subtitle: Text(community['description'] ?? ''),
        trailing: TextButton(onPressed: onJoinLeave, child: Text(joined ? 'Leave' : 'Join')),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message});

  final IconData icon;
  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(message!, textAlign: TextAlign.center),
              ],
            ],
          ),
        ),
      );
}

class ErrorRetryState extends StatelessWidget {
  const ErrorRetryState({super.key, required this.title, required this.message, required this.onRetry});

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off_outlined, size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
            ],
          ),
        ),
      );
}

class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.height = 16, this.width = double.infinity});

  final double height;
  final double width;

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(8),
        ),
      );
}

class FeedSkeletonList extends StatelessWidget {
  const FeedSkeletonList({super.key, this.itemCount = 5});

  final int itemCount;

  @override
  Widget build(BuildContext context) => ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: itemCount,
        itemBuilder: (context, index) => const Card(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 120),
                SizedBox(height: 10),
                SkeletonBox(height: 14),
                SizedBox(height: 8),
                SkeletonBox(height: 14, width: 220),
                SizedBox(height: 12),
                SkeletonBox(height: 180),
                SizedBox(height: 12),
                SkeletonBox(height: 24, width: 180),
              ],
            ),
          ),
        ),
      );
}
