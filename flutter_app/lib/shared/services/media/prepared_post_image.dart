import 'package:supabase_flutter/supabase_flutter.dart';

/// A single image (either the full-size original or the thumbnail) that has
/// been prepared for upload.
///
/// This is the seam between platforms: mobile implementations hold a
/// [`File`] and call `storageApi.upload(...)`, while the Web implementation
/// holds raw bytes and calls `storageApi.uploadBinary(...)`. Callers never
/// need to know which — they just call [uploadTo].
///
/// This file must stay free of `dart:io` and `path_provider` imports so it
/// can be safely imported from Web builds.
abstract class PreparedPostImage {
  String get contentType;

  Future<void> uploadTo(StorageFileApi storageApi, String path, FileOptions options);
}

/// The original + thumbnail pair produced for a single picked image, ready
/// to be pushed to Supabase Storage.
class PreparedImageSet {
  const PreparedImageSet({
    required this.original,
    required this.thumbnail,
    required this.contentType,
  });

  final PreparedPostImage original;
  final PreparedPostImage thumbnail;
  final String contentType;
}
