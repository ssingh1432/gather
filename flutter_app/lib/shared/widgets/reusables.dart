import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/supabase_client.dart';
import '../../features/data/repositories.dart';
import '../models/models.dart';
import '../services/media_download_service.dart';
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

  void _openLikersSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => _LikersSheet(postId: post.id, likeCount: post.likeCount),
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
            if (post.displayImageUrl != null || post.isVideo)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: _PostMedia(post: post, liked: liked, onLike: onLike),
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
              onShowLikers: () => _openLikersSheet(context),
            ),
          ]),
        ),
      );
}


/// The media block of a post: image or video preview, wrapped so that:
/// - a single tap opens the full-screen [MediaViewerScreen]
/// - a double tap likes the post (Instagram-style) with a heart pop
///   animation, without ever un-liking on a repeat double tap
/// - a small download button in the corner saves the media directly from
///   the feed, without needing to open the viewer first
///
/// Videos are NOT given a live `VideoPlayerController` here — running one
/// controller per visible video in a scrolling list is a real memory/perf
/// risk, so the feed shows a lightweight static placeholder and only pays
/// for video playback once the person actually opens the full viewer.
class _PostMedia extends StatefulWidget {
  const _PostMedia({required this.post, required this.liked, required this.onLike});
  final PostModel post;
  final bool liked;
  final VoidCallback onLike;

  @override
  State<_PostMedia> createState() => _PostMediaState();
}

class _PostMediaState extends State<_PostMedia> with SingleTickerProviderStateMixin {
  late final AnimationController _heartController;
  late final Animation<double> _heartScale;
  bool _showHeart = false;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _heartController = AnimationController(vsync: this, duration: const Duration(milliseconds: 550));
    _heartScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.2).chain(CurveTween(curve: Curves.easeOutBack)), weight: 55),
      TweenSequenceItem(tween: Tween(begin: 1.2, end: 1.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeIn)), weight: 10),
    ]).animate(_heartController);
  }

  @override
  void dispose() {
    _heartController.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    setState(() => _showHeart = true);
    _heartController.forward(from: 0).whenComplete(() {
      if (mounted) setState(() => _showHeart = false);
    });
    if (!widget.liked) widget.onLike();
  }

  String get _mediaUrl => widget.post.imageUrl ?? widget.post.displayImageUrl ?? '';

  void _openViewer(BuildContext context) {
    if (_mediaUrl.isEmpty) return;
    final type = widget.post.isVideo ? 'video' : 'image';
    context.push('/media?url=${Uri.encodeComponent(_mediaUrl)}&type=$type');
  }

  Future<void> _download(BuildContext context) async {
    if (_downloading || _mediaUrl.isEmpty) return;
    setState(() => _downloading = true);
    try {
      await saveMediaToDevice(url: _mediaUrl, isVideo: widget.post.isVideo);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(widget.post.isVideo ? 'Video saved.' : 'Photo saved.')));
      }
    } on MediaDownloadException catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save media. Please try again.')));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: GestureDetector(
        onTap: () => _openViewer(context),
        onDoubleTap: _handleDoubleTap,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              height: 220,
              width: double.infinity,
              child: widget.post.isVideo ? const _VideoPlaceholder() : _ImageThumbnail(post: widget.post),
            ),
            IgnorePointer(
              child: AnimatedOpacity(
                opacity: _showHeart ? 1 : 0,
                duration: const Duration(milliseconds: 150),
                child: ScaleTransition(
                  scale: _heartScale,
                  child: const Icon(Icons.favorite, color: Colors.white, size: 84, shadows: [Shadow(blurRadius: 12, color: Colors.black45)]),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: _MediaIconButton(
                icon: _downloading ? null : Icons.download_outlined,
                loading: _downloading,
                onTap: () => _download(context),
                tooltip: 'Download',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageThumbnail extends StatelessWidget {
  const _ImageThumbnail({required this.post});
  final PostModel post;

  @override
  Widget build(BuildContext context) {
    final url = post.displayImageUrl;
    if (url == null) return const SizedBox.shrink();
    return CachedNetworkImage(
      imageUrl: url,
      cacheKey: post.imageCacheKey,
      fit: BoxFit.cover,
      memCacheWidth: 1080,
      fadeInDuration: const Duration(milliseconds: 120),
      placeholder: (context, url) => const SkeletonBox(height: 220),
      errorWidget: (context, url, error) => const Center(child: Icon(Icons.broken_image_outlined)),
    );
  }
}

class _VideoPlaceholder extends StatelessWidget {
  const _VideoPlaceholder();

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF2B2B2B), Color(0xFF161616)]),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.35), shape: BoxShape.circle),
              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 40),
            ),
            const Positioned(
              left: 10,
              bottom: 10,
              child: _MediaBadge(label: 'VIDEO', icon: Icons.videocam_outlined),
            ),
          ],
        ),
      );
}

class _MediaBadge extends StatelessWidget {
  const _MediaBadge({required this.label, required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(6)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
        ]),
      );
}

class _MediaIconButton extends StatelessWidget {
  const _MediaIconButton({required this.onTap, this.icon, this.loading = false, this.tooltip});
  final VoidCallback onTap;
  final IconData? icon;
  final bool loading;
  final String? tooltip;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.black.withValues(alpha: 0.45),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: loading
                ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Icon(icon, size: 18, color: Colors.white),
          ),
        ),
      );
}

/// Bottom sheet listing the people who liked a post.
class _LikersSheet extends StatefulWidget {
  const _LikersSheet({required this.postId, required this.likeCount});
  final String postId;
  final int likeCount;

  @override
  State<_LikersSheet> createState() => _LikersSheetState();
}

class _LikersSheetState extends State<_LikersSheet> {
  late Future<List<RecommendedUser>> _future;

  @override
  void initState() {
    super.initState();
    _future = FeedRepository().likersOf(widget.postId);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text('Liked by ${widget.likeCount}', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ),
            Expanded(
              child: FutureBuilder<List<RecommendedUser>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return const EmptyState(icon: Icons.error_outline, title: 'Could not load likes');
                  }
                  final likers = snapshot.data ?? const [];
                  if (likers.isEmpty) {
                    return const EmptyState(icon: Icons.favorite_border, title: 'No likes yet');
                  }
                  return ListView.builder(
                    itemCount: likers.length,
                    itemBuilder: (context, index) {
                      final user = likers[index];
                      return ListTile(
                        leading: ProfileAvatar(url: user.avatarUrl, radius: 20),
                        title: Text(user.username),
                        onTap: () {
                          Navigator.pop(context);
                          context.push('/user?id=${user.id}');
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
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
  final VoidCallback onShowLikers;

  const _PostActionBar({
    required this.post,
    required this.liked,
    required this.bookmarked,
    required this.onLike,
    required this.onComment,
    required this.onBookmark,
    required this.onShare,
    required this.onShowLikers,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(children: [
      InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onLike,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Icon(liked ? Icons.favorite : Icons.favorite_border, size: 20, color: liked ? Colors.redAccent : null),
        ),
      ),
      if (post.likeCount > 0)
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onShowLikers,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Text('${post.likeCount}', style: theme.textTheme.bodySmall),
          ),
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
