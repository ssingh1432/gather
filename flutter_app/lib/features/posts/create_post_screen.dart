import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';
import '../../shared/models/models.dart';
import '../../shared/services/analytics_service.dart';
import '../../shared/services/beta_error_logging_service.dart';
import '../../shared/services/link_preview_service.dart';
import '../../shared/services/media/web_safe_pick.dart';
import '../../shared/services/media_upload_service.dart' show UploadedPostImage;
import '../../shared/utils/feelings.dart';
import '../../shared/widgets/format_toolbar.dart';
import '../../shared/widgets/profile_view.dart' show PickedImagePreview;
import '../../shared/widgets/reusables.dart';
import '../data/repositories.dart';
import 'location_picker_screen.dart';

/// Wraps an error with which publish step it happened in, so the
/// composer can tell the user "Video upload failed" instead of a generic
/// "Something went wrong" — see requirement #12 and _friendlyError().
class _PublishStepFailure implements Exception {
  final String label;
  final Object cause;
  const _PublishStepFailure(this.label, this.cause);
  @override
  String toString() => '$label: $cause';
}

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
  final _textFocus = FocusNode();
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
    'followers': ('Followers', Icons.group_outlined),
    'friends': ('Close friends', Icons.people_alt_outlined),
    'community': ('Community only', Icons.diversity_3_outlined),
    'private': ('Only me', Icons.lock_outline),
    'unlisted': ('Unlisted', Icons.link_outlined),
  };

  // Step 10 — Scheduled Posts. Null means "publish now".
  DateTime? _scheduledFor;

  // userId -> username. IDs are the source of truth for who's tagged;
  // usernames are display-only. Keying by id (not name) means a Map
  // naturally forbids duplicate tags and survives username changes.
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
      final pendingId = draft['pending_post_id'] as String?;
      if (savedText.isEmpty && pendingId == null) return;
      setState(() {
        text.text = savedText;
        _draftLoaded = true;
        // Restores a publish that was interrupted by the app being
        // killed/crashing mid-upload in an earlier session — resuming
        // finishes the SAME post instead of createPost() making a new
        // one. See migration 096.
        _pendingPostId = pendingId;
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
    _textFocus.dispose();
    location.dispose();
    tagsCtrl.dispose();
    super.dispose();
  }

  String get _redirectLocation {
    final communityId = widget.communityId;
    if (communityId == null || communityId.isEmpty) return '/create-post';
    return '/create-post?communityId=${Uri.encodeComponent(communityId)}';
  }

  Map<String, (String, IconData)> get _effectiveVisibilityOptions {
    if (widget.communityId != null && widget.communityId!.isNotEmpty) return _visibilityOptions;
    return {for (final e in _visibilityOptions.entries) if (e.key != 'community') e.key: e.value};
  }

  List<String> get _parsedTags => tagsCtrl.text
      .split(RegExp(r'[,\s]+'))
      .map((t) => t.trim().replaceFirst(RegExp(r'^#'), ''))
      .where((t) => t.isNotEmpty)
      .toSet()
      .toList();

  /// `posts.content_type` used to be hardcoded to only `'poll' | 'event' |
  /// 'text'`, so every image/video/audio/document post was mislabeled as
  /// plain text — breaking anything downstream that branches on
  /// content_type (feed filters, search, analytics, moderation triage).
  /// A post can carry multiple attachments at once (see the non-else-if
  /// upload block in [_publish]), so this picks one representative type by
  /// priority: poll/event (their own content model) > video > image >
  /// audio > document > text.
  String get _resolvedContentType {
    if (pollDraft != null) return 'poll';
    if (eventDraft != null) return 'event';
    if (video != null) return 'video';
    if (image != null) return 'image';
    if (audio != null) return 'audio';
    if (document != null) return 'document';
    return 'text';
  }

  /// Labels which publish step failed (per requirement #12: "Post
  /// creation failed" / "Image upload failed" / etc. are meaningfully
  /// different for the user, not just for a developer reading logs) by
  /// wrapping the original error rather than replacing it, so
  /// BetaErrorLoggingService still gets the real exception underneath.
  Object _labeled(String label, Object e) => _PublishStepFailure(label, e);

  /// Turns known backend errors into plain-language messages. Full
  /// technical detail (code/message/hint) still goes to
  /// BetaErrorLoggingService for debugging — it's just no longer shown
  /// verbatim to the user, who has no use for a Postgres error code.
  String _friendlyError(Object e) {
    if (e is _PublishStepFailure) {
      final inner = e.cause;
      if (inner is PostgrestException && (inner.code == 'P0001' || inner.code == '23505' || inner.message.toLowerCase().contains('duplicate'))) {
        return 'This post may have already gone through — check your feed before posting again.';
      }
      if (inner is StorageException && inner.statusCode == '403') {
        return '${e.label} — your session needs a refresh. Please try again, or sign out and back in if it keeps happening.';
      }
      return '${e.label}. Please check your connection and try again.';
    }
    if (e is PostgrestException) {
      switch (e.code) {
        case 'P0001':
          return 'This post may have already gone through — check your feed before posting again.';
        case '23505':
          return 'This looks like it was already posted.';
      }
      if (e.message.toLowerCase().contains('duplicate')) {
        return 'This post may have already gone through — check your feed before posting again.';
      }
    }
    if (e is StorageException && e.statusCode == '403') {
      return 'Your session needs a refresh before uploading — please try again, or sign out and back in if it keeps happening.';
    }
    return 'Upload failed. Please check your connection and try again.';
  }

  /// Decodes a JWT's payload segment without verifying its signature —
  /// this is purely for client-side diagnostics (comparing the token's
  /// `sub` against who we think is logged in), never for trusting the
  /// token's contents for anything security-relevant.
  Map<String, dynamic>? _decodeJwtPayload(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
      payload += '=' * ((4 - payload.length % 4) % 4);
      return jsonDecode(utf8.decode(base64.decode(payload))) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> _publish() async {
    // Explicit operation guard — belt-and-braces alongside the button's
    // `onPressed: loading ? null : _publish`. The button disables on the
    // next frame after setState, which is not synchronous with the tap;
    // this check closes that gap so a double/rapid tap or a stray
    // duplicate callback can never start a second publish while one is
    // already in flight.
    if (loading) return;
    if (_scheduledFor != null) return _schedule();

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
      final isResuming = _pendingPostId != null;

      if (isResuming) {
        // The post row from an earlier attempt already exists — don't
        // create a second one. But the composer's content may have
        // changed since then (the user edited text/tags/visibility
        // before retrying), so sync it onto the existing row rather than
        // silently publishing whatever was there from the first attempt.
        try {
          await postRepository.updatePendingPost(
            _pendingPostId!,
            textContent: text.text.trim(),
            visibility: _visibility,
            tags: _parsedTags,
            mentionedUserIds: _taggedFriends.keys.toList(),
            mentionedUsernames: _taggedFriends.values.toList(),
            isSensitive: _isSensitive,
          );
        } catch (e) {
          throw _labeled('Post update failed', e);
        }
      } else {
        try {
          _pendingPostId = (await postRepository.createPost({
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
            'mentioned_user_ids': _taggedFriends.keys.toList(),
            'mentioned_usernames': _taggedFriends.values.toList(),
            'link_preview_url': _linkPreview?.url,
            'link_preview_title': _linkPreview?.title,
            'link_preview_description': _linkPreview?.description,
            'link_preview_image_url': _linkPreview?.imageUrl,
            'link_preview_site_name': _linkPreview?.siteName,
            'is_sensitive': _isSensitive,
            'content_type': _resolvedContentType,
            // Invisible to every feed/profile/search read until
            // finalizePost() confirms every step below succeeded — see
            // migration 097 / requirement #3 ("a partially-created post
            // must not accidentally appear as a normal completed post").
            'publish_status': 'publishing',
          }))['id'].toString();
        } catch (e) {
          throw _labeled('Post creation failed', e);
        }
        // Persist immediately (best-effort — a failure here just means a
        // crash in the next few seconds would fall back to creating a
        // new post, same as before this fix existed) so a resume after
        // an app kill can find this row instead of createPost() making
        // a duplicate. Not awaited: this must not add latency/failure
        // surface to the actual publish path.
        unawaited(
          postRepository
              .saveDraft(
                userId: uid,
                communityId: widget.communityId,
                textContent: text.text.trim(),
                tags: _parsedTags,
                visibility: _visibility,
                pendingPostId: _pendingPostId,
              )
              .catchError((_) {}),
        );
      }

      if (pollDraft != null) {
        try {
          await postRepository.createPoll(
            _pendingPostId!,
            question: pollDraft!.question,
            options: pollDraft!.options,
            allowMultiple: pollDraft!.allowMultiple,
            isAnonymous: pollDraft!.isAnonymous,
            expiresAt: pollDraft!.expiresAt,
          );
        } catch (e) {
          throw _labeled('Poll creation failed', e);
        }
      } else if (eventDraft != null) {
        try {
          await postRepository.createEvent(
            _pendingPostId!,
            title: eventDraft!.title,
            startsAt: eventDraft!.startsAt,
            locationText: eventDraft!.locationText,
            onlineUrl: eventDraft!.onlineUrl,
          );
        } catch (e) {
          throw _labeled('Event creation failed', e);
        }
      } else {
        // Independent — a post can carry any combination of photo, video,
        // audio, and document at once (each lives as its own row in
        // post_media, keyed by media_type), so these must NOT be an
        // else-if chain. They previously were, which silently dropped
        // every attachment but the first one the user had picked.
        if (video != null) {
          String videoUrl;
          try {
            videoUrl = await postRepository.uploadPostVideo(_pendingPostId!, video!);
          } catch (e) {
            throw _labeled('Video upload failed', e);
          }
          try {
            await postRepository.addPostMedia(_pendingPostId!, videoUrl, mediaType: 'video');
          } catch (e) {
            throw _labeled('Attaching video failed', e);
          }
        }
        if (image != null) {
          UploadedPostImage uploaded;
          try {
            uploaded = await postRepository.uploadPostImage(_pendingPostId!, image!);
          } catch (e) {
            throw _labeled('Image upload failed', e);
          }
          try {
            await postRepository.addPostMedia(_pendingPostId!, uploaded.originalUrl);
          } catch (e) {
            throw _labeled('Attaching image failed', e);
          }
        }
        if (audio != null) {
          String audioUrl;
          try {
            audioUrl = await postRepository.uploadPostAudio(_pendingPostId!, audio!);
          } catch (e) {
            throw _labeled('Audio upload failed', e);
          }
          try {
            await postRepository.addPostMedia(_pendingPostId!, audioUrl, mediaType: 'audio');
          } catch (e) {
            throw _labeled('Attaching audio failed', e);
          }
        }
        if (document != null) {
          String docUrl;
          try {
            docUrl = await postRepository.uploadPostDocument(_pendingPostId!, document!);
          } catch (e) {
            throw _labeled('Document upload failed', e);
          }
          try {
            await postRepository.addPostMedia(_pendingPostId!, docUrl, mediaType: 'document');
          } catch (e) {
            throw _labeled('Attaching document failed', e);
          }
        }
      }

      try {
        await postRepository.finalizePost(_pendingPostId!);
      } catch (e) {
        // Post + media are genuinely fine at this point — only the "mark
        // it visible" flag failed. Don't clear the composer or navigate;
        // a retry re-enters the resume branch above (updatePendingPost,
        // no re-uploads) and just retries this call.
        throw _labeled('Finalizing post failed', e);
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
      final session = SupabaseConfig.maybeClient?.auth.currentSession;
      final secondsLeft = session?.expiresAt == null
          ? null
          : session!.expiresAt! - (DateTime.now().millisecondsSinceEpoch ~/ 1000);
      final jwtPayload = session == null ? null : _decodeJwtPayload(session.accessToken);
      BetaErrorLoggingService.instance.record(e, stackTrace,
        context: 'post_creation_submit',
        metadata: {
          'community_id': widget.communityId,
          'had_session': session != null,
          'token_seconds_left_at_failure': secondsLeft,
          // The decisive check: does the token actually being sent carry
          // the same user we think is logged in and posting? A mismatch
          // here (or a null role/sub) would explain an RLS 403/400 that
          // otherwise looks inexplicable, since Postgres would correctly
          // reject a request authenticated as someone other than the
          // post's author.
          'jwt_sub': jwtPayload?['sub'],
          'jwt_role': jwtPayload?['role'],
          'expected_author_id': uid,
          'jwt_sub_matches_author': jwtPayload?['sub'] == uid,
        },
      );

      if (mounted) {
        final message = _friendlyError(e);
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

  /// Same validation/upload flow as _publish, but writes to
  /// scheduled_posts instead of posts. Polls/events aren't supported for
  /// scheduling yet (they need their own follow-up rows created
  /// atomically with the post, which the cron publisher doesn't do) —
  /// the UI hides the Schedule option whenever a poll/event is attached.
  Future<void> _schedule() async {
    final uid = SupabaseConfig.client.auth.currentUser?.id;
    if (uid == null) {
      if (mounted) context.go('/login?redirect=${Uri.encodeComponent(_redirectLocation)}');
      return;
    }
    final scheduledFor = _scheduledFor;
    if (scheduledFor == null) return;
    if (scheduledFor.isBefore(DateTime.now().add(const Duration(minutes: 1)))) {
      if (mounted) setState(() => err = 'Scheduled time must be at least a minute from now.');
      return;
    }
    if (text.text.trim().isEmpty && image == null && video == null && audio == null && document == null) {
      if (mounted) setState(() => err = 'Add text or media to schedule');
      return;
    }
    if (pollDraft != null || eventDraft != null) {
      if (mounted) setState(() => err = 'Polls and events can\'t be scheduled yet — publish now instead.');
      return;
    }

    if (mounted) setState(() { loading = true; err = null; });

    try {
      final scheduledRepo = ScheduledPostRepository();
      final scheduled = await scheduledRepo.create(
        userId: uid,
        communityId: widget.communityId,
        textContent: text.text.trim(),
        visibility: _visibility,
        contentType: _resolvedContentType,
        tags: _parsedTags,
        location: location.text.trim().isEmpty ? null : location.text.trim(),
        locationLat: _pickedLat,
        locationLng: _pickedLng,
        feeling: _feeling?.stored,
        scheduledAt: scheduledFor,
        clientTimezone: DateTime.now().timeZoneName,
      );

      final media = <Map<String, dynamic>>[];
      if (video != null) {
        final url = await scheduledRepo.uploadVideo(scheduled.id, video!);
        media.add({'media_url': url, 'media_type': 'video'});
      }
      if (image != null) {
        final uploaded = await scheduledRepo.uploadImage(scheduled.id, image!);
        media.add({'media_url': uploaded.originalUrl, 'thumbnail_url': uploaded.thumbnailUrl, 'media_type': 'image'});
      }
      if (audio != null) {
        final url = await scheduledRepo.uploadAudio(scheduled.id, audio!);
        media.add({'media_url': url, 'media_type': 'audio'});
      }
      if (document != null) {
        final url = await scheduledRepo.uploadDocument(scheduled.id, document!);
        media.add({'media_url': url, 'media_type': 'document'});
      }
      if (media.isNotEmpty) await scheduledRepo.attachMedia(scheduled.id, media);

      _published = true;
      unawaited(PostRepository().deleteDraft(userId: uid, communityId: widget.communityId).catchError((_) {}));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Post scheduled')),
        );
        context.go('/scheduled-posts');
      }
    } catch (e, stackTrace) {
      BetaErrorLoggingService.instance.record(e, stackTrace, context: 'post_scheduling_submit', metadata: {'community_id': widget.communityId});
      if (mounted) setState(() => err = _friendlyError(e).replaceFirst('Upload failed', 'Scheduling failed'));
    } finally {
      if (mounted) setState(() => loading = false);
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
    // id -> username. This is the sheet's working copy; it's only
    // committed to _taggedFriends if the sheet is dismissed normally.
    final selected = Map<String, String>.from(_taggedFriends);
    var results = <Map<String, dynamic>>[];
    var loading = true;
    var loadedDefault = false;
    var searchError = false;
    Timer? debounce;
    // Bumped on every new search kicked off; a response is only applied
    // if it's still the *latest* generation by the time it lands, so a
    // slow "a" response can never overwrite a faster "alice" response.
    var generation = 0;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          if (!loadedDefault) {
            loadedDefault = true;
            final myGeneration = ++generation;
            ProfileRepository().followingUsers(uid).then((people) {
              if (myGeneration != generation) return; // superseded
              results = people;
              loading = false;
              setSheetState(() {});
            }).catchError((_) {
              if (myGeneration != generation) return;
              loading = false;
              searchError = true;
              setSheetState(() {});
            });
          }

          Future<void> runSearch(String q) async {
            final myGeneration = ++generation;
            try {
              final found = q.trim().isEmpty
                  ? await ProfileRepository().followingUsers(uid)
                  : await ProfileRepository().searchUsersByUsername(q.trim());
              if (myGeneration != generation) return; // a newer search landed first — drop this one
              results = found;
              loading = false;
              searchError = false;
              setSheetState(() {});
            } catch (_) {
              if (myGeneration != generation) return;
              loading = false;
              searchError = true;
              setSheetState(() {});
            }
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
                    onChanged: (q) {
                      debounce?.cancel();
                      loading = true;
                      setSheetState(() {});
                      // ~300ms debounce — avoids firing a search on every
                      // keystroke while still feeling responsive.
                      debounce = Timer(const Duration(milliseconds: 300), () => runSearch(q));
                    },
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: loading
                        ? const Center(child: CircularProgressIndicator())
                        : searchError
                            ? const Center(child: Text('Search failed — check your connection and try again'))
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
                                      final isSelected = selected.containsKey(id);
                                      return CheckboxListTile(
                                        value: isSelected,
                                        secondary: ProfileAvatar(url: person['profile_photo_url'] as String?, radius: 16),
                                        title: Text(name),
                                        onChanged: (checked) {
                                          setSheetState(() {
                                            if (checked == true) {
                                              selected[id] = name;
                                            } else {
                                              selected.remove(id);
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
    debounce?.cancel();

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

  Future<void> _pickImage(ImageSource source) async {
    final picked = await ImagePicker().pickImage(source: source);
    if (picked == null) return;
    final safe = await materializeIfWeb(picked);
    if (mounted) setState(() { image = safe; pollDraft = null; eventDraft = null; });
  }

  Future<void> _pickVideo(ImageSource source) async {
    final picked = await ImagePicker().pickVideo(source: source, maxDuration: const Duration(minutes: 5));
    if (picked == null) return;
    final safe = await materializeIfWeb(picked);
    if (mounted) setState(() { video = safe; pollDraft = null; eventDraft = null; });
  }

  Future<void> _pickAudio() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp3', 'm4a', 'aac', 'wav'],
      withData: true,
    );
    final picked = result?.files.single;
    if (picked == null) return;
    if (mounted) setState(() { audio = picked; pollDraft = null; eventDraft = null; });
  }

  Future<void> _pickDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'doc', 'docx'],
      withData: true,
    );
    final picked = result?.files.single;
    if (picked == null) return;
    if (mounted) setState(() { document = picked; pollDraft = null; eventDraft = null; });
  }

  /// Photo and video can each come from the camera or the gallery — this
  /// sheet is the one extra tap that unlocks "take a photo/video right
  /// now" instead of only ever picking something already saved.
  Future<void> _showCameraSheet() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(sheetContext, 'photo'),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Record a video'),
              onTap: () => Navigator.pop(sheetContext, 'video'),
            ),
          ],
        ),
      ),
    );
    if (choice == 'photo') await _pickImage(ImageSource.camera);
    if (choice == 'video') await _pickVideo(ImageSource.camera);
  }

  /// Human-readable file size for the document/audio preview chip, e.g.
  /// "1.4 MB" — PlatformFile.size is already known synchronously (no
  /// disk read needed), so this is cheap to compute on every rebuild.
  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Widget _attachTile(BuildContext context, {required IconData icon, required String label, required VoidCallback onTap, bool active = false}) {
    final theme = Theme.of(context);
    final color = active ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 72,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
        decoration: BoxDecoration(
          color: active ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4) : null,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? theme.colorScheme.primary : theme.colorScheme.outlineVariant),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(label, style: theme.textTheme.labelSmall?.copyWith(color: color), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _attachmentPreviewChip(BuildContext context, {required Widget leading, required String title, String? subtitle, required VoidCallback onRemove}) {
    final theme = Theme.of(context);
    return Container(
      width: 140,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (subtitle != null) Text(subtitle, style: theme.textTheme.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          InkWell(
            onTap: onRemove,
            child: Icon(Icons.close, size: 16, color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
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
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  FormatToolbar(controller: text, onChanged: _onTextChanged, focusNode: _textFocus),
                  Container(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
                  TextField(
                    controller: text,
                    focusNode: _textFocus,
                    minLines: 3,
                    maxLines: 8,
                    maxLength: _maxLength,
                    onChanged: _onTextChanged,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.all(12),
                      hintText: "What's on your mind?",
                      helperText: _draftSaving
                          ? 'Saving draft…'
                          : _draftSavedAt != null
                              ? 'Draft saved'
                              : null,
                    ),
                  ),
                ],
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
              options: _effectiveVisibilityOptions,
              onChanged: (v) => setState(() => _visibility = v),
            ),
            const SizedBox(height: 8),
            _SchedulePicker(
              value: _scheduledFor,
              onChanged: (v) => setState(() => _scheduledFor = v),
            ),
            const SizedBox(height: 12),
            if (_loadingQuote) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator()),
            if (_quotedPost != null) ...[
              _QuotedPostPreviewCard(post: _quotedPost!),
              const SizedBox(height: 12),
            ],
            Text('Add to your post', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _attachTile(context, icon: Icons.photo_camera_outlined, label: 'Camera', onTap: _showCameraSheet),
                  const SizedBox(width: 8),
                  _attachTile(context, icon: Icons.image_outlined, label: 'Photo', active: image != null, onTap: () => _pickImage(ImageSource.gallery)),
                  const SizedBox(width: 8),
                  _attachTile(context, icon: Icons.videocam_outlined, label: 'Video', active: video != null, onTap: () => _pickVideo(ImageSource.gallery)),
                  const SizedBox(width: 8),
                  _attachTile(context, icon: Icons.audiotrack_outlined, label: 'Audio', active: audio != null, onTap: _pickAudio),
                  const SizedBox(width: 8),
                  _attachTile(context, icon: Icons.description_outlined, label: 'Document', active: document != null, onTap: _pickDocument),
                  const SizedBox(width: 8),
                  _attachTile(
                    context,
                    icon: Icons.poll_outlined,
                    label: 'Poll',
                    active: pollDraft != null,
                    onTap: () async {
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
                  ),
                  const SizedBox(width: 8),
                  _attachTile(
                    context,
                    icon: Icons.event_outlined,
                    label: 'Event',
                    active: eventDraft != null,
                    onTap: () async {
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
                  ),
                ],
              ),
            ),
            if (image != null || video != null || audio != null || document != null || pollDraft != null || eventDraft != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 60,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    if (image != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _attachmentPreviewChip(
                          context,
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: SizedBox(width: 40, height: 40, child: PickedImagePreview(bytesFuture: image!.readAsBytes())),
                          ),
                          title: 'Photo',
                          onRemove: () => setState(() => image = null),
                        ),
                      ),
                    if (video != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _attachmentPreviewChip(
                          context,
                          leading: const Icon(Icons.videocam, size: 28),
                          title: 'Video',
                          subtitle: 'up to 5 min',
                          onRemove: () => setState(() => video = null),
                        ),
                      ),
                    if (audio != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _attachmentPreviewChip(
                          context,
                          leading: const Icon(Icons.audiotrack, size: 28),
                          title: audio!.name,
                          subtitle: _formatFileSize(audio!.size),
                          onRemove: () => setState(() => audio = null),
                        ),
                      ),
                    if (document != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _attachmentPreviewChip(
                          context,
                          leading: const Icon(Icons.description, size: 28),
                          title: document!.name,
                          subtitle: _formatFileSize(document!.size),
                          onRemove: () => setState(() => document = null),
                        ),
                      ),
                    if (pollDraft != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _attachmentPreviewChip(
                          context,
                          leading: const Icon(Icons.poll, size: 28),
                          title: pollDraft!.question,
                          subtitle: '${pollDraft!.options.length} options${pollDraft!.expiresAt != null ? ' · ends ${_formatPollEnd(pollDraft!.expiresAt!)}' : ''}',
                          onRemove: () => setState(() => pollDraft = null),
                        ),
                      ),
                    if (eventDraft != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _attachmentPreviewChip(
                          context,
                          leading: const Icon(Icons.event, size: 28),
                          title: eventDraft!.title,
                          onRemove: () => setState(() => eventDraft = null),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            Text('More options', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
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
                children: _taggedFriends.entries
                    .map((e) => Chip(
                          label: Text('@${e.value}'),
                          onDeleted: () => setState(() => _taggedFriends.remove(e.key)),
                        ))
                    .toList(),
              ),
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
            const SizedBox(height: 12),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: loading ? null : _publish,
            child: loading
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_scheduledFor != null ? 'Schedule' : 'Publish'),
          ),
        ),
      ),
    );
  }
}

/// Lets the user pick a future date/time to publish at instead of posting
/// immediately (Step 10). Uses the device's local timezone throughout —
/// showDatePicker/showTimePicker both work in local time, and the result
/// is converted to UTC only when sent to the server (see
/// ScheduledPostRepository.create), so what the user picks ("9:00 AM") is
/// exactly what they meant in their own timezone.
class _SchedulePicker extends StatelessWidget {
  const _SchedulePicker({required this.value, required this.onChanged});
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    final v = value;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.schedule_outlined),
            label: Text(v == null ? 'Publish now' : 'Scheduled for ${_format(v)}'),
            onPressed: () async {
              final now = DateTime.now();
              final date = await showDatePicker(
                context: context,
                initialDate: v ?? now.add(const Duration(minutes: 5)),
                firstDate: now,
                lastDate: now.add(const Duration(days: 365)),
              );
              if (date == null || !context.mounted) return;
              final time = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(v ?? now.add(const Duration(minutes: 5))),
              );
              if (time == null) return;
              onChanged(DateTime(date.year, date.month, date.day, time.hour, time.minute));
            },
          ),
        ),
        if (v != null)
          IconButton(icon: const Icon(Icons.close), tooltip: 'Publish immediately instead', onPressed: () => onChanged(null)),
      ],
    );
  }

  String _format(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.month)}/${two(d.day)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
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
  DateTime? expiresAt = existing?.expiresAt;

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
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.timer_outlined),
                title: Text(expiresAt == null ? 'No end time' : 'Ends ${_formatPollEnd(expiresAt!)}'),
                subtitle: const Text('Optional — voting closes automatically'),
                trailing: expiresAt == null
                    ? null
                    : IconButton(icon: const Icon(Icons.close), onPressed: () => setSheetState(() => expiresAt = null)),
                onTap: () async {
                  final now = DateTime.now();
                  final date = await showDatePicker(
                    context: sheetContext,
                    initialDate: expiresAt ?? now.add(const Duration(hours: 24)),
                    firstDate: now,
                    lastDate: now.add(const Duration(days: 30)),
                  );
                  if (date == null || !sheetContext.mounted) return;
                  final time = await showTimePicker(context: sheetContext, initialTime: TimeOfDay.fromDateTime(expiresAt ?? now.add(const Duration(hours: 24))));
                  if (time == null) return;
                  setSheetState(() => expiresAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
                },
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
                  if (expiresAt != null && expiresAt!.isBefore(DateTime.now().add(const Duration(minutes: 1)))) {
                    ScaffoldMessenger.of(sheetContext).showSnackBar(
                      const SnackBar(content: Text('End time must be in the future.')),
                    );
                    return;
                  }
                  Navigator.pop(sheetContext, _PollDraft(question: q, options: opts, allowMultiple: allowMultiple, isAnonymous: isAnonymous, expiresAt: expiresAt));
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

String _formatPollEnd(DateTime dt) {
  final local = dt.toLocal();
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final ampm = local.hour >= 12 ? 'PM' : 'AM';
  return '${months[local.month - 1]} ${local.day}, ${hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')} $ampm';
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
  _PollDraft({required this.question, required this.options, this.allowMultiple = false, this.isAnonymous = true, this.expiresAt});
  final String question;
  final List<String> options;
  final bool allowMultiple;
  final bool isAnonymous;
  final DateTime? expiresAt;
}

class _EventDraft {
  _EventDraft({required this.title, required this.startsAt, this.locationText, this.onlineUrl});
  final String title;
  final DateTime startsAt;
  final String? locationText;
  final String? onlineUrl;
}
