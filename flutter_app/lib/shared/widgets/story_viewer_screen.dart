import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/models.dart';
import '../../features/data/repositories.dart';

/// Instagram/Facebook/Snapchat-style story viewer: segmented progress bars
/// across the top (one per story for the current author), tap right half
/// to advance, tap left half to go back, hold to pause. Images show for a
/// fixed duration; videos drive the progress bar off their own playback.
class StoryViewerScreen extends StatefulWidget {
  const StoryViewerScreen({super.key, required this.authorIds, required this.startAuthorId});
  final List<String> authorIds;
  final String startAuthorId;

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen> with SingleTickerProviderStateMixin {
  static const _imageDuration = Duration(seconds: 5);

  late int _authorIndex;
  List<StoryModel> _stories = [];
  int _storyIndex = 0;
  bool _loading = true;

  late final AnimationController _progress;
  VideoPlayerController? _videoController;
  final AudioPlayer _musicPlayer = AudioPlayer();
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    _authorIndex = widget.authorIds.indexOf(widget.startAuthorId).clamp(0, widget.authorIds.length - 1);
    _progress = AnimationController(vsync: this)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _advance();
      });
    _loadAuthorStories();
  }

  @override
  void dispose() {
    _progress.dispose();
    _videoController?.dispose();
    _musicPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadAuthorStories() async {
    setState(() => _loading = true);
    final authorId = widget.authorIds[_authorIndex];
    final stories = await StoryRepository().storiesFor(authorId);
    if (!mounted) return;
    setState(() {
      _stories = stories;
      _storyIndex = 0;
      _loading = false;
    });
    if (stories.isEmpty) {
      _goToNextAuthor();
    } else {
      _playCurrent();
    }
  }

  Future<void> _playCurrent() async {
    _progress.stop();
    _videoController?.dispose();
    _videoController = null;
    await _musicPlayer.stop();
    if (_stories.isEmpty) return;

    final story = _stories[_storyIndex];
    unawaited(StoryRepository().markViewed(story.id));

    if (story.hasMusic) {
      unawaited(_musicPlayer.play(UrlSource(story.audioUrl!)));
    }

    if (story.isVideo) {
      final controller = VideoPlayerController.networkUrl(Uri.parse(story.mediaUrl));
      try {
        await controller.initialize().timeout(const Duration(seconds: 12));
        if (!mounted) return;
        // A music track replaces the video's own sound by default (set at
        // creation time) — otherwise the video plays with its own audio,
        // same as any camera recording.
        await controller.setVolume(story.muteOriginalAudio ? 0 : 1);
        setState(() => _videoController = controller);
        _progress.duration = controller.value.duration;
        controller.play();
      } catch (_) {
        _progress.duration = _imageDuration;
      }
    } else {
      _progress.duration = _imageDuration;
    }
    _progress
      ..reset()
      ..forward();
  }

  void _advance() {
    if (_storyIndex < _stories.length - 1) {
      setState(() => _storyIndex++);
      _playCurrent();
    } else {
      _goToNextAuthor();
    }
  }

  void _rewind() {
    if (_storyIndex > 0) {
      setState(() => _storyIndex--);
      _playCurrent();
    } else {
      _goToPreviousAuthor();
    }
  }

  void _goToNextAuthor() {
    if (_authorIndex < widget.authorIds.length - 1) {
      setState(() => _authorIndex++);
      _loadAuthorStories();
    } else if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _goToPreviousAuthor() {
    if (_authorIndex > 0) {
      setState(() => _authorIndex--);
      _loadAuthorStories();
    }
  }

  void _togglePause() {
    setState(() => _paused = !_paused);
    if (_paused) {
      _progress.stop();
      _videoController?.pause();
      _musicPlayer.pause();
    } else {
      _progress.forward();
      _videoController?.play();
      _musicPlayer.resume();
    }
  }

  @override
  Widget build(BuildContext context) {
    final story = _stories.isNotEmpty ? _stories[_storyIndex] : null;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: GestureDetector(
          onLongPressStart: (_) => _togglePause(),
          onLongPressEnd: (_) => _togglePause(),
          onTapUp: (details) {
            final width = MediaQuery.of(context).size.width;
            if (details.globalPosition.dx < width / 3) {
              _rewind();
            } else {
              _advance();
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_loading)
                const Center(child: CircularProgressIndicator(color: Colors.white))
              else if (story != null)
                Center(
                  child: story.isVideo
                      ? (_videoController?.value.isInitialized == true
                          ? AspectRatio(aspectRatio: _videoController!.value.aspectRatio, child: VideoPlayer(_videoController!))
                          : const CircularProgressIndicator(color: Colors.white))
                      : Image.network(story.mediaUrl, fit: BoxFit.contain),
                ),
              Positioned(
                top: 8,
                left: 8,
                right: 8,
                child: Row(
                  children: [
                    for (int i = 0; i < _stories.length; i++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              minHeight: 3,
                              backgroundColor: Colors.white.withValues(alpha: 0.3),
                              value: i < _storyIndex
                                  ? 1
                                  : i == _storyIndex
                                      ? _progress.value
                                      : 0,
                              valueColor: const AlwaysStoppedAnimation(Colors.white),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Positioned(
                top: 20,
                left: 12,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              if (story != null && story.hasMusic)
                Positioned(
                  bottom: 20,
                  left: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(20)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.music_note, color: Colors.white, size: 14),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            story.audioTitle ?? 'Music',
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
