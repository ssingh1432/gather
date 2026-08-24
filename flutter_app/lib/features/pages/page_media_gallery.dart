import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    try { return await SupabaseConfig.client.storage.from(bucket).createSignedUrl(path, 3600); } catch (_) { return url; }
  }
}

Future<void> showPageMediaViewer(BuildContext context, List<Map<String, dynamic>> items, {int initialIndex = 0}) async {
  final visible = items.where((item) => item['type'] != 'event').toList();
  if (visible.isEmpty || !context.mounted) return;
  await Navigator.of(context).push<void>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _PageMediaViewer(items: visible, initialIndex: initialIndex.clamp(0, visible.length - 1).toInt()),
  ));
}

class PageNetworkImage extends StatefulWidget {
  const PageNetworkImage({super.key, required this.url, this.width, this.height, this.fit = BoxFit.contain, this.borderRadius, this.errorWidget});
  final String url; final double? width; final double? height; final BoxFit fit; final BorderRadius? borderRadius; final WidgetBuilder? errorWidget;
  @override State<PageNetworkImage> createState() => _PageNetworkImageState();
}
class _PageNetworkImageState extends State<PageNetworkImage> {
  String? _resolvedUrl; ImageStream? _imageStream; ImageStreamListener? _imageListener; double? _aspectRatio;
  @override void initState() { super.initState(); _resolve(); }
  @override void didUpdateWidget(covariant PageNetworkImage oldWidget) { super.didUpdateWidget(oldWidget); if (oldWidget.url != widget.url) { _aspectRatio = null; _resolve(); } }
  @override void dispose() { if (_imageStream != null && _imageListener != null) _imageStream!.removeListener(_imageListener!); super.dispose(); }
  Future<void> _resolve() async { final resolved = await PageMediaUrlResolver.resolve(widget.url); if (!mounted) return; setState(() => _resolvedUrl = resolved); _listenForDimensions(resolved); }
  void _listenForDimensions(String url) { final provider = NetworkImage(url); final stream = provider.resolve(const ImageConfiguration()); _imageStream = stream; _imageListener = ImageStreamListener((info, _) { final size = info.image; if (!mounted || size.width <= 0 || size.height <= 0) return; setState(() => _aspectRatio = size.width / size.height); }, onError: (_, __) {}); stream.addListener(_imageListener!); }
  @override Widget build(BuildContext context) {
    Widget fallback() => widget.errorWidget?.call(context) ?? Container(width: widget.width, height: widget.height, color: Theme.of(context).colorScheme.surfaceContainerHighest, alignment: Alignment.center, child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.broken_image_outlined, color: Theme.of(context).colorScheme.onSurfaceVariant), const SizedBox(height: 4), Text('Image unavailable', style: Theme.of(context).textTheme.bodySmall)]));
    if (widget.url.trim().isEmpty) return fallback();
    final url = _resolvedUrl;
    if (url == null) return SizedBox(width: widget.width, height: widget.height ?? 240, child: const Center(child: CircularProgressIndicator(strokeWidth: 2)));
    final image = Image.network(url, width: widget.width, height: widget.height, fit: widget.fit, webHtmlElementStrategy: kIsWeb ? WebHtmlElementStrategy.prefer : WebHtmlElementStrategy.never, errorBuilder: (_, __, ___) => fallback());
    Widget child = widget.height == null && _aspectRatio != null ? AspectRatio(aspectRatio: _aspectRatio!.clamp(0.5625, 1.7778), child: image) : image;
    return widget.borderRadius == null ? child : ClipRRect(borderRadius: widget.borderRadius!, child: child);
  }
}

class PageInlineVideo extends StatefulWidget {
  const PageInlineVideo({super.key, required this.url, this.height = 220});
  final String url; final double height;
  @override State<PageInlineVideo> createState() => _PageInlineVideoState();
}
class _PageInlineVideoState extends State<PageInlineVideo> {
  VideoPlayerController? _controller; bool _loading = false; bool _failed = false; String? _resolvedUrl;
  @override void initState() { super.initState(); _resolve(); }
  @override void dispose() { _controller?.dispose(); super.dispose(); }
  Future<void> _resolve() async { final resolved = await PageMediaUrlResolver.resolve(widget.url); if (mounted) setState(() => _resolvedUrl = resolved); }
  Future<void> _start() async { final url = _resolvedUrl; if (url == null || _loading || _controller != null) return; setState(() => _loading = true); try { final controller = VideoPlayerController.networkUrl(Uri.parse(url)); await controller.initialize(); controller.setVolume(0); if (!mounted) { controller.dispose(); return; } setState(() { _controller = controller; _loading = false; }); await controller.play(); } catch (_) { if (mounted) setState(() { _loading = false; _failed = true; }); } }
  void _toggle() { final controller = _controller; if (controller == null) return; setState(() { if (controller.value.isPlaying) { controller.pause(); } else { controller.play(); } }); }
  @override Widget build(BuildContext context) { if (_failed) return _MediaError(height: widget.height, label: 'Video unavailable'); final controller = _controller; if (controller == null) return SizedBox(height: widget.height, child: Stack(alignment: Alignment.center, children: [Container(color: Colors.black.withValues(alpha: 0.08)), _loading || _resolvedUrl == null ? const CircularProgressIndicator(strokeWidth: 2) : IconButton.filled(onPressed: _start, icon: const Icon(Icons.play_arrow), iconSize: 34)])); final size = controller.value.size; final ratio = size.width > 0 && size.height > 0 ? (size.width / size.height).clamp(0.5625, 1.7778) : 16 / 9; return GestureDetector(onTap: _toggle, child: AspectRatio(aspectRatio: ratio, child: Stack(alignment: Alignment.center, children: [Positioned.fill(child: VideoPlayer(controller)), if (!controller.value.isPlaying) const Icon(Icons.play_circle_fill, size: 54, color: Colors.white70)]))); }
}

class PageMediaGallery extends StatelessWidget {
  const PageMediaGallery({super.key, required this.items, this.onOpen});
  final List<Map<String, dynamic>> items; final ValueChanged<int>? onOpen;
  @override Widget build(BuildContext context) {
    final visible = items.where((item) => item['type'] != 'event').toList(); if (visible.isEmpty) return const SizedBox.shrink();
    if (visible.length == 1) return _SingleTile(item: visible.first, onTap: onOpen == null ? null : () => onOpen!(0));
    if (visible.length == 2) return SizedBox(height: 240, child: Row(children: [Expanded(child: _Tile(item: visible[0], height: 240, onTap: onOpen == null ? null : () => onOpen!(0))), const SizedBox(width: 3), Expanded(child: _Tile(item: visible[1], height: 240, onTap: onOpen == null ? null : () => onOpen!(1)))]));
    if (visible.length == 3) return SizedBox(height: 300, child: Row(children: [Expanded(flex: 2, child: _Tile(item: visible[0], height: 300, onTap: onOpen == null ? null : () => onOpen!(0))), const SizedBox(width: 3), Expanded(child: Column(children: [Expanded(child: _Tile(item: visible[1], height: 148, onTap: onOpen == null ? null : () => onOpen!(1))), const SizedBox(height: 3), Expanded(child: _Tile(item: visible[2], height: 149, onTap: onOpen == null ? null : () => onOpen!(2)))]))]));
    final count = visible.length;
    return SizedBox(height: 300, child: GridView.builder(physics: const NeverScrollableScrollPhysics(), itemCount: 4, gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 3, mainAxisSpacing: 3), itemBuilder: (context, index) { final remaining = count - 4; return Stack(children: [Positioned.fill(child: _Tile(item: visible[index], height: 148, onTap: onOpen == null ? null : () => onOpen!(index))), if (index == 3 && remaining > 0) Positioned.fill(child: IgnorePointer(child: Container(color: Colors.black.withValues(alpha: 0.48), alignment: Alignment.center, child: Text('+$remaining more', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700))))]); }));
  }
}

class _SingleTile extends StatelessWidget {
  const _SingleTile({required this.item, this.onTap}); final Map<String, dynamic> item; final VoidCallback? onTap;
  Future<void> _download(BuildContext context) async { final raw = item['url']?.toString() ?? ''; if (raw.isEmpty) return; final url = await PageMediaUrlResolver.resolve(raw); if (!context.mounted) return; final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication); if (!ok && context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open this media.'))); }
  @override Widget build(BuildContext context) { final type = item['type']?.toString() ?? 'document'; final url = item['url']?.toString() ?? ''; final name = item['name']?.toString() ?? 'Attachment'; final media = switch (type) { 'image' || 'gif' => PageNetworkImage(url: url, width: double.infinity, fit: BoxFit.contain), 'video' => onTap == null ? PageInlineVideo(url: url, height: 300) : IgnorePointer(child: PageInlineVideo(url: url, height: 300)), _ => Container(width: double.infinity, padding: const EdgeInsets.all(20), color: Theme.of(context).colorScheme.surfaceContainerHighest, alignment: Alignment.center, child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.description_outlined, size: 48), const SizedBox(height: 8), Text(name, maxLines: 3, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center)])) }; final content = Stack(children: [Positioned.fill(child: media), Positioned(right: 10, top: 10, child: Material(color: Colors.black38, shape: const CircleBorder(), child: SizedBox(width: 34, height: 34, child: IconButton(padding: EdgeInsets.zero, constraints: const BoxConstraints.tightFor(width: 34, height: 34), tooltip: 'Download', onPressed: () => _download(context), icon: const Icon(Icons.download_outlined, color: Colors.white, size: 17))))]); return ClipRRect(borderRadius: BorderRadius.circular(10), child: onTap == null ? content : GestureDetector(onTap: onTap, child: content)); }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.item, required this.height, this.onTap}); final Map<String, dynamic> item; final double height; final VoidCallback? onTap;
  Future<void> _download(BuildContext context) async { final raw = item['url']?.toString() ?? ''; if (raw.isEmpty) return; final url = await PageMediaUrlResolver.resolve(raw); if (!context.mounted) return; final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication); if (!ok && context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open this media.'))); }
  @override Widget build(BuildContext context) { final type = item['type']?.toString() ?? 'document'; final url = item['url']?.toString() ?? ''; final name = item['name']?.toString() ?? 'Attachment'; final media = switch (type) { 'image' || 'gif' => PageNetworkImage(url: url, width: double.infinity, height: height, fit: BoxFit.cover), 'video' => onTap == null ? PageInlineVideo(url: url, height: height) : IgnorePointer(child: PageInlineVideo(url: url, height: height)), _ => Container(color: Theme.of(context).colorScheme.surfaceContainerHighest, padding: const EdgeInsets.all(16), alignment: Alignment.center, child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.description_outlined, size: 42), const SizedBox(height: 8), Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center)]) }; final content = Stack(children: [Positioned.fill(child: media), Positioned(right: 8, top: 8, child: Material(color: Colors.black38, shape: const CircleBorder(), child: SizedBox(width: 34, height: 34, child: IconButton(padding: EdgeInsets.zero, constraints: const BoxConstraints.tightFor(width: 34, height: 34), tooltip: 'Download', onPressed: () => _download(context), icon: const Icon(Icons.download_outlined, color: Colors.white, size: 17)))), if (type == 'video' && onTap == null) const Positioned(left: 8, bottom: 8, child: DecoratedBox(decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle), child: Padding(padding: EdgeInsets.all(6), child: Icon(Icons.play_arrow, color: Colors.white, size: 18))))]); return ClipRRect(borderRadius: BorderRadius.circular(10), child: onTap == null ? content : GestureDetector(onTap: onTap, child: content)); }
}

class PageMediaAttachmentList extends StatelessWidget { const PageMediaAttachmentList({super.key, required this.items}); final List<Map<String, dynamic>> items; @override Widget build(BuildContext context) => PageMediaGallery(items: items); }
class PageEventAttachmentCard extends StatelessWidget { const PageEventAttachmentCard({super.key, required this.event}); final Map<String, dynamic> event; @override Widget build(BuildContext context) => Container(margin: const EdgeInsets.fromLTRB(12, 0, 12, 10), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)), child: Row(children: [const Icon(Icons.event_outlined), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(event['title']?.toString() ?? 'Event', style: const TextStyle(fontWeight: FontWeight.w700)), if (event['start_time'] != null) Text(DateTime.parse(event['start_time'] as String).toLocal().toString(), style: Theme.of(context).textTheme.bodySmall), if (event['location'] != null) Text(event['location'].toString(), style: Theme.of(context).textTheme.bodySmall)]))])); }

class _PageMediaViewer extends StatefulWidget { const _PageMediaViewer({required this.items, required this.initialIndex}); final List<Map<String, dynamic>> items; final int initialIndex; @override State<_PageMediaViewer> createState() => _PageMediaViewerState(); }
class _PageMediaViewerState extends State<_PageMediaViewer> {
  late final PageController _controller; late int _index;
  @override void initState() { super.initState(); _index = widget.initialIndex; _controller = PageController(initialPage: _index); SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky); }
  @override void dispose() { _controller.dispose(); SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge); SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]); super.dispose(); }
  @override Widget build(BuildContext context) { final item = widget.items[_index]; return Scaffold(backgroundColor: Colors.black, appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text('${_index + 1} / ${widget.items.length}', style: const TextStyle(fontSize: 15))), body: PageView.builder(controller: _controller, itemCount: widget.items.length, onPageChanged: (value) => setState(() => _index = value), itemBuilder: (context, index) => _PageMediaViewerItem(item: widget.items[index])), floatingActionButton: _ViewerOpenButton(item: item)); }
}
class _ViewerOpenButton extends StatelessWidget { const _ViewerOpenButton({required this.item}); final Map<String, dynamic> item; Future<void> _open(BuildContext context) async { final raw = item['url']?.toString() ?? ''; if (raw.isEmpty) return; final url = await PageMediaUrlResolver.resolve(raw); if (!context.mounted) return; final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication); if (!ok && context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open this attachment.'))); } @override Widget build(BuildContext context) { final type = item['type']?.toString() ?? 'document'; if (type == 'image' || type == 'gif' || type == 'video') return const SizedBox.shrink(); return FloatingActionButton.extended(onPressed: () => _open(context), icon: const Icon(Icons.open_in_new), label: const Text('Open file')); } }
class _PageMediaViewerItem extends StatelessWidget { const _PageMediaViewerItem({required this.item}); final Map<String, dynamic> item; @override Widget build(BuildContext context) { final type = item['type']?.toString() ?? 'document'; final url = item['url']?.toString() ?? ''; final title = item['name']?.toString() ?? 'Attachment'; if (type == 'image' || type == 'gif') return Center(child: InteractiveViewer(minScale: 1, maxScale: 5, child: PageNetworkImage(url: url, fit: BoxFit.contain))); if (type == 'video') return _PageViewerVideo(url: url); return Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.description_outlined, color: Colors.white, size: 72), const SizedBox(height: 16), Text(title, textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600))]))); } }
class _PageViewerVideo extends StatefulWidget { const _PageViewerVideo({required this.url}); final String url; @override State<_PageViewerVideo> createState() => _PageViewerVideoState(); }
class _PageViewerVideoState extends State<_PageViewerVideo> {
  VideoPlayerController? _controller; bool _error = false; bool _controlsVisible = true;
  @override void initState() { super.initState(); _resolveAndStart(); }
  @override void dispose() { _controller?.dispose(); super.dispose(); }
  Future<void> _resolveAndStart() async { final resolved = await PageMediaUrlResolver.resolve(widget.url); if (!mounted) return; try { final controller = VideoPlayerController.networkUrl(Uri.parse(resolved)); await controller.initialize(); if (!mounted) { controller.dispose(); return; } controller.addListener(() { if (mounted) setState(() {}); }); setState(() => _controller = controller); await controller.play(); } catch (_) { if (mounted) setState(() => _error = true); } }
  void _togglePlay() { final controller = _controller; if (controller == null) return; if (controller.value.isPlaying) { controller.pause(); } else { controller.play(); } setState(() {}); }
  String _format(Duration duration) { final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0'); final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0'); return '$minutes:$seconds'; }
  @override Widget build(BuildContext context) { if (_error) return const Center(child: Text('Could not play this video.', style: TextStyle(color: Colors.white70))); final controller = _controller; if (controller == null) return const Center(child: CircularProgressIndicator()); final ratio = controller.value.aspectRatio == 0 ? 16 / 9 : controller.value.aspectRatio; return GestureDetector(onTap: () => setState(() => _controlsVisible = !_controlsVisible), child: Center(child: AspectRatio(aspectRatio: ratio, child: Stack(alignment: Alignment.center, children: [VideoPlayer(controller), if (_controlsVisible) ...[IconButton(onPressed: _togglePlay, iconSize: 60, color: Colors.white, icon: Icon(controller.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled)), Positioned(left: 8, right: 8, bottom: 0, child: Container(padding: const EdgeInsets.fromLTRB(8, 18, 8, 4), decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black87])), child: Row(children: [Text(_format(controller.value.position), style: const TextStyle(color: Colors.white, fontSize: 11)), Expanded(child: VideoProgressIndicator(controller, allowScrubbing: true, padding: const EdgeInsets.symmetric(horizontal: 8), colors: VideoProgressColors(playedColor: Theme.of(context).colorScheme.primary, backgroundColor: Colors.white24))), Text(_format(controller.value.duration), style: const TextStyle(color: Colors.white, fontSize: 11))])))] ])))); }
}
class _MediaError extends StatelessWidget { const _MediaError({required this.height, required this.label}); final double height; final String label; @override Widget build(BuildContext context) => Container(height: height, color: Theme.of(context).colorScheme.surfaceContainerHighest, alignment: Alignment.center, child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.broken_image_outlined), const SizedBox(height: 4), Text(label)])); }
