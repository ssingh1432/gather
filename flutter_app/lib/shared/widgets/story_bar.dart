import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/supabase_client.dart';
import '../models/models.dart';
import '../services/media_upload_service.dart';
import '../../features/data/repositories.dart';
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
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(children: [
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Camera'), onTap: () => Navigator.pop(context, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Gallery'), onTap: () => Navigator.pop(context, ImageSource.gallery)),
        ]),
      ),
    );
    if (source == null) return;

    final picked = await ImagePicker().pickImage(source: source, imageQuality: 85);
    if (picked == null) return;

    final uid = SupabaseConfig.maybeClient?.auth.currentUser?.id;
    if (uid == null) return;

    setState(() => _uploading = true);
    try {
      final upload = MediaUploadService();
      final prepared = await upload.preparePostImage(picked);
      final story = await StoryRepository().createStory(mediaUrl: '', mediaType: 'image');
      final storyId = story['id'] as String;
      final url = await upload.uploadStoryImage(userId: uid, storyId: storyId, image: prepared);
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
