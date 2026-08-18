import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/supabase_client.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/reusables.dart' show ProfileAvatar;
import '../data/repositories.dart';
import 'page_post_media_repository.dart';
import 'pages_theme.dart';

/// Create or edit a Page post. Rich media is deliberately Page-local so the
/// normal Gather composer/media stack remains untouched.
class PageContentComposerScreen extends StatefulWidget {
  const PageContentComposerScreen({super.key, required this.pageId, this.existingPost});

  final String pageId;
  final Map<String, dynamic>? existingPost;

  @override
  State<PageContentComposerScreen> createState() => _PageContentComposerScreenState();
}

class _PageContentComposerScreenState extends State<PageContentComposerScreen> {
  final _repo = PageRepository();
  final _profileRepo = ProfileRepository();
  final _mediaRepo = PagePostMediaRepository();
  final _contentController = TextEditingController();
  final Map<String, String> _mentionedUsers = {};
  final List<PlatformFile> _pickedFiles = [];

  String _postType = 'post';
  DateTime? _scheduledAt;
  List<Map<String, dynamic>> _existingMedia = [];
  Map<String, dynamic>? _selectedEvent;
  bool _saving = false;

  bool get _isEditing => widget.existingPost != null;

  @override
  void initState() {
    super.initState();
    final post = widget.existingPost;
    if (post == null) return;

    _contentController.text = post['content'] as String? ?? '';
    _postType = post['post_type'] as String? ?? 'post';
    final media = post['media'];
    if (media is List) {
      _existingMedia = media.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
      for (final item in _existingMedia) {
        if (item['type'] == 'event') _selectedEvent = item;
      }
    }
    final scheduledAt = post['scheduled_at'] as String?;
    if (scheduledAt != null) _scheduledAt = DateTime.tryParse(scheduledAt);

    final mentionIds = post['mention_ids'];
    if (mentionIds is List && mentionIds.isNotEmpty) {
      _profileRepo.usersByIds(mentionIds.cast<String>()).then((users) {
        if (!mounted) return;
        setState(() {
          for (final user in users) {
            final username = user['username'] as String?;
            final id = user['id'] as String?;
            if (username != null && id != null) _mentionedUsers[username] = id;
          }
        });
      }).catchError((_) {});
    }
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: true,
        type: FileType.any,
      );
      if (result == null || result.files.isEmpty) return;

      final accepted = <PlatformFile>[];
      final rejected = <String>[];
      for (final file in result.files) {
        final mime = _mimeType(file);
        if (!_isSupportedMime(mime)) {
          rejected.add(file.name);
          continue;
        }
        if (file.bytes == null) {
          rejected.add(file.name);
          continue;
        }
        if (file.bytes!.length > PagePostMediaRepository.maxBytes) {
          rejected.add(file.name);
          continue;
        }
        accepted.add(file);
      }

      if (mounted && rejected.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${rejected.length} file(s) were not added. Use images, videos, PDF, DOC, DOCX or TXT under 25 MB.')),
        );
      }
      if (accepted.isNotEmpty) setState(() => _pickedFiles.addAll(accepted));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not select the files.')));
    }
  }

  String _mimeType(PlatformFile file) {
    final supplied = file.extension == null ? null : file.extension!.toLowerCase();
    final ext = supplied ?? file.name.split('.').last.toLowerCase();
    const types = <String, String>{
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'webp': 'image/webp',
      'gif': 'image/gif',
      'mp4': 'video/mp4',
      'mov': 'video/quicktime',
      'webm': 'video/webm',
      'pdf': 'application/pdf',
      'doc': 'application/msword',
      'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'txt': 'text/plain',
    };
    return types[ext] ?? 'application/octet-stream';
  }

  bool _isSupportedMime(String mime) => const {
        'image/jpeg',
        'image/png',
        'image/webp',
        'image/gif',
        'video/mp4',
        'video/quicktime',
        'video/webm',
        'application/pdf',
        'application/msword',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'text/plain',
      }.contains(mime);

  String _mediaType(String mime) {
    if (mime.startsWith('image/')) return 'image';
    if (mime.startsWith('video/')) return 'video';
    return 'document';
  }

  Future<void> _pickEvent() async {
    try {
      final events = await _repo.listPageEvents(widget.pageId);
      if (!mounted) return;
      final selected = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) {
          if (events.isEmpty) return const SafeArea(child: Padding(padding: EdgeInsets.all(24), child: Text('No Page events are available. Create an event first.')));
          return SafeArea(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: events.length,
              itemBuilder: (_, index) {
                final event = events[index];
                final start = DateTime.tryParse(event['start_time']?.toString() ?? '');
                return ListTile(
                  leading: const Icon(Icons.event_outlined),
                  title: Text(event['title']?.toString() ?? 'Event'),
                  subtitle: Text(start == null ? 'Page event' : _formatEventDate(start)),
                  onTap: () => Navigator.pop(sheetContext, event),
                );
              },
            ),
          );
        },
      );
      if (selected != null && mounted) setState(() => _selectedEvent = selected);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not load Page events.')));
    }
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
            }).catchError((_) {
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
                    decoration: const InputDecoration(hintText: 'Search by username', prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
                    onChanged: (q) async {
                      loading = true;
                      setSheetState(() {});
                      try {
                        results = q.trim().isEmpty ? await _profileRepo.followingUsers(uid) : await _profileRepo.searchUsersByUsername(q);
                      } finally {
                        loading = false;
                        setSheetState(() {});
                      }
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
                                itemBuilder: (_, i) {
                                  final person = results[i];
                                  final id = person['id'] as String;
                                  final name = person['username'] as String? ?? 'Unknown';
                                  return CheckboxListTile(
                                    value: selected.containsKey(name),
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
                      child: SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(sheetContext), child: Text(selected.isEmpty ? 'Done' : 'Tag ${selected.length}'))),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (mounted) setState(() { _mentionedUsers..clear()..addAll(selected); });
  }

  Future<void> _save(String status) async {
    final text = _contentController.text.trim();
    if (text.isEmpty && _pickedFiles.isEmpty && _existingMedia.isEmpty && _selectedEvent == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add text, media, or a Page event first.')));
      return;
    }
    if (status == 'scheduled' && _scheduledAt == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Choose a date and time to schedule this post.')));
      return;
    }

    setState(() => _saving = true);
    final uploadedPaths = <String>[];
    var createdPostId = '';
    try {
      Map<String, dynamic> post;
      if (_isEditing) {
        post = widget.existingPost!;
      } else {
        post = await _repo.createPagePost({
          'page_id': widget.pageId,
          'author_id': SupabaseConfig.currentUserId,
          'post_type': _postType,
          'content': text,
          'status': 'draft',
        });
      }
      createdPostId = post['id'] as String;

      final media = <Map<String, dynamic>>[];
      if (_existingMedia.isNotEmpty && _pickedFiles.isEmpty) media.addAll(_existingMedia);
      if (_selectedEvent != null) {
        media.removeWhere((item) => item['type'] == 'event');
        media.add({
          'type': 'event',
          'event_id': _selectedEvent!['id'],
          'title': _selectedEvent!['title'],
          'cover_url': _selectedEvent!['cover_url'],
          'start_time': _selectedEvent!['start_time'],
          'end_time': _selectedEvent!['end_time'],
          'location': _selectedEvent!['location'],
        });
      }

      for (final file in _pickedFiles) {
        final bytes = file.bytes;
        if (bytes == null) throw const PagePostMediaException('Could not read one of the selected files.');
        final mime = _mimeType(file);
        final path = await _mediaRepo.upload(
          pageId: widget.pageId,
          postId: createdPostId,
          fileName: file.name,
          mimeType: mime,
          bytes: bytes,
        );
        uploadedPaths.add(path);
        media.add({
          'type': _mediaType(mime),
          'url': _mediaRepo.publicUrl(path),
          'path': path,
          'name': file.name,
          'mime_type': mime,
          'size': bytes.length,
        });
      }

      await _repo.updatePagePost(createdPostId, {
        'post_type': _postType,
        'content': text,
        'media': media,
        'status': status,
        'scheduled_at': status == 'scheduled' ? _scheduledAt!.toIso8601String() : null,
        'mention_ids': _mentionedUsers.values.toList(),
      });

      if (mounted) Navigator.of(context).pop(true);
    } on PagePostMediaException catch (e) {
      await _cleanupFailedSave(createdPostId, uploadedPaths);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      await _cleanupFailedSave(createdPostId, uploadedPaths);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save the Page post. Please try again.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _cleanupFailedSave(String postId, List<String> paths) async {
    try {
      await _mediaRepo.deletePaths(paths);
      if (!_isEditing && postId.isNotEmpty) await _repo.deletePagePost(postId);
    } catch (_) {
      // The user already received the failed-operation message. A later
      // Page media cleanup pass can remove any orphaned objects.
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
          const SizedBox(height: PageTokens.spaceMd),
          OutlinedButton.icon(
            onPressed: _saving ? null : _pickFiles,
            icon: const Icon(Icons.attach_file),
            label: const Text('Add photos, videos or files'),
          ),
          if (_pickedFiles.isNotEmpty) ...[
            const SizedBox(height: 8),
            ..._pickedFiles.map((file) => ListTile(
                  dense: true,
                  leading: Icon(_fileIcon(_mimeType(file))),
                  title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(_formatBytes(file.bytes?.length ?? 0)),
                  trailing: IconButton(icon: const Icon(Icons.close), onPressed: _saving ? null : () => setState(() => _pickedFiles.remove(file))),
                )),
          ],
          if (_existingMedia.isNotEmpty && _pickedFiles.isEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(border: Border.all(color: Theme.of(context).dividerColor), borderRadius: BorderRadius.circular(PageTokens.radiusMd)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Existing attachments', style: TextStyle(fontWeight: FontWeight.w600)),
                ..._existingMedia.where((m) => m['type'] != 'event').map((m) => ListTile(dense: true, leading: Icon(_fileIcon(m['mime_type']?.toString() ?? '')), title: Text(m['name']?.toString() ?? m['type']?.toString() ?? 'Attachment'), subtitle: Text(m['mime_type']?.toString() ?? ''))),
                TextButton.icon(onPressed: _saving ? null : () => setState(() => _existingMedia.clear()), icon: const Icon(Icons.delete_outline), label: const Text('Remove existing attachments')),
              ]),
            ),
          ],
          const SizedBox(height: PageTokens.spaceMd),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: Text(_selectedEvent == null ? 'Attach existing Page event' : 'Event: ${_selectedEvent!['title']}'),
            subtitle: const Text('Use an event already managed by this Page.'),
            trailing: _selectedEvent == null ? null : IconButton(icon: const Icon(Icons.close), onPressed: _saving ? null : () => setState(() => _selectedEvent = null)),
            onTap: _saving ? null : _pickEvent,
          ),
          const SizedBox(height: PageTokens.spaceMd),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule_outlined),
            title: Text(_scheduledAt == null ? 'Schedule for later (optional)' : _formatScheduled(_scheduledAt!)),
            trailing: _scheduledAt == null ? null : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _scheduledAt = null)),
            onTap: _saving ? null : _pickScheduleTime,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.alternate_email),
            title: Text(_mentionedUsers.isEmpty ? 'Tag people' : 'Tagged ${_mentionedUsers.length}'),
            onTap: _saving ? null : _pickMentions,
          ),
          if (_mentionedUsers.isNotEmpty)
            Wrap(spacing: 6, runSpacing: 6, children: _mentionedUsers.keys.map((name) => Chip(label: Text('@$name'), onDeleted: _saving ? null : () => setState(() => _mentionedUsers.remove(name)))).toList()),
          const SizedBox(height: PageTokens.spaceXl),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: _saving ? null : () => _save('draft'), style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)), child: const Text('Save draft'))),
            const SizedBox(width: 8),
            Expanded(child: FilledButton(
              onPressed: _saving ? null : () => _save(_scheduledAt != null ? 'scheduled' : 'published'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.brandTeal, foregroundColor: AppColors.onBrandTeal, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PageTokens.radiusPill))),
              child: _saving ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onBrandTeal)) : Text(_scheduledAt != null ? 'Schedule' : 'Publish'),
            )),
          ]),
        ],
      ),
    );
  }
}

IconData _fileIcon(String mime) {
  if (mime.startsWith('image/')) return Icons.image_outlined;
  if (mime.startsWith('video/')) return Icons.videocam_outlined;
  if (mime == 'application/pdf') return Icons.picture_as_pdf_outlined;
  return Icons.description_outlined;
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _formatScheduled(DateTime dateTime) {
  final local = dateTime.toLocal();
  final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final ampm = local.hour < 12 ? 'AM' : 'PM';
  final minute = local.minute.toString().padLeft(2, '0');
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${months[local.month - 1]} ${local.day}, ${local.year} · $hour12:$minute $ampm';
}

String _formatEventDate(DateTime dateTime) => _formatScheduled(dateTime);
