import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';

class ProfileAvatar extends StatelessWidget {
  final String? url;
  const ProfileAvatar({super.key, this.url});
  @override
  Widget build(BuildContext context) => CircleAvatar(backgroundImage: (url != null && url!.isNotEmpty) ? CachedNetworkImageProvider(url!) : null, child: url == null ? const Icon(Icons.person) : null);
}

class PostCard extends StatelessWidget {
  final PostModel post;
  final VoidCallback onLike;
  final VoidCallback onBookmark;
  final VoidCallback onComment;
  final bool liked;
  final bool bookmarked;
  const PostCard({super.key, required this.post, required this.onLike, required this.onBookmark, required this.onComment, this.liked = false, this.bookmarked = false});
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(post.authorUsername ?? 'Unknown', style: Theme.of(context).textTheme.titleMedium),
            if (post.textContent.isNotEmpty) Text(post.textContent),
            if (post.displayImageUrl != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: post.displayImageUrl!,
                    cacheKey: post.imageCacheKey,
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    memCacheWidth: 1080,
                    fadeInDuration: const Duration(milliseconds: 120),
                    placeholder: (context, url) => const SkeletonBox(height: 180),
                    errorWidget: (context, url, error) => const SizedBox(
                      height: 180,
                      child: Center(child: Icon(Icons.broken_image_outlined)),
                    ),
                  ),
                ),
              ),
            Row(children: [
              IconButton(onPressed: onLike, icon: Icon(liked ? Icons.favorite : Icons.favorite_border)),
              Text(post.likeCount.toString()),
              IconButton(onPressed: onComment, icon: const Icon(Icons.comment_outlined)),
              Text(post.commentCount.toString()),
              IconButton(onPressed: onBookmark, icon: Icon(bookmarked ? Icons.bookmark : Icons.bookmark_border)),
            ])
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
