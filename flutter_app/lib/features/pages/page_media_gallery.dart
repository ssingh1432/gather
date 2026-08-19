import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

/// Page-local media rendering shared by owner Page posts and Page visitor
/// posts. Deliberately separate from the normal Gather media stack so this
/// stays a Page-only change.
///
/// Root cause of the "Image unavailable" bug: on Flutter Web, the default
/// `Image.network` decode path (CanvasKit/Skwasm) requires a CORS-eligible
/// byte fetch to read pixel data. Supabase Storage's public-bucket response
/// displays fine as a plain HTML `<img>` (browsers don't gate that on CORS)
/// but fails canvas decode, so a perfectly valid public URL still hits
/// `errorBuilder`. Using `WebHtmlElementStrategy.prefer` on web renders the
/// image as a native HTML element instead, sidestepping the canvas decode
/// requirement entirely. Native platforms are unaffected and keep the
/// normal decode path.
class PageNetworkImage extends StatelessWidget {
  const PageNetworkImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.errorWidget,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  /// Custom fallback (e.g. a small avatar icon). Defaults to a
  /// "broken image" box sized for full-width media.
  final WidgetBuilder? errorWidget;

  @override
  Widget build(BuildContext context) {
    Widget fallback() {
      if (errorWidget != null) return errorWidget!(context);
      return Container(
        width: width,
        height: height,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 4),
            Text('Image unavailable', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
    }

    if (url.trim().isEmpty) return fallback();

    final image = Image.network(
      url,
      width: width,
      height: height,
      fit: fit,
      webHtmlElementStrategy: kIsWeb ? WebHtmlElementStrategy.prefer : WebHtmlElementStrategy.never,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return SizedBox(
          width: width,
          height: height,
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      },
      errorBuilder: (_, __, ___) => fallback(),
    );

    if (borderRadius == null) return image;
    return ClipRRect(borderRadius: borderRadius!, child: image);
  }
}

/// Minimal tap-to-play inline video widget for Page media. Kept intentionally
/// simple (no autoplay/feed management) since Page posts aren't rendered in
/// an infinite-scroll feed context the way normal Home posts are.
class PageInlineVideo extends StatefulWidget {
  const PageInlineVideo({super.key, required this.url, this.height = 220});

  final String url;
  final double height;

  @override
  State<PageInlineVideo> createState() => _PageInlineVideoState();
}

class _PageInlineVideoState extends State<PageInlineVideo> {
  VideoPlayerController? _controller;
  bool _initializing = false;
  bool _failed = false;
  bool _playing = false;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_controller != null || _initializing) return;
    setState(() => _initializing = true);
    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await controller.initialize();
      controller.setVolume(0);
      await controller.play();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _initializing = false;
        _playing = true;
      });
    } catch (_) {
      if (mounted) setState(() { _initializing = false; _failed = true; });
    }
  }

  void _togglePlay() {
    final c = _controller;
    if (c == null) return;
    setState(() {
      if (c.value.isPlaying) {
        c.pause();
        _playing = false;
      } else {
        c.play();
        _playing = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Container(
        height: widget.height,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off_outlined, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 4),
            Text('Video unavailable', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
    }

    final controller = _controller;
    if (controller == null) {
      return SizedBox(
        height: widget.height,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(color: Colors.black.withValues(alpha: 0.06)),
            _initializing
                ? const CircularProgressIndicator(strokeWidth: 2)
                : IconButton.filled(
                    iconSize: 36,
                    onPressed: _start,
                    icon: const Icon(Icons.play_arrow),
                  ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: _togglePlay,
      child: SizedBox(
        height: widget.height,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: controller.value.aspectRatio == 0 ? 16 / 9 : controller.value.aspectRatio,
                child: VideoPlayer(controller),
              ),
            ),
            if (!_playing) const Icon(Icons.play_arrow, size: 42, color: Colors.white70),
          ],
        ),
      ),
    );
  }
}

/// Renders a Page post's `media` array (image / video / document) in a
/// consistent, type-correct way. Used by both owner Page posts and Page
/// visitor posts.
class PageMediaAttachmentList extends StatelessWidget {
  const PageMediaAttachmentList({super.key, required this.items});

  final List<Map<String, dynamic>> items;

  Future<void> _openAttachment(BuildContext context, String url) async {
    if (url.trim().isEmpty) return;
    final launched = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open this attachment.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (final item in items)
            if (item['type'] == 'image')
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: PageNetworkImage(
                  url: item['url']?.toString() ?? '',
                  width: double.infinity,
                  height: 260,
                ),
              )
            else if (item['type'] == 'video')
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: PageInlineVideo(url: item['url']?.toString() ?? ''),
              )
            else if (item['type'] != 'event')
              InkWell(
                onTap: () => _openAttachment(context, item['url']?.toString() ?? ''),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.insert_drive_file_outlined),
                      const SizedBox(width: 8),
                      Expanded(child: Text(item['name']?.toString() ?? 'Attachment')),
                      const Icon(Icons.open_in_new, size: 18),
                    ],
                  ),
                ),
              ),
        ],
      );
}

/// Renders an event attachment (either a Page-owned `page_events` row for
/// visitor posts, or the inline event snapshot stored on owner post media).
class PageEventAttachmentCard extends StatelessWidget {
  const PageEventAttachmentCard({super.key, required this.event});

  final Map<String, dynamic> event;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.event_outlined),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event['title']?.toString() ?? 'Event',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (event['start_time'] != null)
                    Text(
                      DateTime.parse(event['start_time'] as String).toLocal().toString(),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (event['location'] != null)
                    Text(event['location'].toString(), style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      );
}
