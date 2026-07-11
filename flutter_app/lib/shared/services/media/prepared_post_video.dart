import 'package:supabase_flutter/supabase_flutter.dart';

/// A video picked for a post, prepared for upload.
///
/// Same seam as [PreparedPostImage]: mobile implementations hold a `File`
/// and call `storageApi.upload(...)`, the Web implementation holds raw
/// bytes and calls `storageApi.uploadBinary(...)`. Callers never need to
/// know which — they just call [uploadTo].
///
/// This file must stay free of `dart:io` so it can be safely imported from
/// Web builds.
abstract class PreparedPostVideo {
  String get contentType;

  Future<void> uploadTo(StorageFileApi storageApi, String path, FileOptions options);
}
