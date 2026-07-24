import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/supabase_client.dart';
import '../../shared/models/models.dart';
import '../../shared/services/analytics_service.dart';
import '../../shared/services/beta_error_logging_service.dart';
import '../../shared/services/link_preview_service.dart';
import '../../shared/services/media/web_safe_pick.dart';
import '../../shared/utils/feelings.dart';
import '../../shared/widgets/format_toolbar.dart';
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
  PlatformFile? audio;
  PlatformFile? document;
  _PollDraft? pollDraft;
  _EventDraft? eventDraft;
  bool loading = false;
  String? err;
  String? _pendingPostId;
  bool _published = false;
  FeelingOption? _feeling;
  bool _isSensitive = false;

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

  static const _maxLength = 5000;
  Timer? _draftDebounce;
  bool _draftSaving = false;
  DateTime? _draftSavedAt;
  bool _draftLoaded = false;

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
    } else {
      _loadDraft();
    }
    _loadDefaultVisibility();
  }

  Future<void> _loadDraft() async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null || widget.quotePostId != null) return;
    try {
      final draft = await PostRepository().loadDraft(userId: uid, communityId: widget.communityId);
      if (draft == null || !mounted) return;
      final savedText = draft['text_content'] as String? ?? '';
      if (savedText.isEmpty) return;
      setState(() {
        text.text = savedText;
        _draftLoaded = true;
      });
    } catch (_) {
      // No draft, or the fetch failed — composer just opens empty, same as before.
    }
  }

  void _scheduleDraftSave(String value) {
    _draftDebounce?.cancel();
    if (widget.quotePostId != null) return; // quote/reply composer isn't drafted
    _draftDebounce = Timer(const Duration(seconds: 2), () async {
      final uid = SupabaseConfig.currentUserId;
      if (uid == null) return;
      if (value.trim().isEmpty) return;
      setState(() => _draftSaving = true);
      try {
        await PostRepository().saveDraft(
          userId: uid,
          communityId: widget.communityId,
          textContent: value,
          tags: _parsedTags,
          visibility: _visibility,
        );
        if (mounted) setState(() => _draftSavedAt = DateTime.now());
      } catch (_) {
        // Draft save is best-effort; don't interrupt composing over it.
      } finally {
        if (mounted) setState(() => _draftSaving = false);
      }
    });
  }

  Future<void> _discardDraft() async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) return;
    try {
      await PostRepository().deleteDraft(userId: uid, communityId: widget.communityId);
    } catch (_) {}
    if (mounted) {
      setState(() {
        text.clear();
        _draftLoaded = false;
        _draftSavedAt = null;
      });
    }
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
    if (!_published && (text.text.trim().isNotEmpty || image != null || video != null || audio != null || document != null)) {
      AnalyticsService.instance.postCreationAbandoned(
        communityId: widget.communityId,
        hadText: text.text.trim().isNotEmpty,
        hadImage: image != null || video != null || audio != null || document != null,
      );
    }
    _linkDebounce?.cancel();
    _draftDebounce?.cancel();
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

    if (text.text.trim().isEmpty && image == null && video == null && audio == null && document == null && pollDraft == null && eventDraft == null) {
      if (mounted) setState(() => err = 'Add text, media, a poll, or an event');
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
        'is_sensitive': _isSensitive,
        'content_type': pollDraft != null ? 'poll' : (eventDraft != null ? 'event' : 'text'),
      }))['id'].toString();

      if (pollDraft != null) {
        await postRepository.createPoll(
          _pendingPostId!,
          question: pollDraft!.question,
          options: pollDraft!.options,
          allowMultiple: pollDraft!.allowMultiple,
          isAnonymous: pollDraft!.isAnonymous,
        );
      } else if (eventDraft != null) {
        await postRepository.createEvent(
          _pendingPostId!,
          title: eventDraft!.title,
          startsAt: eventDraft!.startsAt,
          locationText: eventDraft!.locationText,
          onlineUrl: eventDraft!.onlineUrl,
        );
      } else if (video != null) {
        final videoUrl = await postRepository.uploadPostVideo(_pendingPostId!, video!);
        await postRepository.addPostMedia(_pendingPostId!, videoUrl, mediaType: 'video');
      } else if (image != null) {
        final uploaded = await postRepository.uploadPostImage(_pendingPostId!, image!);
        await postRepository.addPostMedia(_pendingPostId!, uploaded.originalUrl);
      } else if (audio != null) {
        final audioUrl = await postRepository.uploadPostAudio(_pendingPostId!, audio!);
        await postRepository.addPostMedia(_pendingPostId!, audioUrl, mediaType: 'audio');
      } else if (document != null) {
        final docUrl = await postRepository.uploadPostDocument(_pendingPostId!, document!);
        await postRepository.addPostMedia(_pendingPostId!, docUrl, mediaType: 'document');
      }

      _published = true;
      unawaited(PostRepository().deleteDraft(userId: uid, communityId: widget.communityId).catchError((_) {}));
      if (mounted) {
        text.clear();
        image = null;
        video = null;
        audio = null;
        document = null;
        pollDraft = null;
        eventDraft = null;
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
    _scheduleDraftSave(value);
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
            if (_draftLoaded)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(Icons.history, size: 16, color: Colors.grey),
                    const SizedBox(width: 6),
                    const Expanded(child: Text('Restored from your draft', style: TextStyle(color: Colors.grey, fontSize: 12))),
                    TextButton(onPressed: _discardDraft, child: const Text('Discard')),
                  ],
                ),
              ),
            FormatToolbar(controller: text, onChanged: _onTextChanged),
            TextField(
              controller: text,
              minLines: 3,
              maxLines: 8,
              maxLength: _maxLength,
              onChanged: _onTextChanged,
              decoration: InputDecoration(
                labelText: 'Text content',
                hintText: "What's on your mind?",
                helperText: _draftSaving
                    ? 'Saving draft…'
                    : _draftSavedAt != null
                        ? 'Draft saved'
                        : null,
              ),
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
                    final safe = await materializeIfWeb(picked);
                    setState(() {
                      image = safe;
                      video = null;
                      audio = null;
                      document = null; // a post carries at most one media item
                      pollDraft = null;
                      eventDraft = null;
                    });
                  },
                  icon: const Icon(Icons.image_outlined),
                  label: Text(image == null ? 'Add photo' : 'Photo selected'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await ImagePicker().pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 5));
                    if (picked == null) return;
                    final safe = await materializeIfWeb(picked);
                    setState(() {
                      video = safe;
                      image = null;
                      audio = null;
                      document = null; // a post carries at most one media item
                      pollDraft = null;
                      eventDraft = null;
                    });
                  },
                  icon: const Icon(Icons.videocam_outlined),
                  label: Text(video == null ? 'Add video' : 'Video selected'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final result = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: const ['mp3', 'm4a', 'aac', 'wav'],
                      withData: true,
                    );
                    final picked = result?.files.single;
                    if (picked == null) return;
                    if (mounted) {
                      setState(() {
                        audio = picked;
                        image = null;
                        video = null;
                        document = null;
                        pollDraft = null;
                        eventDraft = null;
                      });
                    }
                  },
                  icon: const Icon(Icons.audiotrack_outlined),
                  label: Text(audio == null ? 'Add audio' : audio!.name),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final result = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: const ['pdf', 'doc', 'docx'],
                      withData: true,
                    );
                    final picked = result?.files.single;
                    if (picked == null) return;
                    if (mounted) {
                      setState(() {
                        document = picked;
                        image = null;
                        video = null;
                        audio = null;
                        pollDraft = null;
                        eventDraft = null;
                      });
                    }
                  },
                  icon: const Icon(Icons.description_outlined),
                  label: Text(document == null ? 'Add document' : document!.name),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final draft = await _showPollSheet(context, pollDraft);
                    if (draft == null) return;
                    setState(() {
                      pollDraft = draft;
                      eventDraft = null;
                      image = null;
                      video = null;
                      audio = null;
                      document = null;
                    });
                  },
                  icon: const Icon(Icons.poll_outlined),
                  label: Text(pollDraft == null ? 'Add poll' : 'Poll: ${pollDraft!.question}'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final draft = await _showEventSheet(context, eventDraft);
                    if (draft == null) return;
                    setState(() {
                      eventDraft = draft;
                      pollDraft = null;
                      image = null;
                      video = null;
                      audio = null;
                      document = null;
                    });
                  },
                  icon: const Icon(Icons.event_outlined),
                  label: Text(eventDraft == null ? 'Add event' : 'Event: ${eventDraft!.title}'),
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
                OutlinedButton.icon(
                  onPressed: () => setState(() => _isSensitive = !_isSensitive),
                  style: _isSensitive
                      ? OutlinedButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.error,
                          side: BorderSide(color: Theme.of(context).colorScheme.error),
                        )
                      : null,
                  icon: Icon(_isSensitive ? Icons.warning_amber_rounded : Icons.warning_amber),
                  label: const Text('Sensitive content'),
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
                  MarkdownLiteText(post.textContent, maxLines: 3, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
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


Future<_PollDraft?> _showPollSheet(BuildContext context, _PollDraft? existing) {
  final question = TextEditingController(text: existing?.question ?? '');
  final options = List<TextEditingController>.generate(
    (existing?.options.length ?? 2).clamp(2, 6),
    (i) => TextEditingController(text: existing != null && i < existing.options.length ? existing.options[i] : ''),
  );
  bool allowMultiple = existing?.allowMultiple ?? false;
  bool isAnonymous = existing?.isAnonymous ?? true;

  return showModalBottomSheet<_PollDraft>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Create poll', style: Theme.of(sheetContext).textTheme.titleMedium),
              const SizedBox(height: 12),
              TextField(controller: question, decoration: const InputDecoration(labelText: 'Question')),
              const SizedBox(height: 12),
              for (var i = 0; i < options.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    controller: options[i],
                    decoration: InputDecoration(
                      labelText: 'Option ${i + 1}',
                      suffixIcon: options.length > 2
                          ? IconButton(icon: const Icon(Icons.close), onPressed: () => setSheetState(() => options.removeAt(i).dispose()))
                          : null,
                    ),
                  ),
                ),
              if (options.length < 6)
                TextButton.icon(
                  onPressed: () => setSheetState(() => options.add(TextEditingController())),
                  icon: const Icon(Icons.add),
                  label: const Text('Add option'),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Allow multiple choices'),
                value: allowMultiple,
                onChanged: (v) => setSheetState(() => allowMultiple = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Anonymous voting'),
                value: isAnonymous,
                onChanged: (v) => setSheetState(() => isAnonymous = v),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () {
                  final q = question.text.trim();
                  final opts = options.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();
                  if (q.isEmpty || opts.length < 2) {
                    ScaffoldMessenger.of(sheetContext).showSnackBar(
                      const SnackBar(content: Text('Add a question and at least 2 options.')),
                    );
                    return;
                  }
                  Navigator.pop(sheetContext, _PollDraft(question: q, options: opts, allowMultiple: allowMultiple, isAnonymous: isAnonymous));
                },
                child: const Text('Save poll'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<_EventDraft?> _showEventSheet(BuildContext context, _EventDraft? existing) {
  final title = TextEditingController(text: existing?.title ?? '');
  final locationText = TextEditingController(text: existing?.locationText ?? '');
  final onlineUrl = TextEditingController(text: existing?.onlineUrl ?? '');
  DateTime startsAt = existing?.startsAt ?? DateTime.now().add(const Duration(days: 1));

  return showModalBottomSheet<_EventDraft>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Create event', style: Theme.of(sheetContext).textTheme.titleMedium),
              const SizedBox(height: 12),
              TextField(controller: title, decoration: const InputDecoration(labelText: 'Event title')),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule),
                title: Text('${startsAt.year}-${startsAt.month.toString().padLeft(2, '0')}-${startsAt.day.toString().padLeft(2, '0')}  ${startsAt.hour.toString().padLeft(2, '0')}:${startsAt.minute.toString().padLeft(2, '0')}'),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () async {
                  final date = await showDatePicker(
                    context: sheetContext,
                    initialDate: startsAt,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 730)),
                  );
                  if (date == null || !sheetContext.mounted) return;
                  final time = await showTimePicker(context: sheetContext, initialTime: TimeOfDay.fromDateTime(startsAt));
                  if (time == null) return;
                  setSheetState(() => startsAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
                },
              ),
              const SizedBox(height: 8),
              TextField(controller: locationText, decoration: const InputDecoration(labelText: 'Location (optional)')),
              const SizedBox(height: 12),
              TextField(controller: onlineUrl, decoration: const InputDecoration(labelText: 'Online meeting link (optional)')),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  if (title.text.trim().isEmpty) {
                    ScaffoldMessenger.of(sheetContext).showSnackBar(const SnackBar(content: Text('Add an event title.')));
                    return;
                  }
                  Navigator.pop(
                    sheetContext,
                    _EventDraft(
                      title: title.text.trim(),
                      startsAt: startsAt,
                      locationText: locationText.text.trim().isEmpty ? null : locationText.text.trim(),
                      onlineUrl: onlineUrl.text.trim().isEmpty ? null : onlineUrl.text.trim(),
                    ),
                  );
                },
                child: const Text('Save event'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _PollDraft {
  _PollDraft({required this.question, required this.options, this.allowMultiple = false, this.isAnonymous = true});
  final String question;
  final List<String> options;
  final bool allowMultiple;
  final bool isAnonymous;
}

class _EventDraft {
  _EventDraft({required this.title, required this.startsAt, this.locationText, this.onlineUrl});
  final String title;
  final DateTime startsAt;
  final String? locationText;
  final String? onlineUrl;
}
