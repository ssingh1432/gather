import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';
import 'media/media_upload_exception.dart';
import 'media/post_image_preparer.dart' as preparer;
import 'media/post_video_preparer.dart' as video_preparer;
import 'media/prepared_post_image.dart';
import 'media/prepared_post_video.dart';

export 'media/media_upload_exception.dart';
export 'media/prepared_post_image.dart' show PreparedImageSet;

/// Public model returned once both storage objects for a post image have
/// been uploaded. Identical on every platform.
class UploadedPostImage {
  const UploadedPostImage({required this.originalUrl, required this.thumbnailUrl});

  final String originalUrl;
  final String thumbnailUrl;
}

/// Platform-safe media upload service used by [FeedRepository]/
/// `create_post_screen.dart`.
///
/// This file — and everything it imports directly — never imports
/// `dart:io` or `path_provider`. Platform-specific work (temp-file
/// compression on mobile vs. in-memory bytes on Web) lives behind
/// [preparePostImage], which resolves to the correct implementation via a
/// conditional import in `media/post_image_preparer.dart`. That is what
/// fixes the `MissingPluginException: getTemporaryDirectory` crash on
/// Flutter Web, since the Web build never links `path_provider` at all.
class MediaUploadService {
  static const String bucket = 'post-media';
  static const String avatarsBucket = 'avatars';
  static const String storyBucket = 'story-media';
  static const String evidenceBucket = 'moderation-evidence';
  static const String communityMediaBucket = 'community-media';
  static const String communityChatMediaBucket = 'community-chat-media';
  static const String pageMediaBucket = 'page-media';

  // Mirrors the file_size_limit set on each Supabase Storage bucket, so we
  // can reject an oversized pick instantly instead of letting the user
  // wait through compression/upload only for the server to reject it.
  // These are a client-side courtesy, not the enforcement boundary — the
  // bucket limits are what actually protect storage/bandwidth, since a
  // client can always be bypassed.
  static const int maxPostMediaBytes = 100 * 1024 * 1024; // 100MB — post-media, story-media
  static const int maxAvatarBytes = 5 * 1024 * 1024; // 5MB — avatars
  static const int maxCommunityImageBytes = 5 * 1024 * 1024; // 5MB — community-media
  static const int maxPageImageBytes = 10 * 1024 * 1024; // 10MB — page-media (matches bucket file_size_limit, migration 074)
  static const int maxEvidenceBytes = 20 * 1024 * 1024; // 20MB — moderation-evidence
  static const int maxAudioBytes = 20 * 1024 * 1024; // 20MB — matches story-audio bucket limit
  static const int maxDocumentBytes = 25 * 1024 * 1024; // 25MB
  static const int maxChatMediaBytes = 15 * 1024 * 1024; // 15MB — matches community-chat-media bucket limit

  static Future<void> _assertWithinLimit(XFile file, int maxBytes, String label) async {
    final size = await file.length();
    if (size > maxBytes) {
      final maxMb = (maxBytes / (1024 * 1024)).toStringAsFixed(0);
      throw MediaUploadException('$label must be $maxMb MB or smaller.');
    }
  }

  /// Same check as [_assertWithinLimit] but for `file_picker`'s
  /// `PlatformFile`, whose size is already known synchronously.
  static void assertFileWithinLimit(PlatformFile file, int maxBytes, String label) {
    if (file.bytes == null) {
      throw const MediaUploadException('Could not read the selected file.');
    }
    if (file.size > maxBytes) {
      final maxMb = (maxBytes / (1024 * 1024)).toStringAsFixed(0);
      throw MediaUploadException('$label must be $maxMb MB or smaller.');
    }
  }

  SupabaseClient get _client => SupabaseConfig.client;

  /// Runs [action] (a storage upload), retrying once more after a forced
  /// session refresh if it fails with a 403, OR with a 400 whose body
  /// indicates a storage RLS rejection (see below), backing off briefly so
  /// the SDK has time to propagate the refreshed token before the retry.
  ///
  /// This used to force `auth.refreshSession()` unconditionally before
  /// *every* call, plus up to two more refreshes per call on 403 — a
  /// leftover from misdiagnosing a storage-RLS bug (see migration
  /// `fix_post_media_grants_and_policies` / the `can_upload_post_media`
  /// SECURITY DEFINER fix) as a token problem. A post with all four
  /// attachment types called this four times per publish, each one
  /// firing a real `TOKEN_REFRESHED` auth event — which
  /// `PushNotificationService`'s listener reacts to on every publish by
  /// writing a login-device row and re-syncing the FCM token. That's the
  /// concrete mechanism behind the "screen refreshes ~4 times and gets
  /// stuck" report: up to 4 extra network round trips competing with the
  /// actual uploads, not real UI rebuilds. Refreshing was made purely
  /// reactive — only after an upload had actually failed — as a fix for
  /// that.
  ///
  /// But that later turned out to be too narrow: production logs (post
  /// e55f6f05..., publish attempts spanning 2026-08-13 through
  /// 2026-08-14) showed the *same* post getting rejected by storage RLS
  /// on every single retry over many hours, even though
  /// `can_upload_post_media()` verifiably returns true for that exact
  /// post/author pair when evaluated directly in SQL. The only way both
  /// of those are true at once is that the live request's access token
  /// had gone stale (Flutter Web throttles JS timers — including the
  /// SDK's background auto-refresh — on a backgrounded/inactive browser
  /// tab, per https://developer.chrome.com/blog/timer-throttling-in-chrome-88/),
  /// and the old `!= '403'` check let a token-related 400 straight
  /// through unretried. So this now also proactively tops up the session
  /// before ever calling [action] (cheap no-op if the token still has
  /// plenty of life left — see [_ensureFreshSession]), and reactively
  /// retries on a 400 that looks like a storage-RLS rejection in addition
  /// to a 403. A second consecutive failure after that still means the
  /// session is unrecoverable client-side, so it's only ever retried once.
  Future<T> _withAuthRetry<T>(Future<T> Function() action) async {
    await _ensureFreshSession();
    try {
      return await action();
    } on StorageException catch (e) {
      final isForbidden = e.statusCode == '403';
      final isRlsRejection = e.statusCode == '400' &&
          e.message.toLowerCase().contains('row-level security');
      if (!isForbidden && !isRlsRejection) rethrow;
      try {
        await _client.auth.refreshSession();
      } catch (_) {
        // Refresh itself failed — the token is unrecoverable client-side;
        // let the retry below surface the real error instead of hiding
        // it behind a refresh exception.
      }
      await Future.delayed(const Duration(milliseconds: 300));
      return action();
    }
  }

  /// Tops up the session if the access token is at or near expiry (60s
  /// buffer, to cover the network round-trip the upload itself is about
  /// to make). No-ops entirely if the token is still fresh, or if there's
  /// no session at all (the caller's own auth check surfaces that error).
  /// This is what actually closes the backgrounded-tab gap described in
  /// [_withAuthRetry] above — refreshSession() is safe to call even when
  /// nothing needs refreshing yet, but we still gate on expiry so a fresh
  /// upload doesn't pay a network round trip it doesn't need.
  Future<void> _ensureFreshSession() async {
    final session = _client.auth.currentSession;
    if (session?.expiresAt == null) return;
    final secondsLeft = session!.expiresAt! - (DateTime.now().millisecondsSinceEpoch ~/ 1000);
    if (secondsLeft > 60) return;
    try {
      await _client.auth.refreshSession();
    } catch (_) {
      // Let the actual upload attempt surface the real failure below
      // rather than hiding it behind a refresh error here.
    }
  }

  /// Prepares [image] for upload. On mobile this compresses to temp files;
  /// on Web it reads the raw bytes. See `media/post_image_preparer.dart`.
  Future<PreparedImageSet> preparePostImage(XFile image) async {
    await _assertWithinLimit(image, maxPostMediaBytes, 'Image');
    return preparer.preparePostImage(image);
  }

  /// Prepares a picked video for upload — same io/File-vs-Web/bytes seam as
  /// [preparePostImage], but with no client-side re-encoding (videos are
  /// uploaded as picked). See `media/post_video_preparer.dart`.
  Future<PreparedPostVideo> preparePostVideo(XFile video) async {
    await _assertWithinLimit(video, maxPostMediaBytes, 'Video');
    return video_preparer.preparePostVideo(video);
  }

  /// Uploads a post video to `posts/{postId}/video`. Deterministic path +
  /// upsert mirrors [uploadPostImage] so a retried publish overwrites the
  /// same object instead of orphaning duplicates.
  Future<String> uploadPostVideo({
    required String postId,
    required PreparedPostVideo video,
  }) async {
    return _withAuthRetry(() async {
      final options = FileOptions(contentType: video.contentType, cacheControl: '31536000', upsert: true);
      final storage = _client.storage.from(bucket);
      final path = 'posts/$postId/video';
      await video.uploadTo(storage, path, options);
      return storage.getPublicUrl(path);
    });
  }

  Future<UploadedPostImage> uploadPostImage({
    required String postId,
    required PreparedImageSet image,
  }) async {
    return _withAuthRetry(() async {
      final options = FileOptions(
        contentType: image.contentType,
        cacheControl: '31536000',
        upsert: true,
      );
      final storage = _client.storage.from(bucket);
      final originalPath = 'posts/$postId/original';
      final thumbPath = 'posts/$postId/thumb';

      // Deterministic paths plus upsert make a failed publish retry-safe:
      // the next attempt overwrites the same objects instead of orphaning
      // duplicate files. Each PreparedPostImage decides for itself whether
      // to call `.upload()` (mobile, File) or `.uploadBinary()` (Web,
      // bytes) — this call site stays identical across platforms.
      await image.original.uploadTo(storage, originalPath, options);
      await image.thumbnail.uploadTo(storage, thumbPath, options);

      return UploadedPostImage(
        originalUrl: storage.getPublicUrl(originalPath),
        thumbnailUrl: storage.getPublicUrl(thumbPath),
      );
    });
  }

  /// Uploads a post audio or document file to `posts/{postId}/{kind}.{ext}`.
  /// Unlike image/video, these come from `file_picker` with `withData:
  /// true`, so bytes are already available on every platform — no
  /// io/web preparer split needed here.
  Future<String> uploadPostBinary({
    required String postId,
    required String kind, // 'audio' or 'document'
    required List<int> bytes,
    required String contentType,
    required String fileExtension,
  }) async {
    return _withAuthRetry(() async {
      final options = FileOptions(contentType: contentType, cacheControl: '31536000', upsert: true);
      final storage = _client.storage.from(bucket);
      final path = 'posts/$postId/$kind.$fileExtension';
      await storage.uploadBinary(path, Uint8List.fromList(bytes), fileOptions: options);
      return storage.getPublicUrl(path);
    });
  }


  /// to `{userId}/{kind}` so storage RLS (folder == auth.uid()) allows it.
  /// Reuses the same platform-safe prepare pipeline as post images.
  Future<String> uploadProfileImage({
    required String userId,
    required XFile image,
    required ProfileImageKind kind,
  }) async {
    await _assertWithinLimit(image, maxAvatarBytes, 'Profile image');
    final prepared = await preparer.preparePostImage(image);
    return _withAuthRetry(() async {
      final options = FileOptions(
        contentType: prepared.contentType,
        cacheControl: '31536000',
        upsert: true,
      );
      final storage = _client.storage.from(avatarsBucket);
      final path = '$userId/${kind.name}';

      // Only the original is needed for profile images; skip the
      // thumbnail upload to save a storage call.
      await prepared.original.uploadTo(storage, path, options);
      return storage.getPublicUrl(path);
    });
  }

  /// Uploads a community icon or banner to `{communityId}/{kind}` in the
  /// `community-media` bucket. Storage RLS (migration 050) only allows the
  /// community's owner/admin (or a site admin/mod) to write into a given
  /// community's folder, mirroring the avatars-bucket convention.
  Future<String> uploadCommunityImage({
    required String communityId,
    required XFile image,
    required CommunityImageKind kind,
  }) async {
    await _assertWithinLimit(image, maxCommunityImageBytes, 'Community image');
    final prepared = await preparer.preparePostImage(image);
    return _withAuthRetry(() async {
      final options = FileOptions(
        contentType: prepared.contentType,
        cacheControl: '31536000',
        upsert: true,
      );
      final storage = _client.storage.from(communityMediaBucket);
      final path = '$communityId/${kind.name}';
      await prepared.original.uploadTo(storage, path, options);
      return storage.getPublicUrl(path);
    });
  }

  /// Uploads a community event's cover image to
  /// `{communityId}/events/{eventId}/cover` in the `community-media` bucket.
  /// Path shape matches the storage RLS added in migration 062, which checks
  /// segment [1] (communityId) against `manage_events` and requires segment
  /// [2] to literally be `events`.
  Future<String> uploadEventCover({
    required String communityId,
    required String eventId,
    required XFile image,
  }) async {
    await _assertWithinLimit(image, maxCommunityImageBytes, 'Event cover image');
    final prepared = await preparer.preparePostImage(image);
    return _withAuthRetry(() async {
      final options = FileOptions(
        contentType: prepared.contentType,
        cacheControl: '31536000',
        upsert: true,
      );
      final storage = _client.storage.from(communityMediaBucket);
      final path = '$communityId/events/$eventId/cover';
      await prepared.original.uploadTo(storage, path, options);
      return storage.getPublicUrl(path);
    });
  }

  /// Uploads a Page's logo or cover image to `{pageId}/{kind}` in the
  /// `page-media` bucket. Storage RLS (migration 074) only allows a page's
  /// manage_content/manage_settings holders (or the owner) to write into
  /// that page's folder — same convention as community-media (050).
  Future<String> uploadPageImage({
    required String pageId,
    required XFile image,
    required PageImageKind kind,
  }) async {
    await _assertWithinLimit(image, maxPageImageBytes, 'Page image');
    final prepared = await preparer.preparePostImage(image);
    return _withAuthRetry(() async {
      final options = FileOptions(
        contentType: prepared.contentType,
        cacheControl: '31536000',
        upsert: true,
      );
      final storage = _client.storage.from(pageMediaBucket);
      final path = '$pageId/${kind.name}';
      await prepared.original.uploadTo(storage, path, options);
      return storage.getPublicUrl(path);
    });
  }

  /// Uploads a Page post's image to `{pageId}/posts/{postId}/{original,thumb}`
  /// in the `page-media` bucket. Same storage RLS as [uploadPageImage]
  /// (`can_manage_page_media`, migration 074) — it only checks path segment
  /// [1] == pageId, so any subpath (logo/cover/posts/...) is covered without
  /// a new storage policy.
  Future<UploadedPostImage> uploadPagePostImage({
    required String pageId,
    required String postId,
    required XFile image,
  }) async {
    await _assertWithinLimit(image, maxPageImageBytes, 'Post image');
    final prepared = await preparer.preparePostImage(image);
    return _withAuthRetry(() async {
      final options = FileOptions(contentType: prepared.contentType, cacheControl: '31536000', upsert: true);
      final storage = _client.storage.from(pageMediaBucket);
      final originalPath = '$pageId/posts/$postId/original';
      final thumbPath = '$pageId/posts/$postId/thumb';
      await prepared.original.uploadTo(storage, originalPath, options);
      await prepared.thumbnail.uploadTo(storage, thumbPath, options);
      return UploadedPostImage(
        originalUrl: storage.getPublicUrl(originalPath),
        thumbnailUrl: storage.getPublicUrl(thumbPath),
      );
    });
  }

  /// Uploads a Page event's cover image to `{pageId}/events/{eventId}/cover`
  /// in the `page-media` bucket — same storage RLS coverage as above.
  Future<String> uploadPageEventCover({
    required String pageId,
    required String eventId,
    required XFile image,
  }) async {
    await _assertWithinLimit(image, maxPageImageBytes, 'Event cover image');
    final prepared = await preparer.preparePostImage(image);
    return _withAuthRetry(() async {
      final options = FileOptions(contentType: prepared.contentType, cacheControl: '31536000', upsert: true);
      final storage = _client.storage.from(pageMediaBucket);
      final path = '$pageId/events/$eventId/cover';
      await prepared.original.uploadTo(storage, path, options);
      return storage.getPublicUrl(path);
    });
  }

  /// Uploads a story's media to `{userId}/{storyId}` in the `story-media`
  /// bucket — user-scoped path (not post-scoped) so storage RLS can check
  /// folder == auth.uid(), same convention as the avatars bucket.
  ///
  /// Also uploads the already-generated compressed thumbnail (same one used
  /// for post images) to `{userId}/{storyId}_thumb`, so the story bar can
  /// show the actual photo instead of just the poster's avatar.
  Future<UploadedStoryImage> uploadStoryImage({required String userId, required String storyId, required PreparedImageSet image}) async {
    return _withAuthRetry(() async {
      final options = FileOptions(contentType: image.contentType, cacheControl: '86400', upsert: true);
      final storage = _client.storage.from(storyBucket);
      final path = '$userId/$storyId';
      final thumbPath = '$userId/${storyId}_thumb';
      await image.original.uploadTo(storage, path, options);
      await image.thumbnail.uploadTo(storage, thumbPath, options);
      return UploadedStoryImage(
        originalUrl: storage.getPublicUrl(path),
        thumbnailUrl: storage.getPublicUrl(thumbPath),
      );
    });
  }

  /// Uploads a report-evidence screenshot to `{reportId}/{uploaderId}_{ts}.{ext}`
  /// in the private `moderation-evidence` bucket. Unlike the other upload
  /// methods, this bucket is NOT public (evidence can contain sensitive
  /// content), so this returns the storage **path**, not a public URL — the
  /// caller must go through [createEvidenceSignedUrl] to actually view it,
  /// which storage RLS restricts to the reporter and admins/mods (matching
  /// the moderation_evidence table's own RLS from migration 022).
  Future<String> uploadEvidenceImage({
    required String reportId,
    required String uploaderId,
    required XFile image,
  }) async {
    await _assertWithinLimit(image, maxEvidenceBytes, 'Evidence image');
    final prepared = await preparer.preparePostImage(image);
    return _withAuthRetry(() async {
      final options = FileOptions(contentType: prepared.contentType, cacheControl: '3600', upsert: false);
      final storage = _client.storage.from(evidenceBucket);
      final ext = prepared.contentType.contains('png') ? 'png' : 'jpg';
      final path = '$reportId/${uploaderId}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await prepared.original.uploadTo(storage, path, options);
      return path;
    });
  }

  /// Short-lived signed URL for viewing a private evidence object. RLS on
  /// storage.objects (migration 023) is what actually enforces who is
  /// allowed to succeed here — this just requests the URL.
  Future<String> createEvidenceSignedUrl(String path) async {
    return _withAuthRetry(() => _client.storage.from(evidenceBucket).createSignedUrl(path, 600));
  }

  /// Uploads a story video. There is no client-side video-frame extraction
  /// in this app yet (unlike images, which reuse the post-thumbnail
  /// pipeline), so video stories fall back to the author's avatar in the
  /// story bar rather than a real frame from the clip.
  Future<String> uploadStoryVideo({required String userId, required String storyId, required PreparedPostVideo video}) async {
    return _withAuthRetry(() async {
      final options = FileOptions(contentType: video.contentType, cacheControl: '86400', upsert: true);
      final storage = _client.storage.from(storyBucket);
      final path = '$userId/$storyId';
      await video.uploadTo(storage, path, options);
      return storage.getPublicUrl(path);
    });
  }
  /// Uploads a community chat image or video to
  /// `{communityId}/{senderId}/{timestamp}.{ext}` in the **private**
  /// `community-chat-media` bucket (migration 059). Unlike post/story media,
  /// chat attachments are not public — storage RLS only allows a community
  /// member (or admin/mod) to read them. This returns the storage **path**,
  /// not a public URL; callers must go through [createChatMediaSignedUrl] to
  /// actually render it, same convention as [uploadEvidenceImage].
  Future<String> uploadChatImage({
    required String communityId,
    required String senderId,
    required XFile image,
  }) async {
    await _assertWithinLimit(image, maxChatMediaBytes, 'Image');
    final prepared = await preparer.preparePostImage(image);
    return _withAuthRetry(() async {
      final options = FileOptions(contentType: prepared.contentType, cacheControl: '3600', upsert: false);
      final storage = _client.storage.from(communityChatMediaBucket);
      final ext = prepared.contentType.contains('png') ? 'png' : 'jpg';
      final path = '$communityId/$senderId/${DateTime.now().millisecondsSinceEpoch}.$ext';
      await prepared.original.uploadTo(storage, path, options);
      return path;
    });
  }

  Future<String> uploadChatVideo({
    required String communityId,
    required String senderId,
    required XFile video,
  }) async {
    await _assertWithinLimit(video, maxChatMediaBytes, 'Video');
    final prepared = await video_preparer.preparePostVideo(video);
    return _withAuthRetry(() async {
      final options = FileOptions(contentType: prepared.contentType, cacheControl: '3600', upsert: false);
      final storage = _client.storage.from(communityChatMediaBucket);
      final ext = prepared.contentType.split('/').last;
      final path = '$communityId/$senderId/${DateTime.now().millisecondsSinceEpoch}.$ext';
      await prepared.uploadTo(storage, path, options);
      return path;
    });
  }

  /// Uploads a chat document/file (from `file_picker`, bytes already in
  /// memory on every platform — no io/web preparer split needed).
  Future<String> uploadChatDocument({
    required String communityId,
    required String senderId,
    required PlatformFile file,
  }) async {
    assertFileWithinLimit(file, maxChatMediaBytes, 'File');
    return _withAuthRetry(() async {
      final safeName = file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final options = FileOptions(cacheControl: '3600', upsert: false);
      final storage = _client.storage.from(communityChatMediaBucket);
      final path = '$communityId/$senderId/${DateTime.now().millisecondsSinceEpoch}_$safeName';
      await storage.uploadBinary(path, file.bytes!, fileOptions: options);
      return path;
    });
  }

  /// Short-lived signed URL for viewing a private chat attachment. Storage
  /// RLS (migration 059) is the real gate — this just requests the URL.
  /// 1 hour is long enough to cover a scroll session without re-signing on
  /// every rebuild, while still expiring if the URL is ever shared outside
  /// the app.
  Future<String> createChatMediaSignedUrl(String path) async {
    return _withAuthRetry(() => _client.storage.from(communityChatMediaBucket).createSignedUrl(path, 3600));
  }
}

/// Result of uploading a story image: the full-size original plus a
/// compressed thumbnail for use in the story bar.
class UploadedStoryImage {
  const UploadedStoryImage({required this.originalUrl, required this.thumbnailUrl});

  final String originalUrl;
  final String thumbnailUrl;
}

enum ProfileImageKind { avatar, cover }

/// Distinguishes the two image slots a community/page can have: a square
/// `icon` (shown in lists/cards) and a wide `banner` (shown at the top of
/// the community detail screen), matching `ProfileImageKind`'s avatar/cover
/// split.
enum CommunityImageKind { icon, banner }

enum PageImageKind { logo, cover }
