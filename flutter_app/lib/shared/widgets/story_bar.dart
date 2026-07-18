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
    String? createdStoryId;
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
      createdStoryId = storyId;
      final String url;
      String? thumbnailUrl;
      if (mediaType == 'video') {
        final prepared = await upload.preparePostVideo(picked);
        url = await upload.uploadStoryVideo(userId: uid, storyId: storyId, video: prepared);
      } else {
        final prepared = await upload.preparePostImage(picked);
        final uploaded = await upload.uploadStoryImage(userId: uid, storyId: storyId, image: prepared);
        url = uploaded.originalUrl;
        thumbnailUrl = uploaded.thumbnailUrl;
      }
      await SupabaseConfig.client.from('stories').update({
        'media_url': url,
        if (thumbnailUrl != null) 'thumbnail_url': thumbnailUrl,
      }).eq('id', storyId);
      createdStoryId = null; // fully committed, nothing left to roll back
      _refresh();
    } catch (e) {
      // The story row (with a placeholder media_url) may have already been
      // inserted before the media upload or the follow-up update failed.
      // Leaving it behind would show up as a broken, empty story in the
      // viewer — so clean it up rather than orphaning it.
      if (createdStoryId != null) {
        try {
          await StoryRepository().deleteStory(createdStoryId);
        } catch (_) {
          // Best-effort cleanup; the original error is what we report below.
        }
      }
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
      height: 124,
      child: FutureBuilder<List<StoryFeedEntry>>(
        future: _future,
        builder: (context, snapshot) {
          final entries = snapshot.data ?? const [];
          final hasOwnStory = entries.any((e) => e.authorId == uid);
          final others = entries.where((e) => e.authorId != uid).toList();
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            itemCount: others.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              if (i == 0) {
                return _AddStoryTile(uploading: _uploading, hasOwnStory: hasOwnStory, onTap: _addStory);
              }
              final entry = others[i - 1];
              return _StoryTile(
                entry: entry,
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => StoryViewerScreen(authorIds: entries.map((e) => e.authorId).toList(), startAuthorId: entry.authorId)),
                  );
                  _refresh();
                },
              );
            },
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
        width: 72,
        height: 108,
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: 72,
                height: 108,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                alignment: Alignment.center,
                child: uploading ? const CircularProgressIndicator(strokeWidth: 2) : Icon(Icons.add_a_photo_outlined, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
            if (!uploading)
              Positioned(
                right: 6,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                  child: const Icon(Icons.add, size: 14, color: Colors.white),
                ),
              ),
            Positioned(
              left: 4,
              right: 4,
              bottom: 4,
              child: Text(
                hasOwnStory ? 'Your story' : 'Add story',
                style: Theme.of(context).textTheme.labelSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
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
    final imageUrl = (entry.latestThumbnailUrl != null && entry.latestThumbnailUrl!.isNotEmpty)
        ? entry.latestThumbnailUrl
        : entry.authorAvatarUrl;
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72,
        height: 108,
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: entry.hasUnseen
              ? const LinearGradient(colors: [Color(0xFFF58529), Color(0xFFDD2A7B), Color(0xFF8134AF)], begin: Alignment.topLeft, end: Alignment.bottomRight)
              : null,
          color: entry.hasUnseen ? null : Theme.of(context).colorScheme.outlineVariant,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11.5),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: hasImage
                    ? Image.network(imageUrl, fit: BoxFit.cover)
                    : Icon(Icons.person, size: 32, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [Colors.transparent, Colors.black87], begin: Alignment.topCenter, end: Alignment.bottomCenter),
                  ),
                  child: Text(
                    entry.authorUsername,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
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
