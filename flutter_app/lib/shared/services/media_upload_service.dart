import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';
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

  SupabaseClient get _client => SupabaseConfig.client;

  /// Prepares [image] for upload. On mobile this compresses to temp files;
  /// on Web it reads the raw bytes. See `media/post_image_preparer.dart`.
  Future<PreparedImageSet> preparePostImage(XFile image) => preparer.preparePostImage(image);

  /// Prepares a picked video for upload — same io/File-vs-Web/bytes seam as
  /// [preparePostImage], but with no client-side re-encoding (videos are
  /// uploaded as picked). See `media/post_video_preparer.dart`.
  Future<PreparedPostVideo> preparePostVideo(XFile video) => video_preparer.preparePostVideo(video);

  /// Uploads a post video to `posts/{postId}/video`. Deterministic path +
  /// upsert mirrors [uploadPostImage] so a retried publish overwrites the
  /// same object instead of orphaning duplicates.
  Future<String> uploadPostVideo({
    required String postId,
    required PreparedPostVideo video,
  }) async {
    final options = FileOptions(contentType: video.contentType, cacheControl: '31536000', upsert: true);
    final storage = _client.storage.from(bucket);
    final path = 'posts/$postId/video';
    await video.uploadTo(storage, path, options);
    return storage.getPublicUrl(path);
  }

  Future<UploadedPostImage> uploadPostImage({
    required String postId,
    required PreparedImageSet image,
  }) async {
    final options = FileOptions(
      contentType: image.contentType,
      cacheControl: '31536000',
      upsert: true,
    );
    final storage = _client.storage.from(bucket);
    final originalPath = 'posts/$postId/original';
    final thumbPath = 'posts/$postId/thumb';

    // Deterministic paths plus upsert make a failed publish retry-safe: the
    // next attempt overwrites the same objects instead of orphaning
    // duplicate files. Each PreparedPostImage decides for itself whether to
    // call `.upload()` (mobile, File) or `.uploadBinary()` (Web, bytes) —
    // this call site stays identical across platforms.
    await image.original.uploadTo(storage, originalPath, options);
    await image.thumbnail.uploadTo(storage, thumbPath, options);

    return UploadedPostImage(
      originalUrl: storage.getPublicUrl(originalPath),
      thumbnailUrl: storage.getPublicUrl(thumbPath),
    );
  }

  /// Uploads a profile avatar or cover photo to the `avatars` bucket, scoped
  /// to `{userId}/{kind}` so storage RLS (folder == auth.uid()) allows it.
  /// Reuses the same platform-safe prepare pipeline as post images.
  Future<String> uploadProfileImage({
    required String userId,
    required XFile image,
    required ProfileImageKind kind,
  }) async {
    final prepared = await preparePostImage(image);
    final options = FileOptions(
      contentType: prepared.contentType,
      cacheControl: '31536000',
      upsert: true,
    );
    final storage = _client.storage.from(avatarsBucket);
    final path = '$userId/${kind.name}';

    // Only the original is needed for profile images; skip the thumbnail
    // upload to save a storage call.
    await prepared.original.uploadTo(storage, path, options);
    return storage.getPublicUrl(path);
  }

  /// Uploads a story's media to `{userId}/{storyId}` in the `story-media`
  /// bucket — user-scoped path (not post-scoped) so storage RLS can check
  /// folder == auth.uid(), same convention as the avatars bucket.
  Future<String> uploadStoryImage({required String userId, required String storyId, required PreparedImageSet image}) async {
    final options = FileOptions(contentType: image.contentType, cacheControl: '86400', upsert: true);
    final storage = _client.storage.from(storyBucket);
    final path = '$userId/$storyId';
    await image.original.uploadTo(storage, path, options);
    return storage.getPublicUrl(path);
  }

  Future<String> uploadStoryVideo({required String userId, required String storyId, required PreparedPostVideo video}) async {
    final options = FileOptions(contentType: video.contentType, cacheControl: '86400', upsert: true);
    final storage = _client.storage.from(storyBucket);
    final path = '$userId/$storyId';
    await video.uploadTo(storage, path, options);
    return storage.getPublicUrl(path);
  }
}

enum ProfileImageKind { avatar, cover }
