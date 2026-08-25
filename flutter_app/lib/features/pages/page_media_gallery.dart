import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import '../../core/supabase_client.dart';

class PageMediaUrlResolver {
  static const _buckets = {'page-media', 'page-visitor-media'};

  static Future<String> resolve(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return url;
    final segments = uri.pathSegments;
    final objectIndex = segments.indexOf('object');
    if (objectIndex < 0 || objectIndex + 2 >= segments.length) return url;
    final mode = segments[objectIndex + 1];
    final bucket = segments[objectIndex + 2];
    if ((mode != 'public' && mode != 'authenticated') || !_buckets.contains(bucket)) return url;
    final path = segments.sublist(objectIndex + 3).join('/');
    if (path.isEmpty) return url;
    try {
      return await SupabaseConfig.client.storage.from(bucket).createSignedUrl(path, 3600);
    } catch (_) {
      return url;
    }
  }
}

Future<void> showPageMediaViewer(
  BuildContext context,
  List<Map<String, dynamic>> items, {
  int initialIndex = 0,
}) async {
  final visible = items.where((item) => item['type'] != 'event').toList();
  if (visible.isEmpty || !context.mounted) return;
  final safeIndex = initialIndex.clamp(0, visible.length - 1).toInt();
  await Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _PageMediaViewer(items: visible, initialIndex: safeIndex),
    ),
  );
}

class PageNetworkImage extends StatefulWidget {
  const PageNetworkImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.borderRadius,
    this.errorWidget,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final WidgetBuilder? errorWidget;

  @override
  State<PageNetworkImage> createState() => _PageNetworkImageState();
}

class _PageNetworkImageState extends State<PageNetworkImage> {
  String? _resolvedUrl;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant PageNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _resolve();
  }

  Future<void> _resolve() async {
    final url = await PageMediaUrlResolver.resolve(widget.url);
    if (mounted) setState(() => _resolvedUrl = url);
  }

  @override
  Widget build(BuildContext context) {
    Widget fallback() {
      return widget.errorWidget?.call(context) ?? Container(
        width: widget.width,
        height: widget.height,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: const Icon(Icons.broken_image_outlined),
      );
    }

    if (widget.url.trim().isEmpty) return fallback();
    final url = _resolvedUrl;
    if (url == null) {
      return SizedBox(
        width: widget.width,
        height: widget.height ?? 240,
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final image = Image.network(
      url,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      webHtmlElementStrategy: kIsWeb
          ? WebHtmlElementStrategy.prefer
          : WebHtmlElementStrategy.never,
      errorBuilder: (_, __, ___) => fallback(),
    );

    return widget.borderRadius == null
        ? image
        : ClipRRect(borderRadius: widget.borderRadius!, child: image);
  }
}

class PageInlineVideo extends StatefulWidget {
  const PageInlineVideo({super.key, required this.url, this.height = 220});

  final String url;
  final double height;

  @override
  State<PageInlineVideo> createState() => _PageInlineVideoState();
}

class _PageInlineVideoState extends State<PageInlineVideo> {
  VideoPlayerController? _controller;
  String? _resolvedUrl;
  bool _loading = false;
  bool _error = false;
  bool _muted = true;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void dispose() {
    _controller?.removeListener(_handleVideoState);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _resolve() async {
    final url = await PageMediaUrlResolver.resolve(widget.url);
    if (mounted) setState(() => _resolvedUrl = url);
  }

  Future<void> _initialize() async {
    if (_loading || _error || _resolvedUrl == null) return;
    setState(() => _loading = true);
    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(_resolvedUrl!));
      await controller.initialize();
      await controller.setVolume(0);
      controller.addListener(_handleVideoState);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  Future<void> _play() async {
    final controller = _controller;
    if (controller == null) return;
    if (_completed || controller.value.position >= controller.value.duration) {
      await controller.seekTo(Duration.zero);
      _completed = false;
    }
    await controller.play();
    if (mounted) setState(() {});
  }

  Future<void> _togglePlay() async {
    final controller = _controller;
    if (controller == null) {
      await _initialize();
      if (_controller != null) await _play();
      return;
    }
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await _play();
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggleMute() async {
    final controller = _controller;
    if (controller == null) return;
    _muted = !_muted;
    await controller.setVolume(_muted ? 0 : 1);
    if (mounted) setState(() {});
  }

  void _handleVideoState() {
    final controller = _controller;
    if (controller == null || !mounted) return;
    final value = controller.value;
    if (value.isInitialized &&
        value.duration > Duration.zero &&
        value.position >= value.duration &&
        !_completed) {
      _completed = true;
      controller.pause();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_error) {
      return _MediaError(height: widget.height, label: 'Video unavailable');
    }

    final controller = _controller;
    if (controller == null) {
      return SizedBox(
        height: widget.height,
        child: Center(
          child: _loading || _resolvedUrl == null
              ? const CircularProgressIndicator(strokeWidth: 2)
              : IconButton.filled(
                  onPressed: _initialize,
                  icon: const Icon(Icons.play_arrow),
                  iconSize: 34,
                ),
        ),
      );
    }

    final aspectRatio = controller.value.aspectRatio == 0
        ? 16 / 9
        : controller.value.aspectRatio.clamp(.5625, 1.7778);

    return SizedBox(
      height: widget.height,
      child: Center(
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: Stack(
            alignment: Alignment.center,
            children: [
              VideoPlayer(controller),
              if (!controller.value.isPlaying || _completed)
                IconButton.filled(
                  onPressed: _togglePlay,
                  icon: Icon(_completed ? Icons.replay : Icons.play_arrow),
                  iconSize: 32,
                ),
              Positioned(
                right: 8,
                bottom: 8,
                child: _VideoMuteButton(
                  muted: _muted,
                  onPressed: _toggleMute,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PageMediaGallery extends StatelessWidget {
  const PageMediaGallery({super.key, required this.items, this.onOpen});

  final List<Map<String, dynamic>> items;
  final ValueChanged<int>? onOpen;

  @override
  Widget build(BuildContext context) {
    final media = items.where((item) => item['type'] != 'event').toList();
    if (media.isEmpty) return const SizedBox.shrink();

    void openGallery() {
      if (onOpen != null) {
        onOpen!(0);
      } else {
        showPageMediaViewer(context, media, initialIndex: 0);
      }
    }

    Widget tile(Map<String, dynamic> item, double height) {
      return _MediaTile(item: item, height: height, onOpen: openGallery);
    }

    if (media.length == 1) {
      return _SingleMediaTile(item: media.first, onOpen: openGallery);
    }

    if (media.length == 2) {
      return SizedBox(
        height: 240,
        child: Row(
          children: [
            Expanded(child: tile(media[0], 240)),
            const SizedBox(width: 3),
            Expanded(child: tile(media[1], 240)),
          ],
        ),
      );
    }

    if (media.length == 3) {
      return SizedBox(
        height: 300,
        child: Row(
          children: [
            Expanded(flex: 2, child: tile(media[0], 300)),
            const SizedBox(width: 3),
            Expanded(
              child: Column(
                children: [
                  Expanded(child: tile(media[1], 148)),
                  const SizedBox(height: 3),
                  Expanded(child: tile(media[2], 149)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final more = media.length - 4;
    return SizedBox(
      height: 300,
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 4,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 3,
          mainAxisSpacing: 3,
        ),
        itemBuilder: (_, index) {
          return Stack(
            children: [
              Positioned.fill(child: tile(media[index], 148)),
              if (index == 3 && more > 0)
                Positioned.fill(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: openGallery,
                      child: Container(
                        color: Colors.black54,
                        alignment: Alignment.center,
                        child: Text(
                          '+$more more',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SingleMediaTile extends StatelessWidget {
  const _SingleMediaTile({required this.item, required this.onOpen});

  final Map<String, dynamic> item;
  final VoidCallback onOpen;

  Future<void> _download(BuildContext context) async {
    final raw = item['url']?.toString() ?? '';
    if (raw.isEmpty) return;
    final url = await PageMediaUrlResolver.resolve(raw);
    if (!context.mounted) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final type = item['type']?.toString() ?? 'document';
    final url = item['url']?.toString() ?? '';

    if (type == 'video') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: onOpen,
                child: PageInlineVideo(url: url, height: 300),
              ),
            ),
            Positioned(
              right: 10,
              top: 10,
              child: _DownloadButton(onPressed: () => _download(context)),
            ),
          ],
        ),
      );
    }

    final media = type == 'image' || type == 'gif'
        ? PageNetworkImage(url: url, width: double.infinity, fit: BoxFit.contain)
        : _DocumentTile(name: item['name']?.toString() ?? 'Attachment');

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: GestureDetector(
        onTap: onOpen,
        child: Stack(
          children: [
            Positioned.fill(child: media),
            Positioned(
              right: 10,
              top: 10,
              child: _DownloadButton(onPressed: () => _download(context)),
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaTile extends StatelessWidget {
  const _MediaTile({required this.item, required this.height, required this.onOpen});

  final Map<String, dynamic> item;
  final double height;
  final VoidCallback onOpen;

  Future<void> _download(BuildContext context) async {
    final raw = item['url']?.toString() ?? '';
    if (raw.isEmpty) return;
    final url = await PageMediaUrlResolver.resolve(raw);
    if (!context.mounted) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final type = item['type']?.toString() ?? 'document';
    final url = item['url']?.toString() ?? '';

    if (type == 'video') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: onOpen,
                child: PageInlineVideo(url: url, height: height),
              ),
            ),
            Positioned(
              right: 8,
              top: 8,
              child: _DownloadButton(onPressed: () => _download(context)),
            ),
          ],
        ),
      );
    }

    final media = type == 'image' || type == 'gif'
        ? PageNetworkImage(
            url: url,
            width: double.infinity,
            height: height,
            fit: BoxFit.cover,
          )
        : _DocumentTile(name: item['name']?.toString() ?? 'Attachment');

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: GestureDetector(
        onTap: onOpen,
        child: Stack(
          children: [
            Positioned.fill(child: media),
            Positioned(
              right: 8,
              top: 8,
              child: _DownloadButton(onPressed: () => _download(context)),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.description_outlined, size: 42),
          const SizedBox(height: 8),
          Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _VideoMuteButton extends StatelessWidget {
  const _VideoMuteButton({required this.muted, required this.onPressed});

  final bool muted;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: muted ? 'Unmute' : 'Mute',
        onPressed: onPressed,
        icon: Icon(muted ? Icons.volume_off : Icons.volume_up, color: Colors.white),
      ),
    );
  }
}

class _DownloadButton extends StatelessWidget {
  const _DownloadButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Download',
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: const Padding(
          padding: EdgeInsets.all(5),
          child: Icon(Icons.download, color: Colors.white, size: 15),
        ),
      ),
    );
  }
}

class PageMediaAttachmentList extends StatelessWidget {
  const PageMediaAttachmentList({super.key, required this.items});

  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) => PageMediaGallery(items: items);
}

class PageEventAttachmentCard extends StatelessWidget {
  const PageEventAttachmentCard({super.key, required this.event});

  final Map<String, dynamic> event;

  @override
  Widget build(BuildContext context) {
    return Container(
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
                  Text(
                    event['location'].toString(),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PageMediaViewer extends StatefulWidget {
  const _PageMediaViewer({required this.items, required this.initialIndex});

  final List<Map<String, dynamic>> items;
  final int initialIndex;

  @override
  State<_PageMediaViewer> createState() => _PageMediaViewerState();
}

class _PageMediaViewerState extends State<_PageMediaViewer> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.items.length - 1).toInt();
    _controller = PageController(initialPage: _index);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _controller.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.items[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${_index + 1} / ${widget.items.length}',
          style: const TextStyle(fontSize: 15),
        ),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.items.length,
        onPageChanged: (index) => setState(() => _index = index),
        itemBuilder: (_, index) => _ViewerItem(item: widget.items[index]),
      ),
      floatingActionButton: _ViewerOpen(item: item),
    );
  }
}

class _ViewerOpen extends StatelessWidget {
  const _ViewerOpen({required this.item});

  final Map<String, dynamic> item;

  Future<void> _open(BuildContext context) async {
    final raw = item['url']?.toString() ?? '';
    if (raw.isEmpty) return;
    final url = await PageMediaUrlResolver.resolve(raw);
    if (context.mounted) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = item['type']?.toString() ?? 'document';
    if (type == 'image' || type == 'gif' || type == 'video') {
      return const SizedBox.shrink();
    }
    return FloatingActionButton.extended(
      onPressed: () => _open(context),
      icon: const Icon(Icons.open_in_new),
      label: const Text('Open file'),
    );
  }
}

class _ViewerItem extends StatelessWidget {
  const _ViewerItem({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final type = item['type']?.toString() ?? 'document';
    final url = item['url']?.toString() ?? '';
    if (type == 'image' || type == 'gif') {
      return Center(
        child: InteractiveViewer(
          maxScale: 5,
          child: PageNetworkImage(url: url, fit: BoxFit.contain),
        ),
      );
    }
    if (type == 'video') {
      return Center(
        child: PageInlineVideo(
          url: url,
          height: MediaQuery.sizeOf(context).height * .8,
        ),
      );
    }
    return Center(
      child: _DocumentTile(name: item['name']?.toString() ?? 'Attachment'),
    );
  }
}

class _MediaError extends StatelessWidget {
  const _MediaError({required this.height, required this.label});

  final double height;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(height: height, child: Center(child: Text(label)));
  }
}
