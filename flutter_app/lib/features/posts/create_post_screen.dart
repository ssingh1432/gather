import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/supabase_client.dart';
import '../../shared/models/models.dart';
import '../../shared/services/analytics_service.dart';
import '../../shared/services/beta_error_logging_service.dart';
import '../../shared/services/link_preview_service.dart';
import '../../shared/utils/feelings.dart';
import '../../shared/widgets/reusables.dart';
import '../data/repositories.dart';
import 'location_picker_screen.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key, this.communityId, this.quotePostId, this.sharedText});
  final String? communityId;

  /// When set, this post is published as a quote/reply-share of the given
  /// post id (the "Share to your feed" flow from the post card).
  final String? quotePostId;

  /// Text/link received via the OS "Share" sheet from another app (see
  /// the SEND intent-filter in AndroidManifest.xml + main.dart's
  /// receive_sharing_intent listener) — pre-fills the compose box.
  final String? sharedText;

  @override
  State<CreatePostScreen> createState() => _P();
}

class _P extends State<CreatePostScreen> {
  final text = TextEditingController();
  final location = TextEditingController();
  final tagsCtrl = TextEditingController();
  XFile? image;
  XFile? video;
  bool loading = false;
  String? err;
  String? _pendingPostId;
  bool _published = false;
  FeelingOption? _feeling;

  PostModel? _quotedPost;
  bool _loadingQuote = false;

  // Defaults from the user's Settings > "Who can see your posts by
  // default", but editable per post right here in the composer.
  String _visibility = 'public';
  static const _visibilityOptions = {
    'public': ('Public', Icons.public),
    'friends': ('Friends', Icons.people_alt_outlined),
    'only_me': ('Only me', Icons.lock_outline),
  };

  // username -> id, so chips can show the name while we submit ids.
  final Map<String, String> _taggedFriends = {};
  double? _pickedLat;
  double? _pickedLng;
  LinkPreview? _linkPreview;
  bool _loadingLinkPreview = false;
  String? _lastCheckedUrl;
  Timer? _linkDebounce;

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.postCreationStarted(communityId: widget.communityId);
    if (SupabaseConfig.currentUserId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.go('/login?redirect=${Uri.encodeComponent(_redirectLocation)}');
        }
      });
    }
    if (widget.quotePostId != null) {
      _loadQuotedPost();
    }
    if (widget.sharedText != null && widget.sharedText!.isNotEmpty) {
      text.text = widget.sharedText!;
      _onTextChanged(widget.sharedText!);
    }
    _loadDefaultVisibility();
  }

  Future<void> _loadDefaultVisibility() async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) return;
    try {
      final profile = await ProfileRepository().loadProfile(uid);
      final defaultVisibility = profile?['default_post_visibility'] as String?;
      if (mounted && defaultVisibility != null && _visibilityOptions.containsKey(defaultVisibility)) {
        setState(() => _visibility = defaultVisibility);
      }
    } catch (_) {
      // Falls back to 'public' — not worth blocking or erroring the
      // composer over a preference lookup.
    }
  }

  Future<void> _loadQuotedPost() async {
    setState(() => _loadingQuote = true);
    try {
      final post = await FeedRepository().getPost(widget.quotePostId!);
      if (mounted) setState(() => _quotedPost = post);
    } catch (_) {
      // If the quoted post can't load, publishing still works — the
      // reply_to_post_id insert will simply be rejected server-side if it's
      // genuinely gone, so we just drop the preview rather than block posting.
    } finally {
      if (mounted) setState(() => _loadingQuote = false);
    }
  }

  @override
  void dispose() {
    if (!_published && (text.text.trim().isNotEmpty || image != null || video != null)) {
      AnalyticsService.instance.postCreationAbandoned(
        communityId: widget.communityId,
        hadText: text.text.trim().isNotEmpty,
        hadImage: image != null || video != null,
      );
    }
    _linkDebounce?.cancel();
    text.dispose();
    location.dispose();
    tagsCtrl.dispose();
    super.dispose();
  }

  String get _redirectLocation {
    final communityId = widget.communityId;
    if (communityId == null || communityId.isEmpty) return '/create-post';
    return '/create-post?communityId=${Uri.encodeComponent(communityId)}';
  }

  List<String> get _parsedTags => tagsCtrl.text
      .split(RegExp(r'[,\s]+'))
      .map((t) => t.trim().replaceFirst(RegExp(r'^#'), ''))
      .where((t) => t.isNotEmpty)
      .toSet()
      .toList();

  Future<void> _publish() async {
    final uid = SupabaseConfig.client.auth.currentUser?.id;
    if (uid == null) {
      if (mounted) {
        context.go('/login?redirect=${Uri.encodeComponent(_redirectLocation)}');
      }
      return;
    }

    if (text.text.trim().isEmpty && image == null && video == null) {
      if (mounted) setState(() => err = 'Add text, a photo, or a video');
      return;
    }

    if (mounted) {
      setState(() {
        loading = true;
        err = null;
      });
    }

    try {
      final postRepository = PostRepository();

      _pendingPostId ??= (await postRepository.createPost({
        'author_id': uid,
        'community_id': widget.communityId,
        'text_content': text.text.trim(),
        'visibility': _visibility,
        'location': location.text.trim().isEmpty ? null : location.text.trim(),
        'location_lat': _pickedLat,
        'location_lng': _pickedLng,
        'feeling': _feeling?.stored,
        'tags': _parsedTags,
        'reply_to_post_id': widget.quotePostId,
        'mentioned_user_ids': _taggedFriends.values.toList(),
        'mentioned_usernames': _taggedFriends.keys.toList(),
        'link_preview_url': _linkPreview?.url,
        'link_preview_title': _linkPreview?.title,
        'link_preview_description': _linkPreview?.description,
        'link_preview_image_url': _linkPreview?.imageUrl,
        'link_preview_site_name': _linkPreview?.siteName,
      }))['id'].toString();

      if (video != null) {
        final videoUrl = await postRepository.uploadPostVideo(_pendingPostId!, video!);
        await postRepository.addPostMedia(_pendingPostId!, videoUrl, mediaType: 'video');
      } else if (image != null) {
        final uploaded = await postRepository.uploadPostImage(_pendingPostId!, image!);
        await postRepository.addPostMedia(_pendingPostId!, uploaded.originalUrl);
      }

      _published = true;
      if (mounted) {
        text.clear();
        image = null;
        video = null;
        context.go('/');
      }
    } catch (e, stackTrace) {
      BetaErrorLoggingService.instance.record(e, stackTrace, 
        context: 'post_creation_submit', 
        metadata: {'community_id': widget.communityId}
      );

      if (mounted) {
        final message = 'Upload failed. Please check your connection and retry. $e';
        setState(() => err = message);
        // Inline text below can be scrolled past unnoticed on a long form —
        // a SnackBar guarantees the failure is actually seen instead of
        // looking like the tap silently did nothing.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.red, duration: const Duration(seconds: 6)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  void _onTextChanged(String value) {
    _linkDebounce?.cancel();
    _linkDebounce = Timer(const Duration(milliseconds: 600), () async {
      final url = firstUrlIn(value);
      if (url == null) {
        if (_linkPreview != null && mounted) setState(() => _linkPreview = null);
        _lastCheckedUrl = null;
        return;
      }
      if (url == _lastCheckedUrl) return;
      _lastCheckedUrl = url;
      setState(() => _loadingLinkPreview = true);
      final preview = await LinkPreviewService().fetch(url);
      if (mounted && _lastCheckedUrl == url) {
        setState(() {
          _linkPreview = preview;
          _loadingLinkPreview = false;
        });
      }
    });
  }

  Future<void> _pickFriends() async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) return;
    final selected = Map<String, String>.from(_taggedFriends);
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
            ProfileRepository().followingUsers(uid).then((people) {
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
                  Text('Tag friends', style: Theme.of(context).textTheme.titleMedium),
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
                      final found = q.trim().isEmpty
                          ? await ProfileRepository().followingUsers(uid)
                          : await ProfileRepository().searchUsersByUsername(q);
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
                                  if (id == uid) return const SizedBox.shrink(); // can't tag yourself
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
        _taggedFriends
          ..clear()
          ..addAll(selected);
      });
    }
  }

  Future<void> _pickFeeling() async {
    final selected = await showModalBottomSheet<FeelingOption>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          childAspectRatio: 3.2,
          children: [
            for (final option in kFeelingOptions)
              InkWell(
                onTap: () => Navigator.pop(sheetContext, option),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(border: Border.all(color: Theme.of(sheetContext).colorScheme.outlineVariant), borderRadius: BorderRadius.circular(10)),
                  child: Text('${option.emoji} ${option.label}'),
                ),
              ),
          ],
        ),
      ),
    );
    if (selected != null) setState(() => _feeling = selected);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.quotePostId != null ? 'Share to your feed' : 'Create Post')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: text,
              minLines: 3,
              maxLines: 8,
              onChanged: _onTextChanged,
              decoration: const InputDecoration(labelText: 'Text content', hintText: "What's on your mind?"),
            ),
            if (_loadingLinkPreview) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
            if (_linkPreview != null) ...[
              const SizedBox(height: 10),
              _LinkPreviewCard(
                preview: _linkPreview!,
                onRemove: () => setState(() {
                  _linkPreview = null;
                  _lastCheckedUrl = null;
                }),
              ),
            ],
            const SizedBox(height: 12),
            _VisibilityPicker(
              value: _visibility,
              options: _visibilityOptions,
              onChanged: (v) => setState(() => _visibility = v),
            ),
            const SizedBox(height: 12),
            if (_loadingQuote) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator()),
            if (_quotedPost != null) ...[
              _QuotedPostPreviewCard(post: _quotedPost!),
              const SizedBox(height: 12),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
                    if (picked == null) return;
                    setState(() {
                      image = picked;
                      video = null; // a post carries at most one media item
                    });
                  },
                  icon: const Icon(Icons.image_outlined),
                  label: Text(image == null ? 'Add photo' : 'Photo selected'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await ImagePicker().pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 5));
                    if (picked == null) return;
                    setState(() {
                      video = picked;
                      image = null; // a post carries at most one media item
                    });
                  },
                  icon: const Icon(Icons.videocam_outlined),
                  label: Text(video == null ? 'Add video' : 'Video selected'),
                ),
                OutlinedButton.icon(
                  onPressed: _pickFeeling,
                  icon: Text(_feeling?.emoji ?? '🙂'),
                  label: Text(_feeling == null ? 'Feeling' : _feeling!.label),
                ),
                OutlinedButton.icon(
                  onPressed: _pickFriends,
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: Text(_taggedFriends.isEmpty ? 'Tag friends' : 'Tagged ${_taggedFriends.length}'),
                ),
              ],
            ),
            if (_taggedFriends.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _taggedFriends.keys
                    .map((name) => Chip(
                          label: Text('@$name'),
                          onDeleted: () => setState(() => _taggedFriends.remove(name)),
                        ))
                    .toList(),
              ),
            ],
            if (video != null) ...[
              const SizedBox(height: 8),
              Text('Videos up to 5 minutes are supported.', style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: location,
              readOnly: true,
              onTap: () async {
                final picked = await Navigator.of(context).push<PickedLocation>(
                  MaterialPageRoute(
                    builder: (_) => LocationPickerScreen(
                      initial: _pickedLat != null && _pickedLng != null && location.text.isNotEmpty
                          ? PickedLocation(label: location.text, lat: _pickedLat!, lng: _pickedLng!)
                          : null,
                    ),
                  ),
                );
                if (picked != null) {
                  setState(() {
                    location.text = picked.label;
                    _pickedLat = picked.lat;
                    _pickedLng = picked.lng;
                  });
                }
              },
              decoration: InputDecoration(
                labelText: 'Location',
                hintText: 'Tap to pick on the map',
                prefixIcon: const Icon(Icons.location_on_outlined),
                suffixIcon: location.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() {
                          location.clear();
                          _pickedLat = null;
                          _pickedLng = null;
                        }),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: tagsCtrl,
              decoration: const InputDecoration(labelText: 'Tags', hintText: 'e.g. music, nepal, travel', prefixIcon: Icon(Icons.tag)),
            ),
            if (err != null) ...[
              const SizedBox(height: 12),
              Text(err!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 8),
              const Text('You can press Publish again to retry the same post upload.'),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: loading ? null : _publish,
                child: loading
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Publish'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact "who can see this" selector shown in the composer. Opens a
/// bottom sheet with the three visibility levels (mirrors the wording used
/// in Settings > Privacy so it reads consistently across the app).
class _VisibilityPicker extends StatelessWidget {
  const _VisibilityPicker({required this.value, required this.options, required this.onChanged});

  final String value;
  final Map<String, (String, IconData)> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final (label, icon) = options[value] ?? options['public']!;
    return OutlinedButton.icon(
      onPressed: () async {
        final selected = await showModalBottomSheet<String>(
          context: context,
          showDragHandle: true,
          builder: (sheetContext) => SafeArea(
            child: RadioGroup<String>(
              groupValue: value,
              onChanged: (v) {
                if (v != null) Navigator.pop(sheetContext, v);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Align(alignment: Alignment.centerLeft, child: Text('Who can see this post?')),
                  ),
                  for (final entry in options.entries)
                    RadioListTile<String>(
                      value: entry.key,
                      secondary: Icon(entry.value.$2),
                      title: Text(entry.value.$1),
                    ),
                ],
              ),
            ),
          ),
        );
        if (selected != null) onChanged(selected);
      },
      icon: Icon(icon),
      label: Text(label),
    );
  }
}

class _QuotedPostPreviewCard extends StatelessWidget {
  const _QuotedPostPreviewCard({required this.post});
  final PostModel post;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(border: Border.all(color: theme.colorScheme.outlineVariant), borderRadius: BorderRadius.circular(10)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProfileAvatar(url: post.authorAvatarUrl, radius: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(post.authorUsername ?? 'Unknown', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                if (post.textContent.isNotEmpty)
                  Text(post.textContent, maxLines: 3, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkPreviewCard extends StatelessWidget {
  const _LinkPreviewCard({required this.preview, this.onRemove});
  final LinkPreview preview;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (preview.imageUrl != null && preview.imageUrl!.isNotEmpty)
                SizedBox(
                  width: 84,
                  height: 84,
                  child: Image.network(preview.imageUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (preview.siteName != null)
                        Text(preview.siteName!.toUpperCase(), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.outline)),
                      if (preview.title != null)
                        Text(preview.title!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (preview.description != null)
                        Text(preview.description!, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (onRemove != null)
            Positioned(
              top: 2,
              right: 2,
              child: IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: onRemove,
                style: IconButton.styleFrom(backgroundColor: Colors.black.withValues(alpha: 0.35), foregroundColor: Colors.white, minimumSize: const Size(28, 28)),
              ),
            ),
        ],
      ),
    );
  }
}
