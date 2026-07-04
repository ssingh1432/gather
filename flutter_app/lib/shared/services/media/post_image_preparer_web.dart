// Flutter Web image preparer.
//
// This file is only ever compiled when `dart:html` exists (Web) — it is
// selected via the conditional import in `post_image_preparer.dart`.
//
// Deliberately does NOT import `dart:io` or `path_provider`: Flutter Web has
// no writable filesystem and no `path_provider` platform-channel
// implementation, which is exactly what caused the original
// `MissingPluginException` on "Create Post". Everything here stays in
// memory as bytes.
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'prepared_post_image.dart';

const String _defaultContentType = 'image/jpeg';

class _WebPreparedPostImage implements PreparedPostImage {
  const _WebPreparedPostImage(this.bytes, this.contentType);

  final Uint8List bytes;

  @override
  final String contentType;

  @override
  Future<void> uploadTo(StorageFileApi storageApi, String path, FileOptions options) {
    return storageApi.uploadBinary(path, bytes, fileOptions: options);
  }
}

/// Reads the picked image straight into memory with [XFile.readAsBytes]
/// and uploads the raw bytes via `uploadBinary`.
///
/// There is no equivalent of `flutter_image_compress`'s native codec path
/// on Web, so no client-side compression/resizing happens here — the same
/// bytes are used for both the "original" and "thumbnail" storage objects.
/// This keeps Create Post working correctly on Web; if a distinct
/// thumbnail is desired later, generate it server-side (e.g. a Supabase
/// Storage image-transform or an edge function) rather than reintroducing
/// platform-unsafe client code.
Future<PreparedImageSet> preparePostImage(XFile image) async {
  final bytes = await image.readAsBytes();
  final contentType = _resolveContentType(image);

  return PreparedImageSet(
    original: _WebPreparedPostImage(bytes, contentType),
    thumbnail: _WebPreparedPostImage(bytes, contentType),
    contentType: contentType,
  );
}

String _resolveContentType(XFile image) {
  final mimeType = image.mimeType;
  if (mimeType != null && mimeType.isNotEmpty) return mimeType;

  final name = image.name.toLowerCase();
  if (name.endsWith('.png')) return 'image/png';
  if (name.endsWith('.webp')) return 'image/webp';
  if (name.endsWith('.gif')) return 'image/gif';
  return _defaultContentType;
}
