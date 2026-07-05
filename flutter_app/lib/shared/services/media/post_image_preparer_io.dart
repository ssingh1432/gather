// Mobile/desktop image preparer.
//
// This file is only ever compiled for targets where `dart:io` exists
// (Android, iOS, desktop) — it is selected via the conditional import in
// `post_image_preparer.dart` and is never part of the Flutter Web bundle.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'media_upload_exception.dart';
import 'prepared_post_image.dart';

const int _maxImageWidth = 1080;
const int _thumbnailWidth = 360;
const int _jpegQuality = 84;
const int _thumbnailQuality = 72;
const String _contentType = 'image/jpeg';

class _IoPreparedPostImage implements PreparedPostImage {
  const _IoPreparedPostImage(this.file);

  final File file;

  @override
  String get contentType => _contentType;

  @override
  Future<void> uploadTo(StorageFileApi storageApi, String path, FileOptions options) {
    return storageApi.upload(path, file, fileOptions: options);
  }
}

/// Compresses the picked image into a temp-file original + thumbnail pair
/// using the native codec path (`flutter_image_compress`). Temp files live
/// under [getTemporaryDirectory] and are safe to leave behind — the OS
/// reclaims temp storage, and callers never need to delete them explicitly.
Future<PreparedImageSet> preparePostImage(XFile image) async {
  final tempDir = await getTemporaryDirectory();
  final token = '${DateTime.now().microsecondsSinceEpoch}_${math.Random().nextInt(1 << 32)}';
  final originalPath = p.join(tempDir.path, 'post_original_$token.jpg');
  final thumbnailPath = p.join(tempDir.path, 'post_thumb_$token.jpg');

  final original = await FlutterImageCompress.compressAndGetFile(
    image.path,
    originalPath,
    minWidth: _maxImageWidth,
    quality: _jpegQuality,
    format: CompressFormat.jpeg,
    keepExif: false,
  );
  final thumbnail = await FlutterImageCompress.compressAndGetFile(
    image.path,
    thumbnailPath,
    minWidth: _thumbnailWidth,
    quality: _thumbnailQuality,
    format: CompressFormat.jpeg,
    keepExif: false,
  );

  if (original == null || thumbnail == null) {
    throw const MediaUploadException(
      'Could not optimize the selected image. Please try another image.',
    );
  }

  return PreparedImageSet(
    original: _IoPreparedPostImage(File(original.path)),
    thumbnail: _IoPreparedPostImage(File(thumbnail.path)),
    contentType: _contentType,
  );
}
