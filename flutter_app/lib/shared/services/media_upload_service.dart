import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';
import 'media/post_image_preparer.dart' as preparer;
import 'media/prepared_post_image.dart';

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

  SupabaseClient get _client => SupabaseConfig.client;

  /// Prepares [image] for upload. On mobile this compresses to temp files;
  /// on Web it reads the raw bytes. See `media/post_image_preparer.dart`.
  Future<PreparedImageSet> preparePostImage(XFile image) => preparer.preparePostImage(image);

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
}
