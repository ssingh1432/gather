import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../core/supabase_client.dart';

class PageMediaUrlResolver {
  static const _pageBuckets = {'page-media', 'page-visitor-media'};

  static Future<String> resolve(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return url;
    final segments = uri.pathSegments;
    final objectIndex = segments.indexOf('object');
    if (objectIndex < 0 || objectIndex + 2 >= segments.length) return url;
    final mode = segments[objectIndex + 1];
    if (mode != 'public' && mode != 'authenticated') return url;
    final bucket = segments[objectIndex + 2];
    if (!_pageBuckets.contains(bucket)) return url;
    final path = segments.sublist(objectIndex + 3).join('/');
    if (path.isEmpty) return url;
    try {
      return await SupabaseConfig.client.storage.from(bucket).createSignedUrl(path, 3600);
    } catch (_) {
      return url;
    }
  }
}

class PageNetworkImage extends StatefulWidget {
  const PageNetworkImage({super.key, required this.url, this.width, this.height, this.fit = BoxFit.contain, this.borderRadius, this.errorWidget});
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
  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;
  double? _aspectRatio;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant PageNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _aspectRatio = null;
      _resolve();
    }
  }

  @override
  void dispose() {
    if (_imageStream != null && _imageListener != null) {
      _imageStream!.removeListener(_imageListener!);
    }
    super.dispose();
  }

  Future<void> _resolve() async {
    final resolved = await PageMediaUrlResolver.resolve(widget.url);
    if (!mounted) return;
    setState(() => _resolvedUrl = resolved);
    _listenForDimensions(resolved);
  }

  void _listenForDimensions(String url) {
    final provider = NetworkImage(url);
    final stream = provider.resolve(const ImageConfiguration());
    _imageStream = stream;
    _imageListener = ImageStreamListener((info, _) {
      final size = info.image;
      if (!mounted || size.width <= 0 || size.height <= 0) return;
      setState(() => _aspectRatio = size.width / size.height);
    }, onError: (_, __) {});
    stream.addListener(_imageListener!);
  }

  @override
  Widget build(BuildContext context) {
    Widget fallback() => widget.errorWidget?.call(context) ?? Container(
      width: widget.width,
      height: widget.height,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.broken_image_outlined, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(height: 4),
        Text('Image unavailable', style: Theme.of(context).textTheme.bodySmall),
      ]),
    );

    if (widget.url.trim().isEmpty) return fallback();
    final url = _resolvedUrl;
    if (url == null) {
      return SizedBox(width: widget.width, height: widget.height ?? 240, child: const Center(child: CircularProgressIndicator(strokeWidth: 2)));
    }

    final image = Image.network(
      url,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      webHtmlElementStrategy: kIsWeb ? WebHtmlElementStrategy.prefer : WebHtmlElementStrategy.never,
      errorBuilder: (_, __, ___) => fallback(),
    );

    Widget child;
    if (widget.height == null && _aspectRatio != null) {
      child = AspectRatio(aspectRatio: _aspectRatio!.clamp(0.5625, 1.7778), child: image);
    } else {
      child = image;
    }
    return widget.borderRadius == null ? child : ClipRRect(borderRadius: widget.borderRadius!, child: child);
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
  bool _loading = false;
  bool _failed = false;
  String? _resolvedUrl;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _resolve() async {
    final resolved = await PageMediaUrlResolver.resolve(widget.url);
    if (mounted) setState(() => _resolvedUrl = resolved);
  }

  Future<void> _start() async {
    final url = _resolvedUrl;
    if (url == null || _loading || _controller != null) return;
    setState(() => _loading = true);
    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      await controller.initialize();
      controller.setVolume(0);
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _loading = false;
      });
      await controller.play();
    } catch (_) {
      if (mounted) setState(() { _loading = false; _failed = true; });
    }
  }

  void _toggle() {
    final controller = _controller;
    if (controller == null) return;
    setState(() {
      if (controller.value.isPlaying) {
        controller.pause();
      } else {
        controller.play();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return _MediaError(height: widget.height, label: 'Video unavailable');
    final controller = _controller;
    if (controller == null) {
      return SizedBox(
        height: widget.height,
        child: Stack(alignment: Alignment.center, children: [
          Container(color: Colors.black.withValues(alpha: 0.08)),
          _loading || _resolvedUrl == null
              ? const CircularProgressIndicator(strokeWidth: 2)
              : IconButton.filled(onPressed: _start, icon: const Icon(Icons.play_arrow), iconSize: 34),
        ]),
      );
    }
    final size = controller.value.size;
    final ratio = size.width > 0 && size.height > 0 ? (size.width / size.height).clamp(0.5625, 1.7778) : 16 / 9;
    return GestureDetector(
      onTap: _toggle,
      child: AspectRatio(
        aspectRatio: ratio,
        child: Stack(alignment: Alignment.center, children: [
          Positioned.fill(child: VideoPlayer(controller)),
          if (!controller.value.isPlaying) const Icon(Icons.play_circle_fill, size: 54, color: Colors.white70),
        ]),
      ),
    );
  }
}

class PageMediaGallery extends StatelessWidget {
  const PageMediaGallery({super.key, required this.items});
  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    final visible = items.where((item) => item['type'] != 'event').toList();
    if (visible.isEmpty) return const SizedBox.shrink();

    // A single attachment keeps its natural aspect ratio. The old fixed
    // 280px box cropped portrait/landscape media with BoxFit.cover, making
    // Page posts look broken compared with the normal Home feed.
    if (visible.length == 1) return _SingleTile(item: visible.first);

    // Multi-attachment layouts intentionally use tiles, but the tiles remain
    // bounded and are limited to four visible items. This avoids an unbounded
    // vertical gallery while keeping the existing collage behavior.
    if (visible.length == 2) {
      return SizedBox(
        height: 240,
        child: Row(children: [
          Expanded(child: _Tile(item: visible[0], height: 240)),
          const SizedBox(width: 3),
          Expanded(child: _Tile(item: visible[1], height: 240)),
        ]),
      );
    }
    if (visible.length == 3) {
      return SizedBox(
        height: 300,
        child: Row(children: [
          Expanded(flex: 2, child: _Tile(item: visible[0], height: 300)),
          const SizedBox(width: 3),
          Expanded(child: Column(children: [
            Expanded(child: _Tile(item: visible[1], height: 148)),
            const SizedBox(height: 3),
            Expanded(child: _Tile(item: visible[2], height: 149)),
          ])),
        ]),
      );
    }

    final count = visible.length;
    return SizedBox(
      height: 300,
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: count > 4 ? 4 : count,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 3, mainAxisSpacing: 3),
        itemBuilder: (context, index) {
          final remaining = count - 4;
          return Stack(children: [
            Positioned.fill(child: _Tile(item: visible[index], height: 148)),
            if (index == 3 && remaining > 0)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.48),
                  alignment: Alignment.center,
                  child: Text('+$remaining more', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

class _SingleTile extends StatelessWidget {
  const _SingleTile({required this.item});
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final type = item['type']?.toString() ?? 'document';
    final url = item['url']?.toString() ?? '';
    final name = item['name']?.toString() ?? 'Attachment';
    if (type == 'image' || type == 'gif') {
      return _SingleImage(url: url);
    }
    if (type == 'video') return PageInlineVideo(url: url, height: 300);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.description_outlined, size: 48),
        const SizedBox(height: 8),
        Text(name, maxLines: 3, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
      ]),
    );
  }
}

class _SingleImage extends StatelessWidget {
  const _SingleImage({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) => PageNetworkImage(url: url, width: double.infinity, fit: BoxFit.contain);
}

class _Tile extends StatelessWidget {
  const _Tile({required this.item, required this.height});
  final Map<String, dynamic> item;
  final double height;

  Future<void> _download(BuildContext context) async {
    final raw = item['url']?.toString() ?? '';
    if (raw.isEmpty) return;
    final url = await PageMediaUrlResolver.resolve(raw);
    if (!context.mounted) return;
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open this media.')));
  }

  @override
  Widget build(BuildContext context) {
    final type = item['type']?.toString() ?? 'document';
    final url = item['url']?.toString() ?? '';
    final name = item['name']?.toString() ?? 'Attachment';
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(children: [
        Positioned.fill(
          child: switch (type) {
            'image' || 'gif' => PageNetworkImage(url: url, width: double.infinity, height: height, fit: BoxFit.cover),
            'video' => PageInlineVideo(url: url, height: height),
            _ => Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              padding: const EdgeInsets.all(16),
              alignment: Alignment.center,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.description_outlined, size: 42),
                const SizedBox(height: 8),
                Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
              ]),
            ),
          },
        ),
        Positioned(
          right: 8,
          top: 8,
          child: Material(
            color: Colors.black54,
            shape: const CircleBorder(),
            child: IconButton(
              tooltip: 'Download',
              onPressed: () => _download(context),
              icon: const Icon(Icons.download_outlined, color: Colors.white, size: 20),
            ),
          ),
        ),
        if (type == 'video') const Positioned(left: 8, bottom: 8, child: DecoratedBox(decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle), child: Padding(padding: EdgeInsets.all(6), child: Icon(Icons.play_arrow, color: Colors.white, size: 18)))),
      ]),
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
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
    child: Row(children: [
      const Icon(Icons.event_outlined),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(event['title']?.toString() ?? 'Event', style: const TextStyle(fontWeight: FontWeight.w700)),
        if (event['start_time'] != null) Text(DateTime.parse(event['start_time'] as String).toLocal().toString(), style: Theme.of(context).textTheme.bodySmall),
        if (event['location'] != null) Text(event['location'].toString(), style: Theme.of(context).textTheme.bodySmall),
      ])),
    ]),
  );
}

class _MediaError extends StatelessWidget {
  const _MediaError({required this.height, required this.label});
  final double height;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    alignment: Alignment.center,
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.broken_image_outlined),
      const SizedBox(height: 4),
      Text(label),
    ]),
  );
}
