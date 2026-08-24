import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../core/supabase_client.dart';

/// Page-only media presentation. It deliberately does not replace the
/// shared/community media widgets.
class PagePostMediaUrlResolver {
  static const _buckets = {'page-media', 'page-visitor-media'};

  static Future<String> resolve(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return url;
    final segments = uri.pathSegments;
    final objectIndex = segments.indexOf('object');
    if (objectIndex < 0 || objectIndex + 2 >= segments.length) return url;
    final mode = segments[objectIndex + 1];
    if (mode != 'public' && mode != 'authenticated') return url;
    final bucket = segments[objectIndex + 2];
    if (!_buckets.contains(bucket)) return url;
    final path = segments.sublist(objectIndex + 3).join('/');
    if (path.isEmpty) return url;
    try {
      return await SupabaseConfig.client.storage.from(bucket).createSignedUrl(path, 3600);
    } catch (_) {
      return url;
    }
  }
}

class PagePostMediaAttachmentList extends StatelessWidget {
  const PagePostMediaAttachmentList({super.key, required this.items});
  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    final media = items.where((item) => item['type']?.toString() != 'event').toList();
    if (media.isEmpty) return const SizedBox.shrink();
    return _PageMediaPreviewGrid(items: media);
  }
}

class _PageMediaPreviewGrid extends StatelessWidget {
  const _PageMediaPreviewGrid({required this.items});
  final List<Map<String, dynamic>> items;

  void _open(BuildContext context, int index) => showPagePostMediaList(context, items, initialIndex: index);

  @override
  Widget build(BuildContext context) {
    if (items.length == 1) {
      return _PreviewTile(item: items.first, onTap: () => _open(context, 0), height: 300);
    }
    if (items.length == 2) {
      return SizedBox(
        height: 240,
        child: Row(children: [
          Expanded(child: _PreviewTile(item: items[0], onTap: () => _open(context, 0), height: 240)),
          const SizedBox(width: 3),
          Expanded(child: _PreviewTile(item: items[1], onTap: () => _open(context, 1), height: 240)),
        ]),
      );
    }
    if (items.length == 3) {
      return SizedBox(
        height: 300,
        child: Row(children: [
          Expanded(flex: 2, child: _PreviewTile(item: items[0], onTap: () => _open(context, 0), height: 300)),
          const SizedBox(width: 3),
          Expanded(child: Column(children: [
            Expanded(child: _PreviewTile(item: items[1], onTap: () => _open(context, 1), height: 148)),
            const SizedBox(height: 3),
            Expanded(child: _PreviewTile(item: items[2], onTap: () => _open(context, 2), height: 149)),
          ])),
        ]),
      );
    }

    final remaining = items.length - 4;
    return SizedBox(
      height: 300,
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 4,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 3, mainAxisSpacing: 3),
        itemBuilder: (context, index) => Stack(children: [
          Positioned.fill(child: _PreviewTile(item: items[index], onTap: () => _open(context, index), height: 148)),
          if (index == 3 && remaining > 0)
            Positioned.fill(child: IgnorePointer(child: Container(color: Colors.black.withValues(alpha: 0.48), alignment: Alignment.center, child: Text('+$remaining more', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700))))),
        ]),
      ),
    );
  }
}

class _PreviewTile extends StatelessWidget {
  const _PreviewTile({required this.item, required this.onTap, required this.height});
  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final type = item['type']?.toString() ?? 'document';
    final url = item['url']?.toString() ?? '';
    final name = item['name']?.toString() ?? 'Attachment';
    Widget media;
    if (type == 'image' || type == 'gif') {
      media = _PageNetworkImage(url: url, fit: BoxFit.cover);
    } else if (type == 'video') {
      media = _PageVideo(url: url, height: height, compact: true);
    } else {
      media = Container(color: Theme.of(context).colorScheme.surfaceContainerHighest, alignment: Alignment.center, padding: const EdgeInsets.all(16), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.description_outlined, size: 42), const SizedBox(height: 8), Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center)]));
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(fit: StackFit.expand, children: [
        media,
        Positioned(right: 8, top: 8, child: _PageDownloadButton(item: item)),
        Positioned.fill(child: Material(type: MaterialType.transparency, child: InkWell(onTap: onTap))),
      ]),
    );
  }
}

class _PageNetworkImage extends StatefulWidget {
  const _PageNetworkImage({required this.url, this.fit = BoxFit.contain});
  final String url;
  final BoxFit fit;

  @override
  State<_PageNetworkImage> createState() => _PageNetworkImageState();
}

class _PageNetworkImageState extends State<_PageNetworkImage> {
  String? _resolved;
  @override
  void initState() { super.initState(); _resolve(); }
  Future<void> _resolve() async {
    final url = await PagePostMediaUrlResolver.resolve(widget.url);
    if (mounted) setState(() => _resolved = url);
  }
  @override
  Widget build(BuildContext context) {
    final url = _resolved;
    if (url == null) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    return Image.network(url, fit: widget.fit, webHtmlElementStrategy: kIsWeb ? WebHtmlElementStrategy.prefer : WebHtmlElementStrategy.never, errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_outlined)));
  }
}

class _PageDownloadButton extends StatelessWidget {
  const _PageDownloadButton({required this.item});
  final Map<String, dynamic> item;
  Future<void> _download(BuildContext context) async {
    final raw = item['url']?.toString() ?? '';
    if (raw.isEmpty) return;
    final url = await PagePostMediaUrlResolver.resolve(raw);
    if (!context.mounted) return;
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open this media.')));
  }
  @override
  Widget build(BuildContext context) => Material(color: Colors.black.withValues(alpha: 0.42), shape: const CircleBorder(), child: InkWell(customBorder: const CircleBorder(), onTap: () => _download(context), child: const SizedBox(width: 30, height: 30, child: Icon(Icons.download_outlined, size: 16, color: Colors.white))));
}

Future<void> showPagePostMediaList(BuildContext context, List<Map<String, dynamic>> items, {int initialIndex = 0}) async {
  if (items.isEmpty || !context.mounted) return;
  await Navigator.of(context).push<void>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => _PageMediaListScreen(items: items, initialIndex: initialIndex)));
}

class _PageMediaListScreen extends StatefulWidget {
  const _PageMediaListScreen({required this.items, required this.initialIndex});
  final List<Map<String, dynamic>> items;
  final int initialIndex;
  @override
  State<_PageMediaListScreen> createState() => _PageMediaListScreenState();
}

class _PageMediaListScreenState extends State<_PageMediaListScreen> {
  late final ScrollController _scrollController;
  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.initialIndex <= 0) return;
      final offset = (widget.initialIndex * 340.0).clamp(0.0, _scrollController.position.maxScrollExtent);
      _scrollController.jumpTo(offset);
    });
  }
  @override
  void dispose() { _scrollController.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Theme.of(context).colorScheme.surface,
    appBar: AppBar(title: Text('${widget.items.length} attachments'), actions: [IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close))]),
    body: ListView.separated(controller: _scrollController, padding: const EdgeInsets.fromLTRB(12, 12, 12, 28), itemCount: widget.items.length, separatorBuilder: (_, __) => const SizedBox(height: 14), itemBuilder: (context, index) => _PageMediaListItem(item: widget.items[index], index: index)),
  );
}

class _PageMediaListItem extends StatelessWidget {
  const _PageMediaListItem({required this.item, required this.index});
  final Map<String, dynamic> item;
  final int index;
  @override
  Widget build(BuildContext context) {
    final type = item['type']?.toString() ?? 'document';
    final url = item['url']?.toString() ?? '';
    final name = item['name']?.toString() ?? 'Attachment';
    Widget media;
    if (type == 'image' || type == 'gif') media = ClipRRect(borderRadius: BorderRadius.circular(12), child: _PageNetworkImage(url: url, fit: BoxFit.contain));
    else if (type == 'video') media = ClipRRect(borderRadius: BorderRadius.circular(12), child: _PageVideo(url: url, height: 360));
    else media = Container(width: double.infinity, padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)), child: Column(children: [const Icon(Icons.description_outlined, size: 52), const SizedBox(height: 8), Text(name, textAlign: TextAlign.center)]));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Text('${index + 1}', style: Theme.of(context).textTheme.labelLarge), const Spacer(), _PageDownloadButton(item: item)]), const SizedBox(height: 6), media]);
  }
}

class _PageVideo extends StatefulWidget {
  const _PageVideo({required this.url, required this.height, this.compact = false});
  final String url;
  final double height;
  final bool compact;
  @override
  State<_PageVideo> createState() => _PageVideoState();
}

class _PageVideoState extends State<_PageVideo> {
  VideoPlayerController? _controller;
  String? _resolved;
  bool _loading = false;
  bool _muted = true;
  bool _failed = false;

  @override
  void initState() { super.initState(); _resolve(); }

  @override
  void dispose() { _controller?.removeListener(_onControllerChanged); _controller?.dispose(); super.dispose(); }

  Future<void> _resolve() async {
    final url = await PagePostMediaUrlResolver.resolve(widget.url);
    if (mounted) setState(() => _resolved = url);
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final controller = _controller;
    if (controller == null) return;
    final value = controller.value;
    if (value.hasError && !_failed) {
      setState(() => _failed = true);
      return;
    }
    if (value.isInitialized) setState(() {});
  }

  Future<void> _start() async {
    if (_resolved == null || _loading || _controller != null) return;
    setState(() => _loading = true);
    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(_resolved!));
      await controller.initialize();
      await controller.setVolume(0);
      controller.addListener(_onControllerChanged);
      if (!mounted) {
        controller.removeListener(_onControllerChanged);
        controller.dispose();
        return;
      }
      setState(() { _controller = controller; _loading = false; });
      await controller.play();
    } catch (_) {
      if (mounted) setState(() { _loading = false; _failed = true; });
    }
  }

  void _togglePlay() {
    final controller = _controller;
    if (controller == null) return;
    if (controller.value.isCompleted) {
      controller.seekTo(Duration.zero);
      controller.play();
      return;
    }
    controller.value.isPlaying ? controller.pause() : controller.play();
  }

  Future<void> _toggleMute() async {
    final controller = _controller;
    if (controller == null) return;
    final nextMuted = !_muted;
    await controller.setVolume(nextMuted ? 0 : 1);
    if (mounted) setState(() => _muted = nextMuted);
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return SizedBox(height: widget.height, child: const Center(child: Text('Video unavailable')));
    final controller = _controller;
    if (controller == null) return SizedBox(height: widget.height, child: Center(child: _loading || _resolved == null ? const CircularProgressIndicator(strokeWidth: 2) : IconButton.filled(onPressed: _start, icon: const Icon(Icons.play_arrow), iconSize: widget.compact ? 28 : 36)));
    final size = controller.value.size;
    final ratio = size.width > 0 && size.height > 0 ? (size.width / size.height).clamp(0.5625, 1.7778) : 16 / 9;
    return GestureDetector(
      onTap: _togglePlay,
      child: AspectRatio(aspectRatio: ratio, child: Stack(alignment: Alignment.center, children: [
        Positioned.fill(child: VideoPlayer(controller)),
        if (!controller.value.isPlaying) const Icon(Icons.play_circle_fill, size: 58, color: Colors.white70),
        Positioned(right: 8, bottom: 8, child: Material(color: Colors.black.withValues(alpha: 0.48), shape: const CircleBorder(), child: InkWell(customBorder: const CircleBorder(), onTap: _toggleMute, child: Padding(padding: const EdgeInsets.all(8), child: Icon(_muted ? Icons.volume_off : Icons.volume_up, size: 18, color: Colors.white)))),
      ])),
    );
  }
}
