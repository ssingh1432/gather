import 'dart:async';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../core/supabase_client.dart';
import '../../features/data/repositories.dart';
import '../models/models.dart';
import '../services/feed_video_manager.dart';
import '../services/media_download_service.dart';
import '../services/post_view_tracker.dart';
import '../utils/time_ago.dart';
import 'auth_redirects.dart';

/// A crisp 1px bottom border for AppBars. The app's AppBarTheme runs at
/// elevation 0 (flat, no shadow), which reads clean on its own but leaves
/// the top bar with no visible edge against the content below — this
/// gives it a definite, professional separation line instead, the way
/// Instagram/Facebook/X's top bars are hairline-bordered rather than
/// shadowed.
PreferredSizeWidget appBarBottomBorder(BuildContext context) => PreferredSize(
      preferredSize: const Size.fromHeight(1),
      child: Container(height: 1, color: Theme.of(context).dividerColor),
    );

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

  String get _shareUrl => 'https://eiquoab.xyz/post?id=${post.id}';

  String get _shareText => post.textContent.isNotEmpty ? post.textContent : 'Check out this post on Gather';

  Future<void> _launchShare(BuildContext context, Uri uri, {String target = 'external'}) async {
    final uid = SupabaseConfig.currentUserId;
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't open that app. It may not be installed.")),
      );
      return;
    }
    if (uid != null) await FeedRepository().sharePost(post.id, uid, target: target);
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
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Align(alignment: Alignment.centerLeft, child: Text('Share to', style: TextStyle(fontWeight: FontWeight.w600))),
            ),
            SizedBox(
              height: 92,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _ShareAppButton(
                    label: 'WhatsApp',
                    icon: FontAwesomeIcons.whatsapp,
                    color: const Color(0xFF25D366),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _launchShare(context, Uri.parse('https://wa.me/?text=${Uri.encodeComponent('$_shareText\n\n$_shareUrl')}'));
                    },
                  ),
                  _ShareAppButton(
                    label: 'Facebook',
                    icon: FontAwesomeIcons.facebook,
                    color: const Color(0xFF1877F2),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _launchShare(context, Uri.parse('https://www.facebook.com/sharer/sharer.php?u=${Uri.encodeComponent(_shareUrl)}'));
                    },
                  ),
                  _ShareAppButton(
                    label: 'X',
                    icon: FontAwesomeIcons.xTwitter,
                    color: Theme.of(sheetContext).colorScheme.onSurface,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _launchShare(context, Uri.parse('https://twitter.com/intent/tweet?text=${Uri.encodeComponent(_shareText)}&url=${Uri.encodeComponent(_shareUrl)}'));
                    },
                  ),
                  _ShareAppButton(
                    label: 'Telegram',
                    icon: FontAwesomeIcons.telegram,
                    color: const Color(0xFF26A5E4),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _launchShare(context, Uri.parse('https://t.me/share/url?url=${Uri.encodeComponent(_shareUrl)}&text=${Uri.encodeComponent(_shareText)}'));
                    },
                  ),
                  _ShareAppButton(
                    label: 'TikTok',
                    icon: FontAwesomeIcons.tiktok,
                    color: Theme.of(sheetContext).colorScheme.onSurface,
                    // TikTok has no public web-share intent for arbitrary links, so this
                    // just opens the app (if installed) — the link is already on the
                    // clipboard so it's a one-paste share into a TikTok post/bio/DM.
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await Clipboard.setData(ClipboardData(text: _shareUrl));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Link copied — opening TikTok to paste it in.')),
                        );
                      }
                      final opened = await launchUrl(Uri.parse('tiktok://'), mode: LaunchMode.externalApplication);
                      if (!opened) {
                        await launchUrl(Uri.parse('https://www.tiktok.com/'), mode: LaunchMode.externalApplication);
                      }
                      await FeedRepository().sharePost(post.id, uid, target: 'external');
                    },
                  ),
                  _ShareAppButton(
                    label: 'Mail',
                    icon: FontAwesomeIcons.envelope,
                    color: Theme.of(sheetContext).colorScheme.secondary,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _launchShare(
                        context,
                        Uri(scheme: 'mailto', queryParameters: {'subject': 'Check this out on Gather', 'body': '$_shareText\n\n$_shareUrl'}),
                      );
                    },
                  ),
                  _ShareAppButton(
                    label: 'Copy link',
                    icon: FontAwesomeIcons.link,
                    color: Theme.of(sheetContext).colorScheme.outline,
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await Clipboard.setData(ClipboardData(text: _shareUrl));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied.')));
                      }
                      await FeedRepository().sharePost(post.id, uid, target: 'external');
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 20),
            ListTile(
              leading: const Icon(Icons.more_horiz),
              title: const Text('More apps'),
              subtitle: const Text('Everything else installed on your device'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await Share.share('$_shareText\n\n$_shareUrl');
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
      builder: (sheetContext) => _PeopleSheet(
        title: 'Liked by ${post.likeCount}',
        fetcher: () => FeedRepository().likersOf(post.id),
        emptyLabel: 'No likes yet',
        emptyIcon: Icons.favorite_border,
      ),
    );
  }

  void _openSharersSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => _PeopleSheet(
        title: 'Shared by ${post.shareCount}',
        fetcher: () => FeedRepository().sharersOf(post.id),
        emptyLabel: 'No shares yet',
        emptyIcon: Icons.repeat,
      ),
    );
  }

  void _openDownloadersSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => _PeopleSheet(
        title: 'Downloaded by ${post.downloadCount}',
        fetcher: () => FeedRepository().downloadersOf(post.id),
        emptyLabel: 'No downloads yet',
        emptyIcon: Icons.download_outlined,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor, width: 8)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: _PostHeader(post: post, onTapAuthor: () => _openAuthorProfile(context), onTapMore: () => _openOverflowMenu(context)),
          ),
          if ((post.location != null && post.location!.isNotEmpty) ||
              (post.feeling != null && post.feeling!.isNotEmpty) ||
              post.mentionedUsernames.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: _FeelingLocationLine(post: post),
            ),
          if (post.textContent.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Text(post.textContent),
            ),
          if (post.tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: _TagChips(tags: post.tags),
            ),
          if (post.linkPreviewUrl != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: _FeedLinkPreview(post: post),
            ),
          if (post.replyTo != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: _QuotedPostCard(quoted: post.replyTo!),
            ),
          // Media is deliberately outside any horizontal padding — full
          // device width, flush left and right, no rounded corners.
          // Facebook-style, not a card-inset thumbnail.
          if (post.displayImageUrl != null || post.isVideo)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: post.isSensitive
                  ? _SensitiveContentGate(child: _PostMedia(post: post, liked: liked, onLike: onLike))
                  : _PostMedia(post: post, liked: liked, onLike: onLike),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: _PostActionBar(
              post: post,
              liked: liked,
              bookmarked: bookmarked,
              onLike: onLike,
              onComment: onComment,
              onBookmark: onBookmark,
              onShare: () => _openShareSheet(context),
              onShowLikers: () => _openLikersSheet(context),
              onShowSharers: () => _openSharersSheet(context),
              onShowDownloaders: () => _openDownloadersSheet(context),
            ),
          ),
        ]),
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
/// Blurs whatever [child] is (media, in practice) behind a "Sensitive
/// content" notice until tapped — the same tap-to-reveal contract as
/// Twitter/X's content warnings. Safe search filters these posts out of
/// the feed entirely server-side; this gate is what everyone else sees.
class _SensitiveContentGate extends StatefulWidget {
  const _SensitiveContentGate({required this.child});
  final Widget child;

  @override
  State<_SensitiveContentGate> createState() => _SensitiveContentGateState();
}

class _SensitiveContentGateState extends State<_SensitiveContentGate> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    if (_revealed) return widget.child;
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () => setState(() => _revealed = true),
      child: Stack(
        alignment: Alignment.center,
        children: [
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: IgnorePointer(child: widget.child),
          ),
          Container(color: Colors.black.withValues(alpha: 0.25)),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.white, size: 28),
              const SizedBox(height: 6),
              const Text('Sensitive content', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('Tap to view', style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70)),
            ],
          ),
        ],
      ),
    );
  }
}

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
      final uid = SupabaseConfig.maybeClient?.auth.currentUser?.id;
      if (uid != null) {
        // Best-effort — a missed download log shouldn't block the save
        // the person actually cares about.
        unawaited(SupabaseConfig.client.rpc('log_post_download', params: {'p_post_id': widget.post.id}));
      }
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
    return VisibilityDetector(
      key: ValueKey('post-view-${widget.post.id}'),
      onVisibilityChanged: (info) {
        if (info.visibleFraction > 0.6) PostViewTracker.instance.maybeCount(widget.post.id);
      },
      child: ClipRect(
        child: GestureDetector(
          onTap: () => _openViewer(context),
          onDoubleTap: _handleDoubleTap,
          child: Stack(
            alignment: Alignment.center,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
                child: widget.post.isVideo
                    ? _AutoplayVideo(postId: widget.post.id, url: _mediaUrl)
                    : _AutoAspectImage(post: widget.post),
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
      ),
    );
  }
}

/// Shows the image at its real aspect ratio (letterboxed within a max
/// height, never cropped) instead of force-fitting a fixed 220px box —
/// matches "full screen / as it is originally" rather than Instagram's
/// classic square crop.
class _AutoAspectImage extends StatefulWidget {
  const _AutoAspectImage({required this.post});
  final PostModel post;

  @override
  State<_AutoAspectImage> createState() => _AutoAspectImageState();
}

class _AutoAspectImageState extends State<_AutoAspectImage> {
  double? _aspectRatio;
  ImageStream? _stream;
  String? _resolvedUrl;
  late final ImageStreamListener _listener;

  @override
  void initState() {
    super.initState();
    _listener = ImageStreamListener((info, _) {
      if (!mounted) return;
      final w = info.image.width.toDouble();
      final h = info.image.height.toDouble();
      if (h > 0) setState(() => _aspectRatio = w / h);
    });
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    super.dispose();
  }

  void _resolve(ImageProvider provider) {
    final stream = provider.resolve(const ImageConfiguration());
    if (stream.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _stream = stream..addListener(_listener);
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.post.displayImageUrl;
    if (url == null) return const SizedBox.shrink();
    final provider = CachedNetworkImageProvider(url, cacheKey: widget.post.imageCacheKey);
    if (_resolvedUrl != url) {
      _resolvedUrl = url;
      WidgetsBinding.instance.addPostFrameCallback((_) => _resolve(provider));
    }
    // No clamp here: clamping the box's ratio away from the image's real
    // ratio was exactly what caused tall screenshots to letterbox with
    // gaps on the sides instead of filling the width. SizedBox below
    // forces full width unconditionally; AspectRatio then derives height
    // from the real ratio, so the box always matches the image exactly —
    // full-bleed left and right with nothing cropped, no gaps.
    final ratio = _aspectRatio ?? (4 / 5);
    return SizedBox(
      width: double.infinity,
      child: AspectRatio(
        aspectRatio: ratio,
        child: CachedNetworkImage(
          imageUrl: url,
          cacheKey: widget.post.imageCacheKey,
          // Box now always matches the image's true ratio, so cover and
          // contain are equivalent here — cover avoids any 1px rounding
          // gap at the edges.
          fit: BoxFit.cover,
          memCacheWidth: 1080,
          fadeInDuration: const Duration(milliseconds: 120),
          placeholder: (context, url) => const SkeletonBox(height: 220),
          errorWidget: (context, url, error) => const Center(child: Icon(Icons.broken_image_outlined)),
        ),
      ),
    );
  }
}

/// Autoplays muted, looping, and without sound controls right in the feed
/// — like every short-video feed does — but only while it's the single
/// "most visible" video across the whole scroll (see [FeedVideoManager]).
/// Falls back to a static play-button placeholder otherwise, so only one
/// real `VideoPlayerController` is ever alive at a time.
class _AutoplayVideo extends StatefulWidget {
  const _AutoplayVideo({required this.postId, required this.url});
  final String postId;
  final String url;

  @override
  State<_AutoplayVideo> createState() => _AutoplayVideoState();
}

class _AutoplayVideoState extends State<_AutoplayVideo> {
  VideoPlayerController? _controller;
  bool _initializing = false;
  bool _failed = false;
  // Bumped every time we start a new init attempt so a slow/hung request
  // from a previous scroll position can't clobber state after the user
  // has already scrolled past and a newer request has taken over.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    FeedVideoManager.instance.activePostId.addListener(_onActiveChanged);
  }

  @override
  void dispose() {
    FeedVideoManager.instance.activePostId.removeListener(_onActiveChanged);
    FeedVideoManager.instance.reportDisposed(widget.postId);
    _generation++; // invalidate any in-flight init for this instance
    _controller?.dispose();
    super.dispose();
  }

  bool get _isActive => FeedVideoManager.instance.activePostId.value == widget.postId;

  Future<void> _onActiveChanged() async {
    if (!mounted) return;
    if (_isActive && _controller == null && !_initializing) {
      await _startInit();
    } else if (!_isActive && _controller != null) {
      final c = _controller;
      setState(() => _controller = null);
      await c?.dispose();
    }
  }

  Future<void> _startInit() async {
    _initializing = true;
    _failed = false;
    final myGeneration = ++_generation;
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    try {
      // A hung network request would otherwise freeze this post forever
      // with no feedback — cap it so it fails gracefully instead.
      await c.initialize().timeout(const Duration(seconds: 12));
      await c.setVolume(0); // muted autoplay, same as every app does this
      await c.setLooping(true);
      if (myGeneration != _generation || !mounted || !_isActive) {
        await c.dispose();
      } else {
        await c.play();
        setState(() => _controller = c);
      }
    } catch (_) {
      await c.dispose();
      if (myGeneration == _generation && mounted) setState(() => _failed = true);
    } finally {
      if (myGeneration == _generation) _initializing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: ValueKey('post-video-${widget.postId}'),
      onVisibilityChanged: (info) => FeedVideoManager.instance.reportVisibility(widget.postId, info.visibleFraction),
      child: SizedBox(
        width: double.infinity,
        child: AspectRatio(
          aspectRatio: _controller?.value.isInitialized == true ? _controller!.value.aspectRatio : 4 / 5,
          child: GestureDetector(
            onTap: _failed ? _startInit : null,
            child: Stack(
              alignment: Alignment.center,
              fit: StackFit.expand,
              children: [
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF2B2B2B), Color(0xFF161616)]),
                  ),
                ),
                if (_controller?.value.isInitialized == true)
                  VideoPlayer(_controller!)
                else if (_initializing)
                  const CircularProgressIndicator(color: Colors.white)
                else
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.35), shape: BoxShape.circle),
                        child: Icon(_failed ? Icons.refresh : Icons.play_arrow_rounded, color: Colors.white, size: 40),
                      ),
                      if (_failed) ...[
                        const SizedBox(height: 6),
                        const Text('Tap to retry', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ],
                  ),
                const Positioned(left: 10, bottom: 10, child: _MediaBadge(label: 'VIDEO', icon: Icons.videocam_outlined)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One tappable app icon in the "Share to" row (WhatsApp, Facebook, X,
/// Telegram, TikTok, Mail, Copy link) — a circular brand-colored tile with
/// a label underneath, matching how every major app's native share sheet
/// presents its quick-share row.
class _ShareAppButton extends StatelessWidget {
  const _ShareAppButton({required this.label, required this.icon, required this.color, required this.onTap});
  final String label;
  final FaIconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(radius: 24, backgroundColor: color.withValues(alpha: 0.12), child: FaIcon(icon, color: color, size: 20)),
              const SizedBox(height: 6),
              Text(label, style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
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
class _PeopleSheet extends StatefulWidget {
  const _PeopleSheet({required this.title, required this.fetcher, required this.emptyLabel, required this.emptyIcon});
  final String title;
  final Future<List<RecommendedUser>> Function() fetcher;
  final String emptyLabel;
  final IconData emptyIcon;

  @override
  State<_PeopleSheet> createState() => _PeopleSheetState();
}

class _PeopleSheetState extends State<_PeopleSheet> {
  late Future<List<RecommendedUser>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.fetcher();
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
              child: Text(widget.title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ),
            Expanded(
              child: FutureBuilder<List<RecommendedUser>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return const EmptyState(icon: Icons.error_outline, title: 'Could not load');
                  }
                  final people = snapshot.data ?? const [];
                  if (people.isEmpty) {
                    return EmptyState(icon: widget.emptyIcon, title: widget.emptyLabel);
                  }
                  return ListView.builder(
                    itemCount: people.length,
                    itemBuilder: (context, index) {
                      final user = people[index];
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
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline, fontStyle: FontStyle.italic);
    final linkStyle = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w600);

    final prefixParts = <String>[];
    if (post.feeling != null && post.feeling!.isNotEmpty) prefixParts.add('is feeling ${post.feeling}');
    if (post.location != null && post.location!.isNotEmpty) prefixParts.add('📍 ${post.location}');

    if (prefixParts.isEmpty && post.mentionedUsernames.isEmpty) return const SizedBox.shrink();

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (prefixParts.isNotEmpty) Text(prefixParts.join('  ·  '), style: style),
        if (prefixParts.isNotEmpty && post.mentionedUsernames.isNotEmpty) Text('  ·  ', style: style),
        if (post.mentionedUsernames.isNotEmpty) ...[
          Text('with ', style: style),
          for (var i = 0; i < post.mentionedUsernames.length; i++) ...[
            InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () {
                final id = i < post.mentionedUserIds.length ? post.mentionedUserIds[i] : null;
                if (id != null && id.isNotEmpty) context.push('/user?id=$id');
              },
              child: Text('@${post.mentionedUsernames[i]}', style: linkStyle),
            ),
            if (i != post.mentionedUsernames.length - 1) Text(', ', style: style),
          ],
        ],
      ],
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

class _FeedLinkPreview extends StatelessWidget {
  const _FeedLinkPreview({required this.post});
  final PostModel post;

  @override
  Widget build(BuildContext context) {
    final url = post.linkPreviewUrl;
    if (url == null) return const SizedBox.shrink();
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (post.linkPreviewImageUrl != null && post.linkPreviewImageUrl!.isNotEmpty)
              SizedBox(
                width: 84,
                height: 84,
                child: CachedNetworkImage(
                  imageUrl: post.linkPreviewImageUrl!,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (post.linkPreviewSiteName != null)
                      Text(
                        post.linkPreviewSiteName!.toUpperCase(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.outline),
                      ),
                    if (post.linkPreviewTitle != null)
                      Text(post.linkPreviewTitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (post.linkPreviewDescription != null)
                      Text(post.linkPreviewDescription!, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ),
            const Padding(padding: EdgeInsets.only(right: 8), child: Icon(Icons.open_in_new, size: 16)),
          ],
        ),
      ),
    );
  }
}
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
  final VoidCallback onShowSharers;
  final VoidCallback onShowDownloaders;

  const _PostActionBar({
    required this.post,
    required this.liked,
    required this.bookmarked,
    required this.onLike,
    required this.onComment,
    required this.onBookmark,
    required this.onShare,
    required this.onShowLikers,
    required this.onShowSharers,
    required this.onShowDownloaders,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        _CountedAction(
          icon: liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          iconColor: liked ? Colors.redAccent : null,
          count: post.likeCount,
          onTapIcon: onLike,
          onTapCount: onShowLikers,
        ),
        const SizedBox(width: 16),
        _CountedAction(
          icon: Icons.chat_bubble_outline_rounded,
          count: post.commentCount,
          onTapIcon: onComment,
          onTapCount: onComment,
        ),
        if (post.replyCount > 0) ...[
          const SizedBox(width: 16),
          _CountedAction(
            icon: Icons.forum_outlined,
            count: post.replyCount,
            onTapIcon: () => context.push('/post/replies?id=${post.id}'),
            onTapCount: () => context.push('/post/replies?id=${post.id}'),
          ),
        ],
        const SizedBox(width: 16),
        _CountedAction(
          icon: Icons.send_outlined,
          count: post.shareCount,
          onTapIcon: onShare,
          onTapCount: onShowSharers,
        ),
        if (post.downloadCount > 0) ...[
          const SizedBox(width: 16),
          _CountedAction(
            icon: Icons.file_download_outlined,
            count: post.downloadCount,
            onTapIcon: onShowDownloaders,
            onTapCount: onShowDownloaders,
          ),
        ],
        const Spacer(),
        IconButton(
          onPressed: onBookmark,
          icon: Icon(bookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, color: bookmarked ? theme.colorScheme.primary : null),
          tooltip: 'Save',
        ),
      ]),
      if (post.viewCount > 0)
        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 2),
          child: Text(
            '${post.viewCount} ${post.viewCount == 1 ? 'view' : 'views'}',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
          ),
        ),
    ]);
  }
}

/// A single feed action rendered as icon + count as one visual unit —
/// tapping the icon performs the action (like/comment/share), tapping the
/// count opens the "who liked/shared" list where that applies. Replaces
/// the old ad-hoc mix of separately-padded InkWells with inconsistent
/// 4px gaps between them.
class _CountedAction extends StatelessWidget {
  const _CountedAction({required this.icon, required this.count, required this.onTapIcon, required this.onTapCount, this.iconColor});
  final IconData icon;
  final int count;
  final Color? iconColor;
  final VoidCallback onTapIcon;
  final VoidCallback onTapCount;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTapIcon,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Icon(icon, size: 21, color: iconColor),
            ),
          ),
          if (count > 0)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onTapCount,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                child: Text('$count', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500)),
              ),
            ),
        ],
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
