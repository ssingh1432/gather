import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../../shared/services/media_download_service.dart';

/// Full-screen viewer for a single post's media.
///
/// - Images: pinch-to-zoom + pan via [InteractiveViewer].
/// - Videos: `video_player` with play/pause, a seek bar, a fullscreen
///   (landscape + immersive) toggle, wrapped in [InteractiveViewer] so
///   pinch-to-zoom works on video too.
///
/// Both media types share a download button in the app bar that saves the
/// file to the device gallery (mobile) or triggers a browser download
/// (Web) via [saveMediaToDevice].
class MediaViewerScreen extends StatefulWidget {
  const MediaViewerScreen({super.key, required this.url, required this.isVideo});
  final String url;
  final bool isVideo;

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  bool _downloading = false;

  Future<void> _download() async {
    if (_downloading || widget.url.isEmpty) return;
    setState(() => _downloading = true);
    try {
      await saveMediaToDevice(url: widget.url, isVideo: widget.isVideo);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.isVideo ? 'Video saved.' : 'Photo saved.')),
        );
      }
    } on MediaDownloadException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save media. Please try again.')));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            onPressed: _downloading ? null : _download,
            icon: _downloading
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.download_outlined),
            tooltip: 'Download',
          ),
        ],
      ),
      body: widget.url.isEmpty
          ? const Center(child: Text('Media unavailable', style: TextStyle(color: Colors.white70)))
          : widget.isVideo
              ? _VideoViewer(url: widget.url)
              : _ImageViewer(url: widget.url),
    );
  }
}

class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) => InteractiveViewer(
        minScale: 1,
        maxScale: 5,
        child: Center(
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.contain,
            placeholder: (context, url) => const CircularProgressIndicator(),
            errorWidget: (context, url, error) => const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
          ),
        ),
      );
}

class _VideoViewer extends StatefulWidget {
  const _VideoViewer({required this.url});
  final String url;

  @override
  State<_VideoViewer> createState() => _VideoViewerState();
}

class _VideoViewerState extends State<_VideoViewer> {
  late final VideoPlayerController _controller;
  bool _ready = false;
  bool _error = false;
  bool _controlsVisible = true;
  bool _fullscreen = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _ready = true);
        _controller.play();
      }).catchError((_) {
        if (mounted) setState(() => _error = true);
      });
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _restoreSystemChrome();
    _controller.dispose();
    super.dispose();
  }

  void _restoreSystemChrome() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
  }

  void _toggleFullscreen() {
    setState(() => _fullscreen = !_fullscreen);
    if (_fullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    } else {
      _restoreSystemChrome();
    }
  }

  void _togglePlay() {
    if (_controller.value.isPlaying) {
      _controller.pause();
    } else {
      _controller.play();
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    if (_error) {
      return const Center(child: Text('Could not play this video.', style: TextStyle(color: Colors.white70)));
    }
    if (!_ready) {
      return const Center(child: CircularProgressIndicator());
    }

    return GestureDetector(
      onTap: () => setState(() => _controlsVisible = !_controlsVisible),
      child: InteractiveViewer(
        minScale: 1,
        maxScale: 5,
        child: Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              AspectRatio(
                aspectRatio: _controller.value.aspectRatio == 0 ? 16 / 9 : _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              ),
              if (_controlsVisible) ...[
                IconButton(
                  iconSize: 56,
                  color: Colors.white,
                  onPressed: _togglePlay,
                  icon: Icon(_controller.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 20, 12, 8),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black87]),
                    ),
                    child: Row(
                      children: [
                        Text(_formatDuration(_controller.value.position), style: const TextStyle(color: Colors.white, fontSize: 12)),
                        Expanded(
                          child: VideoProgressIndicator(
                            _controller,
                            allowScrubbing: true,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            colors: VideoProgressColors(playedColor: Theme.of(context).colorScheme.primary, backgroundColor: Colors.white24),
                          ),
                        ),
                        Text(_formatDuration(_controller.value.duration), style: const TextStyle(color: Colors.white, fontSize: 12)),
                        IconButton(
                          onPressed: _toggleFullscreen,
                          icon: Icon(_fullscreen ? Icons.fullscreen_exit : Icons.fullscreen, color: Colors.white),
                          tooltip: 'Fullscreen',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
