import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import '../../core/supabase_client.dart';
import 'page_media_collection_ux.dart';

class PageMediaUrlResolver {
  static const _buckets = {'page-media', 'page-visitor-media'};
  static Future<String> resolve(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return url;
    final s = uri.pathSegments;
    final i = s.indexOf('object');
    if (i < 0 || i + 2 >= s.length) return url;
    final mode = s[i + 1];
    final bucket = s[i + 2];
    if ((mode != 'public' && mode != 'authenticated') || !_buckets.contains(bucket)) return url;
    final path = s.sublist(i + 3).join('/');
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
  final visible = items.where((e) => e['type'] != 'event').toList();
  if (visible.isEmpty || !context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _PageMediaViewer(
        items: visible,
        initialIndex: pageMediaCollectionEntryIndex(initialIndex),
      ),
    ),
  );
}

class PageNetworkImage extends StatefulWidget {
  const PageNetworkImage({super.key, required this.url, this.width, this.height, this.fit = BoxFit.contain, this.borderRadius, this.errorWidget});
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final WidgetBuilder? errorWidget;
  @override State<PageNetworkImage> createState() => _PageNetworkImageState();
}
class _PageNetworkImageState extends State<PageNetworkImage> {
  String? _url;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  double? _ratio;
  @override void initState() { super.initState(); _resolve(); }
  @override void didUpdateWidget(covariant PageNetworkImage old) { super.didUpdateWidget(old); if (old.url != widget.url) { _ratio = null; _resolve(); } }
  @override void dispose() { if (_stream != null && _listener != null) _stream!.removeListener(_listener!); super.dispose(); }
  Future<void> _resolve() async {
    final u = await PageMediaUrlResolver.resolve(widget.url);
    if (!mounted) return;
    setState(() => _url = u);
    final s = NetworkImage(u).resolve(const ImageConfiguration());
    _stream = s;
    _listener = ImageStreamListener((info, _) { if (mounted && info.image.width > 0 && info.image.height > 0) setState(() => _ratio = info.image.width / info.image.height); }, onError: (_, __) {});
    s.addListener(_listener!);
  }
  @override Widget build(BuildContext context) {
    Widget fallback() => widget.errorWidget?.call(context) ?? Container(width: widget.width, height: widget.height, color: Theme.of(context).colorScheme.surfaceContainerHighest, alignment: Alignment.center, child: const Icon(Icons.broken_image_outlined));
    if (widget.url.trim().isEmpty) return fallback();
    final u = _url;
    if (u == null) return SizedBox(width: widget.width, height: widget.height ?? 240, child: const Center(child: CircularProgressIndicator(strokeWidth: 2)));
    final image = Image.network(u, width: widget.width, height: widget.height, fit: widget.fit, webHtmlElementStrategy: kIsWeb ? WebHtmlElementStrategy.prefer : WebHtmlElementStrategy.never, errorBuilder: (_, __, ___) => fallback());
    final child = widget.height == null && _ratio != null ? AspectRatio(aspectRatio: _ratio!.clamp(.5625, 1.7778), child: image) : image;
    return widget.borderRadius == null ? child : ClipRRect(borderRadius: widget.borderRadius!, child: child);
  }
}

class PageInlineVideo extends StatefulWidget {
  const PageInlineVideo({super.key, required this.url, this.height = 220});
  final String url;
  final double height;
  @override State<PageInlineVideo> createState() => _PageInlineVideoState();
}
class _PageInlineVideoState extends State<PageInlineVideo> {
  VideoPlayerController? _c;
  String? _url;
  bool _loading = false;
  bool _error = false;
  bool _muted = true;
  bool _completed = false;
  @override void initState() { super.initState(); _resolve(); }
  @override void dispose() { _c?.removeListener(_changed); _c?.dispose(); super.dispose(); }
  Future<void> _resolve() async { final u = await PageMediaUrlResolver.resolve(widget.url); if (mounted) setState(() => _url = u); }
  Future<void> _start() async {
    if (_loading || _error) return;
    final c = _c;
    if (c != null) { await _play(); return; }
    final u = _url;
    if (u == null) return;
    setState(() => _loading = true);
    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(u));
      await controller.initialize();
      await controller.setVolume(0);
      controller.addListener(_changed);
      if (!mounted) { controller.dispose(); return; }
      setState(() { _c = controller; _loading = false; });
      await controller.play();
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = true; });
    }
  }
  Future<void> _play() async {
    final c = _c;
    if (c == null) return;
    if (_completed || c.value.position >= c.value.duration) {
      await c.seekTo(Duration.zero);
      _completed = false;
    }
    await c.play();
    if (mounted) setState(() {});
  }
  Future<void> _togglePlay() async {
    if (_c == null) { await _start(); return; }
    if (_c!.value.isPlaying) { await _c!.pause(); } else { await _play(); }
    if (mounted) setState(() {});
  }
  Future<void> _mute() async {
    final c = _c;
    if (c == null) return;
    _muted = !_muted;
    await c.setVolume(_muted ? 0 : 1);
    if (mounted) setState(() {});
  }
  void _changed() {
    final c = _c;
    if (c == null || !mounted) return;
    final v = c.value;
    if (v.isInitialized && v.duration > Duration.zero && v.position >= v.duration && !_completed) {
      _completed = true;
      c.pause();
    }
    setState(() {});
  }
  @override Widget build(BuildContext context) {
    if (_error) return _MediaError(height: widget.height, label: 'Video unavailable');
    final c = _c;
    if (c == null) {
      return SizedBox(height: widget.height, child: Center(child: _loading || _url == null ? const CircularProgressIndicator(strokeWidth: 2) : IconButton.filled(onPressed: _start, icon: const Icon(Icons.play_arrow), iconSize: 34)));
    }
    final ratio = c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio.clamp(.5625, 1.7778);
    return SizedBox(
      height: widget.height,
      child: Center(
        child: AspectRatio(
          aspectRatio: ratio,
          child: Stack(
            alignment: Alignment.center,
            children: [
              VideoPlayer(c),
              Material(color: Colors.transparent, child: InkWell(onTap: _togglePlay, child: const SizedBox.expand())),
              if (!c.value.isPlaying || _completed) IconButton.filled(onPressed: _togglePlay, icon: Icon(_completed ? Icons.replay : Icons.play_arrow), iconSize: 32),
              Positioned(right: 8, bottom: 8, child: Material(color: Colors.black54, shape: const CircleBorder(), child: IconButton(tooltip: _muted ? 'Unmute' : 'Mute', onPressed: _mute, icon: Icon(_muted ? Icons.volume_off : Icons.volume_up, color: Colors.white))),
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
  @override Widget build(BuildContext context) {
    final v = items.where((e) => e['type'] != 'event').toList();
    if (v.isEmpty) return const SizedBox.shrink();
    void open() { if (onOpen != null) { onOpen!(0); } else { showPageMediaViewer(context, v); } }
    Widget tile(Map<String, dynamic> e, double h) => _Tile(item: e, height: h, onOpen: open);
    if (v.length == 1) return _SingleTile(item: v.first, onOpen: open);
    if (v.length == 2) return SizedBox(height: 240, child: Row(children: [Expanded(child: tile(v[0], 240)), const SizedBox(width: 3), Expanded(child: tile(v[1], 240))]));
    if (v.length == 3) return SizedBox(height: 300, child: Row(children: [Expanded(flex: 2, child: tile(v[0], 300)), const SizedBox(width: 3), Expanded(child: Column(children: [Expanded(child: tile(v[1], 148)), const SizedBox(height: 3), Expanded(child: tile(v[2], 149))]))]));
    final more = v.length - 4;
    return SizedBox(height: 300, child: GridView.builder(physics: const NeverScrollableScrollPhysics(), itemCount: 4, gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 3, mainAxisSpacing: 3), itemBuilder: (_, i) => Stack(children: [Positioned.fill(child: tile(v[i], 148)), if (i == 3 && more > 0) Positioned.fill(child: IgnorePointer(child: Container(color: Colors.black54, alignment: Alignment.center, child: Text('+$more more', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700))))])));
  }
}

class _SingleTile extends StatelessWidget {
  const _SingleTile({required this.item, required this.onOpen});
  final Map<String, dynamic> item;
  final VoidCallback onOpen;
  Future<void> _download(BuildContext context) async { final raw = item['url']?.toString() ?? ''; if (raw.isEmpty) return; final u = await PageMediaUrlResolver.resolve(raw); if (!context.mounted) return; await launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication); }
  @override Widget build(BuildContext context) {
    final type = item['type']?.toString() ?? 'document';
    final url = item['url']?.toString() ?? '';
    if (type == 'video') return ClipRRect(borderRadius: BorderRadius.circular(10), child: Stack(children: [PageInlineVideo(url: url, height: 300), Positioned(right: 10, top: 10, child: _DownloadButton(onPressed: () => _download(context))), Positioned(left: 10, top: 10, child: _GalleryButton(onPressed: onOpen))]));
    final media = type == 'image' || type == 'gif' ? PageNetworkImage(url: url, width: double.infinity, fit: BoxFit.contain) : _DocumentTile(name: item['name']?.toString() ?? 'Attachment');
    return ClipRRect(borderRadius: BorderRadius.circular(10), child: GestureDetector(onTap: onOpen, child: Stack(children: [Positioned.fill(child: media), Positioned(right: 10, top: 10, child: _DownloadButton(onPressed: () => _download(context)))])));
  }
}
class _Tile extends StatelessWidget {
  const _Tile({required this.item, required this.height, required this.onOpen});
  final Map<String, dynamic> item;
  final double height;
  final VoidCallback onOpen;
  Future<void> _download(BuildContext context) async { final raw = item['url']?.toString() ?? ''; if (raw.isEmpty) return; final u = await PageMediaUrlResolver.resolve(raw); if (!context.mounted) return; await launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication); }
  @override Widget build(BuildContext context) {
    final type = item['type']?.toString() ?? 'document';
    final url = item['url']?.toString() ?? '';
    if (type == 'video') return ClipRRect(borderRadius: BorderRadius.circular(10), child: Stack(children: [PageInlineVideo(url: url, height: height), Positioned(right: 8, top: 8, child: _DownloadButton(onPressed: () => _download(context))), Positioned(left: 8, top: 8, child: _GalleryButton(onPressed: onOpen))]));
    final media = type == 'image' || type == 'gif' ? PageNetworkImage(url: url, width: double.infinity, height: height, fit: BoxFit.cover) : _DocumentTile(name: item['name']?.toString() ?? 'Attachment');
    return ClipRRect(borderRadius: BorderRadius.circular(10), child: GestureDetector(onTap: onOpen, child: Stack(children: [Positioned.fill(child: media), Positioned(right: 8, top: 8, child: _DownloadButton(onPressed: () => _download(context)))])));
  }
}
class _DocumentTile extends StatelessWidget { const _DocumentTile({required this.name}); final String name; @override Widget build(BuildContext context) => Container(color: Theme.of(context).colorScheme.surfaceContainerHighest, alignment: Alignment.center, padding: const EdgeInsets.all(16), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.description_outlined, size: 42), const SizedBox(height: 8), Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center)])); }
class _GalleryButton extends StatelessWidget { const _GalleryButton({required this.onPressed}); final VoidCallback onPressed; @override Widget build(BuildContext context) => Material(color: Colors.black54, shape: const CircleBorder(), child: IconButton(tooltip: 'Open gallery', onPressed: onPressed, icon: const Icon(Icons.collections_outlined, color: Colors.white))); }
class _DownloadButton extends StatelessWidget { const _DownloadButton({required this.onPressed}); final VoidCallback onPressed; @override Widget build(BuildContext context) => Material(color: Colors.black45, shape: const CircleBorder(), child: IconButton(tooltip: 'Download', onPressed: onPressed, icon: const Icon(Icons.download_outlined, color: Colors.white, size: 18))); }
class PageMediaAttachmentList extends StatelessWidget { const PageMediaAttachmentList({super.key, required this.items}); final List<Map<String, dynamic>> items; @override Widget build(BuildContext context) => PageMediaGallery(items: items); }
class PageEventAttachmentCard extends StatelessWidget { const PageEventAttachmentCard({super.key, required this.event}); final Map<String, dynamic> event; @override Widget build(BuildContext context) => Container(margin: const EdgeInsets.fromLTRB(12, 0, 12, 10), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)), child: Row(children: [const Icon(Icons.event_outlined), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(event['title']?.toString() ?? 'Event', style: const TextStyle(fontWeight: FontWeight.w700)), if (event['start_time'] != null) Text(DateTime.parse(event['start_time'] as String).toLocal().toString(), style: Theme.of(context).textTheme.bodySmall), if (event['location'] != null) Text(event['location'].toString(), style: Theme.of(context).textTheme.bodySmall)]))])); }

class _PageMediaViewer extends StatefulWidget { const _PageMediaViewer({required this.items, required this.initialIndex}); final List<Map<String, dynamic>> items; final int initialIndex; @override State<_PageMediaViewer> createState() => _PageMediaViewerState(); }
class _PageMediaViewerState extends State<_PageMediaViewer> { late final PageController _controller; late int _index; @override void initState() { super.initState(); _index = widget.initialIndex.clamp(0, widget.items.length - 1).toInt(); _controller = PageController(initialPage: _index); SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky); } @override void dispose() { _controller.dispose(); SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge); SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]); super.dispose(); } @override Widget build(BuildContext context) { final item = widget.items[_index]; return Scaffold(backgroundColor: Colors.black, appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text('${_index + 1} / ${widget.items.length}', style: const TextStyle(fontSize: 15))), body: PageView.builder(controller: _controller, itemCount: widget.items.length, onPageChanged: (i) => setState(() => _index = i), itemBuilder: (_, i) => _ViewerItem(item: widget.items[i])), floatingActionButton: _ViewerOpen(item: item)); } }
class _ViewerOpen extends StatelessWidget { const _ViewerOpen({required this.item}); final Map<String, dynamic> item; Future<void> _open(BuildContext context) async { final raw = item['url']?.toString() ?? ''; if (raw.isEmpty) return; final u = await PageMediaUrlResolver.resolve(raw); if (context.mounted) await launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication); } @override Widget build(BuildContext context) { final t = item['type']?.toString() ?? 'document'; return t == 'image' || t == 'gif' || t == 'video' ? const SizedBox.shrink() : FloatingActionButton.extended(onPressed: () => _open(context), icon: const Icon(Icons.open_in_new), label: const Text('Open file')); } }
class _ViewerItem extends StatelessWidget { const _ViewerItem({required this.item}); final Map<String, dynamic> item; @override Widget build(BuildContext context) { final t = item['type']?.toString() ?? 'document'; final u = item['url']?.toString() ?? ''; if (t == 'image' || t == 'gif') return Center(child: InteractiveViewer(maxScale: 5, child: PageNetworkImage(url: u, fit: BoxFit.contain))); if (t == 'video') return Center(child: PageInlineVideo(url: u, height: MediaQuery.sizeOf(context).height * .8)); return Center(child: _DocumentTile(name: item['name']?.toString() ?? 'Attachment')); } }
class _MediaError extends StatelessWidget { const _MediaError({required this.height, required this.label}); final double height; final String label; @override Widget build(BuildContext context) => SizedBox(height: height, child: Center(child: Text(label))); }
