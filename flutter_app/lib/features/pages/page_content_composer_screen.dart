import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/supabase_client.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/profile_view.dart' show PickedImagePreview;
import '../../shared/widgets/reusables.dart' show ProfileAvatar;
import '../data/repositories.dart';
import 'pages_theme.dart';

/// Create or edit a Page post (Step 7). Handles every `post_type` the
/// schema supports (post/photo/video/poll/offer/job/article) with one
/// shared form — type-specific structure (e.g. real poll options, video
/// upload) is a future enhancement; for now `poll`/`video` are content-only
/// types the team can still draft/schedule/pin like any other post, and
/// `media` stores whatever image was attached. Draft/Schedule/Publish are
/// three distinct explicit actions rather than one "Save" button, since
/// each maps to a different `page_posts.status`.
class PageContentComposerScreen extends StatefulWidget {
  const PageContentComposerScreen({super.key, required this.pageId, this.existingPost});

  final String pageId;
  /// Non-null when editing an already-created post.
  final Map<String, dynamic>? existingPost;

  @override
  State<PageContentComposerScreen> createState() => _PageContentComposerScreenState();
}

class _PageContentComposerScreenState extends State<PageContentComposerScreen> {
  final _repo = PageRepository();
  final _profileRepo = ProfileRepository();
  final _contentController = TextEditingController();
  String _postType = 'post';
  XFile? _pickedImage;
  String? _existingImageUrl;
  DateTime? _scheduledAt;
  bool _saving = false;
  /// username -> user id, mirrors create_post_screen.dart's _taggedFriends
  /// picker. Populates page_posts.mention_ids on save, which
  /// trg_notify_page_post_mentions (migration 087) turns into 'mention'
  /// notifications once the post publishes.
  final Map<String, String> _mentionedUsers = {};

  bool get _isEditing => widget.existingPost != null;

  @override
  void initState() {
    super.initState();
    final post = widget.existingPost;
    if (post != null) {
      _contentController.text = post['content'] as String? ?? '';
      _postType = post['post_type'] as String? ?? 'post';
      final media = post['media'];
      if (media is List && media.isNotEmpty && media.first is Map) {
        _existingImageUrl = (media.first as Map)['url'] as String?;
      }
      final scheduledAt = post['scheduled_at'] as String?;
      if (scheduledAt != null) _scheduledAt = DateTime.parse(scheduledAt);

      final mentionIds = post['mention_ids'];
      if (mentionIds is List && mentionIds.isNotEmpty) {
        _profileRepo.usersByIds(mentionIds.cast<String>()).then((users) {
          if (!mounted) return;
          setState(() {
            for (final u in users) {
              _mentionedUsers[u['username'] as String? ?? 'unknown'] = u['id'] as String;
            }
          });
        }).catchError((_) {});
      }
    }
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked != null) setState(() => _pickedImage = picked);
  }

  Future<void> _pickScheduleTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _scheduledAt ?? now.add(const Duration(hours: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_scheduledAt ?? now.add(const Duration(hours: 1))),
    );
    if (time == null) return;
    setState(() => _scheduledAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _pickMentions() async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) return;
    final selected = Map<String, String>.from(_mentionedUsers);
    var results = <Map<String, dynamic>>[];
    var loading = true;
    var loadedDefault = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          if (!loadedDefault) {
            loadedDefault = true;
            _profileRepo.followingUsers(uid).then((people) {
              results = people;
              loading = false;
              setSheetState(() {});
            });
          }
          return DraggableScrollableSheet(
            initialChildSize: 0.7,
            minChildSize: 0.4,
            maxChildSize: 0.9,
            expand: false,
            builder: (context, scrollController) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tag people', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  TextField(
                    autofocus: false,
                    decoration: const InputDecoration(
                      hintText: 'Search by username',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (q) async {
                      loading = true;
                      setSheetState(() {});
                      final found = q.trim().isEmpty ? await _profileRepo.followingUsers(uid) : await _profileRepo.searchUsersByUsername(q);
                      results = found;
                      loading = false;
                      setSheetState(() {});
                    },
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: loading
                        ? const Center(child: CircularProgressIndicator())
                        : results.isEmpty
                            ? const Center(child: Text('No one found'))
                            : ListView.builder(
                                controller: scrollController,
                                itemCount: results.length,
                                itemBuilder: (context, i) {
                                  final person = results[i];
                                  final id = person['id'] as String;
                                  final name = person['username'] as String? ?? 'Unknown';
                                  final isSelected = selected.containsKey(name);
                                  return CheckboxListTile(
                                    value: isSelected,
                                    secondary: ProfileAvatar(url: person['profile_photo_url'] as String?, radius: 16),
                                    title: Text(name),
                                    onChanged: (checked) {
                                      setSheetState(() {
                                        if (checked == true) {
                                          selected[name] = id;
                                        } else {
                                          selected.remove(name);
                                        }
                                      });
                                    },
                                  );
                                },
                              ),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          child: Text(selected.isEmpty ? 'Done' : 'Tag ${selected.length}'),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (mounted) {
      setState(() {
        _mentionedUsers
          ..clear()
          ..addAll(selected);
      });
    }
  }

  Future<void> _save(String status) async {
    if (_contentController.text.trim().isEmpty && _pickedImage == null && _existingImageUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add some text or an image first.')));
      return;
    }
    if (status == 'scheduled' && _scheduledAt == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Choose a date and time to schedule this post.')));
      return;
    }
    setState(() => _saving = true);
    try {
      Map<String, dynamic> post;
      if (_isEditing) {
        post = widget.existingPost!;
      } else {
        post = await _repo.createPagePost({
          'page_id': widget.pageId,
          'author_id': SupabaseConfig.currentUserId,
          'post_type': _postType,
          'content': _contentController.text.trim(),
          'status': 'draft',
        });
      }
      final postId = post['id'] as String;

      var mediaUrl = _existingImageUrl;
      if (_pickedImage != null) {
        final uploaded = await _repo.uploadPagePostImage(widget.pageId, postId, _pickedImage!);
        mediaUrl = uploaded.originalUrl;
      }

      await _repo.updatePagePost(postId, {
        'post_type': _postType,
        'content': _contentController.text.trim(),
        'media': mediaUrl != null ? [{'type': 'image', 'url': mediaUrl}] : [],
        'status': status,
        'scheduled_at': status == 'scheduled' ? _scheduledAt!.toIso8601String() : null,
        'mention_ids': _mentionedUsers.values.toList(),
      });

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit Page post' : 'New Page post', style: const TextStyle(fontWeight: FontWeight.w700))),
      body: ListView(
        padding: const EdgeInsets.all(PageTokens.spaceLg),
        children: [
          Text('Type', style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in kPagePostTypes.entries)
                ChoiceChip(
                  avatar: Icon(kPagePostTypeIcons[entry.key], size: 16),
                  label: Text(entry.value),
                  selected: _postType == entry.key,
                  onSelected: (_) => setState(() => _postType = entry.key),
                ),
            ],
          ),
          const SizedBox(height: PageTokens.spaceLg),
          TextField(
            controller: _contentController,
            maxLines: 6,
            minLines: 3,
            decoration: pageFieldDecoration(context, labelText: 'What do you want to share?'),
          ),
          const SizedBox(height: PageTokens.spaceLg),
          if (_pickedImage != null || _existingImageUrl != null)
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(PageTokens.radiusMd),
                  child: SizedBox(
                    height: 180,
                    width: double.infinity,
                    child: _pickedImage != null
                        ? PickedImagePreview(bytesFuture: _pickedImage!.readAsBytes())
                        : Image.network(_existingImageUrl!, fit: BoxFit.cover),
                  ),
                ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: CircleAvatar(
                    backgroundColor: Colors.black54,
                    radius: 16,
                    child: IconButton(
                      icon: const Icon(Icons.close, size: 16, color: Colors.white),
                      onPressed: () => setState(() {
                        _pickedImage = null;
                        _existingImageUrl = null;
                      }),
                    ),
                  ),
                ),
              ],
            )
          else
            OutlinedButton.icon(onPressed: _pickImage, icon: const Icon(Icons.image_outlined), label: const Text('Add image')),
          const SizedBox(height: PageTokens.spaceLg),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule_outlined),
            title: Text(_scheduledAt == null ? 'Schedule for later (optional)' : _formatScheduled(_scheduledAt!)),
            trailing: _scheduledAt != null
                ? IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _scheduledAt = null))
                : null,
            onTap: _pickScheduleTime,
          ),
          const SizedBox(height: PageTokens.spaceMd),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.alternate_email),
            title: Text(_mentionedUsers.isEmpty ? 'Tag people' : 'Tagged ${_mentionedUsers.length}'),
            onTap: _pickMentions,
          ),
          if (_mentionedUsers.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _mentionedUsers.keys
                  .map((name) => Chip(
                        label: Text('@$name'),
                        onDeleted: () => setState(() => _mentionedUsers.remove(name)),
                      ))
                  .toList(),
            ),
          const SizedBox(height: PageTokens.spaceXl),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => _save('draft'),
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: const Text('Save draft'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: _saving ? null : () => _save(_scheduledAt != null ? 'scheduled' : 'published'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brandTeal,
                    foregroundColor: AppColors.onBrandTeal,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PageTokens.radiusPill)),
                  ),
                  child: _saving
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onBrandTeal))
                      : Text(_scheduledAt != null ? 'Schedule' : 'Publish'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _formatScheduled(DateTime dateTime) {
  final local = dateTime.toLocal();
  final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final ampm = local.hour < 12 ? 'AM' : 'PM';
  final minute = local.minute.toString().padLeft(2, '0');
  return '${_months[local.month - 1]} ${local.day}, ${local.year} · $hour12:$minute $ampm';
}
