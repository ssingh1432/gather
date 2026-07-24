import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/models/models.dart';
import '../../shared/widgets/format_toolbar.dart';
import '../data/repositories.dart';

/// Lets a post's author edit its text, tags, and visibility. Media isn't
/// editable yet (Step 11 in the CMS doc calls that out as "add/remove
/// media" — left for a follow-up since it needs the same upload plumbing
/// as post creation). Every save is snapshotted to post_edit_history.
class EditPostScreen extends StatefulWidget {
  const EditPostScreen({super.key, required this.postId});
  final String postId;

  @override
  State<EditPostScreen> createState() => _EditPostScreenState();
}

class _EditPostScreenState extends State<EditPostScreen> {
  static const _maxLength = 5000;
  static const _visibilityOptions = {
    'public': ('Public', Icons.public),
    'friends': ('Friends', Icons.people_alt_outlined),
    'only_me': ('Only me', Icons.lock_outline),
  };

  final _text = TextEditingController();
  final _tags = TextEditingController();
  String _visibility = 'public';
  bool _loading = true;
  bool _saving = false;
  String? _error;
  PostModel? _post;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    _tags.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final post = await FeedRepository().getPost(widget.postId);
      if (!mounted) return;
      setState(() {
        _post = post;
        _text.text = post.textContent;
        _tags.text = post.tags.join(', ');
        _visibility = post.visibility;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() { _error = 'Could not load this post.'; _loading = false; });
    }
  }

  List<String> get _parsedTags => _tags.text
      .split(RegExp(r'[,\s]+'))
      .map((t) => t.trim().replaceFirst(RegExp(r'^#'), ''))
      .where((t) => t.isNotEmpty)
      .toSet()
      .toList();

  Future<void> _save() async {
    if (_text.text.trim().isEmpty) {
      setState(() => _error = 'Post text cannot be empty.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await PostRepository().editPost(
        widget.postId,
        textContent: _text.text.trim(),
        tags: _parsedTags,
        visibility: _visibility,
      );
      if (mounted) context.pop(true);
    } catch (_) {
      if (mounted) setState(() { _saving = false; _error = 'Could not save changes. Try again.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit post'),
        actions: [
          TextButton(
            onPressed: _saving || _loading ? null : _save,
            child: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _post == null
              ? Center(child: Text(_error ?? 'Post not found.'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ),
                    if (_post!.editCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('Edited ${_post!.editCount} time${_post!.editCount == 1 ? '' : 's'}',
                            style: Theme.of(context).textTheme.bodySmall),
                      ),
                    FormatToolbar(controller: _text, onChanged: (_) => setState(() {})),
                    TextField(
                      controller: _text,
                      minLines: 3,
                      maxLines: 10,
                      maxLength: _maxLength,
                      decoration: const InputDecoration(labelText: 'Text content'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _tags,
                      decoration: const InputDecoration(labelText: 'Tags', hintText: 'comma or space separated'),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _visibility,
                      decoration: const InputDecoration(labelText: 'Visibility'),
                      items: [
                        for (final entry in _visibilityOptions.entries)
                          DropdownMenuItem(
                            value: entry.key,
                            child: Row(children: [Icon(entry.value.$2, size: 18), const SizedBox(width: 8), Text(entry.value.$1)]),
                          ),
                      ],
                      onChanged: (v) => setState(() => _visibility = v ?? _visibility),
                    ),
                  ],
                ),
    );
  }
}
