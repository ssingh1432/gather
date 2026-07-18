import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/supabase_client.dart';
import '../models/models.dart';
import '../services/media_upload_service.dart';
import '../../features/data/repositories.dart';
import 'reusables.dart';
import 'story_viewer_screen.dart';

class StoryBar extends StatefulWidget {
  const StoryBar({super.key});

  @override
  State<StoryBar> createState() => _StoryBarState();
}

class _StoryBarState extends State<StoryBar> {
  late Future<List<StoryFeedEntry>> _future = _load();
  bool _uploading = false;

  Future<List<StoryFeedEntry>> _load() async {
    final uid = SupabaseConfig.maybeClient?.auth.currentUser?.id;
    if (uid == null) return const [];
    return StoryRepository().storyFeed(uid);
  }

  void _refresh() => setState(() => _future = _load());

  Future<void> _addStory() async {
    final mediaType = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(children: [
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Photo'), onTap: () => Navigator.pop(context, 'image')),
          ListTile(leading: const Icon(Icons.videocam_outlined), title: const Text('Video'), onTap: () => Navigator.pop(context, 'video')),
        ]),
      ),
    );
    if (mediaType == null || !mounted) return;

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(children: [
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Camera'), onTap: () => Navigator.pop(context, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Gallery'), onTap: () => Navigator.pop(context, ImageSource.gallery)),
        ]),
      ),
    );
    if (source == null || !mounted) return;

    final picker = ImagePicker();
    final picked = mediaType == 'video'
        ? await picker.pickVideo(source: source, maxDuration: const Duration(seconds: 60))
        : await picker.pickImage(source: source, imageQuality: 85);
    if (picked == null || !mounted) return;

    // Music is optional for either photo or video stories.
    final track = await showModalBottomSheet<StoryAudioTrack?>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _MusicPickerSheet(),
    );
    if (!mounted) return;

    final uid = SupabaseConfig.maybeClient?.auth.currentUser?.id;
    if (uid == null) return;

    setState(() => _uploading = true);
    try {
      final upload = MediaUploadService();
      final story = await StoryRepository().createStory(
        mediaUrl: '',
        mediaType: mediaType,
        audioTrackId: track?.id,
        audioUrl: track?.audioUrl,
        audioTitle: track != null ? [track.title, if (track.artist != null) track.artist].join(' · ') : null,
        // A music track replaces a video's own sound by default, matching
        // Instagram/TikTok — the person can still remove the track and
        // repost if they'd rather keep the original audio.
        muteOriginalAudio: track != null && mediaType == 'video',
      );
      final storyId = story['id'] as String;
      final String url;
      if (mediaType == 'video') {
        final prepared = await upload.preparePostVideo(picked);
        url = await upload.uploadStoryVideo(userId: uid, storyId: storyId, video: prepared);
      } else {
        final prepared = await upload.preparePostImage(picked);
        url = await upload.uploadStoryImage(userId: uid, storyId: storyId, image: prepared);
      }
      await SupabaseConfig.client.from('stories').update({'media_url': url}).eq('id', storyId);
      _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not post story: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = SupabaseConfig.maybeClient?.auth.currentUser?.id;
    if (uid == null) return const SizedBox.shrink();

    return SizedBox(
      height: 96,
      child: FutureBuilder<List<StoryFeedEntry>>(
        future: _future,
        builder: (context, snapshot) {
          final entries = snapshot.data ?? const [];
          final hasOwnStory = entries.any((e) => e.authorId == uid);
          return ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            children: [
              _AddStoryTile(uploading: _uploading, hasOwnStory: hasOwnStory, onTap: _addStory),
              for (final entry in entries.where((e) => e.authorId != uid))
                _StoryTile(
                  entry: entry,
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => StoryViewerScreen(authorIds: entries.map((e) => e.authorId).toList(), startAuthorId: entry.authorId)),
                    );
                    _refresh();
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}

class _AddStoryTile extends StatelessWidget {
  const _AddStoryTile({required this.uploading, required this.hasOwnStory, required this.onTap});
  final bool uploading;
  final bool hasOwnStory;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: uploading ? null : onTap,
      child: SizedBox(
        width: 68,
        child: Column(
          children: [
            SizedBox(
              width: 60,
              height: 60,
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: uploading ? const CircularProgressIndicator(strokeWidth: 2) : const Icon(Icons.add_a_photo_outlined),
                  ),
                  if (!uploading)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                        child: const Icon(Icons.add, size: 14, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(hasOwnStory ? 'Your story' : 'Add story', style: Theme.of(context).textTheme.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class _StoryTile extends StatelessWidget {
  const _StoryTile({required this.entry, required this.onTap});
  final StoryFeedEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 68,
        child: Column(
          children: [
            Container(
              width: 60,
              height: 60,
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: entry.hasUnseen
                    ? const LinearGradient(colors: [Color(0xFFF58529), Color(0xFFDD2A7B), Color(0xFF8134AF)], begin: Alignment.topLeft, end: Alignment.bottomRight)
                    : null,
                color: entry.hasUnseen ? null : Theme.of(context).colorScheme.outlineVariant,
              ),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  backgroundImage: entry.authorAvatarUrl != null && entry.authorAvatarUrl!.isNotEmpty ? NetworkImage(entry.authorAvatarUrl!) : null,
                  child: entry.authorAvatarUrl == null || entry.authorAvatarUrl!.isEmpty ? const Icon(Icons.person) : null,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(entry.authorUsername, style: Theme.of(context).textTheme.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

/// Optional "add music" step, shown after picking a story's media.
/// Empty by default — populate story_audio_tracks with tracks you have
/// the rights to use.
class _MusicPickerSheet extends StatefulWidget {
  @override
  State<_MusicPickerSheet> createState() => _MusicPickerSheetState();
}

class _MusicPickerSheetState extends State<_MusicPickerSheet> {
  final Future<List<StoryAudioTrack>> _future = StoryRepository().audioTracks();
  final _player = AudioPlayer();
  String? _previewingId;

  @override
  void dispose() {
    _player.stop();
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePreview(StoryAudioTrack track) async {
    if (_previewingId == track.id) {
      await _player.stop();
      setState(() => _previewingId = null);
    } else {
      await _player.stop();
      await _player.play(UrlSource(track.audioUrl));
      setState(() => _previewingId = track.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Add music', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('Skip')),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<StoryAudioTrack>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final tracks = snapshot.data ?? const [];
                  if (tracks.isEmpty) {
                    return const EmptyState(icon: Icons.music_off_outlined, title: 'No tracks yet', message: 'Post without music for now.');
                  }
                  return ListView.builder(
                    itemCount: tracks.length,
                    itemBuilder: (context, i) {
                      final track = tracks[i];
                      final previewing = _previewingId == track.id;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage: track.coverUrl != null ? NetworkImage(track.coverUrl!) : null,
                          child: track.coverUrl == null ? const Icon(Icons.music_note) : null,
                        ),
                        title: Text(track.title),
                        subtitle: track.artist != null ? Text(track.artist!) : null,
                        trailing: IconButton(
                          icon: Icon(previewing ? Icons.stop_circle_outlined : Icons.play_circle_outline),
                          onPressed: () => _togglePreview(track),
                        ),
                        onTap: () {
                          _player.stop();
                          Navigator.pop(context, track);
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
