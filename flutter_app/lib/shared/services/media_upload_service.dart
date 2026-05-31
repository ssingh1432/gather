import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';

class PreparedPostImage {
  const PreparedPostImage({
    required this.originalFile,
    required this.thumbnailFile,
    required this.contentType,
  });

  final File originalFile;
  final File thumbnailFile;
  final String contentType;
}

class UploadedPostImage {
  const UploadedPostImage({required this.originalUrl, required this.thumbnailUrl});

  final String originalUrl;
  final String thumbnailUrl;
}

class MediaUploadService {
  static const int maxImageWidth = 1080;
  static const int thumbnailWidth = 360;
  static const int jpegQuality = 84;
  static const int thumbnailQuality = 72;
  static const String bucket = 'post-media';

  SupabaseClient get _client => SupabaseConfig.client;

  Future<PreparedPostImage> preparePostImage(XFile image) async {
    final tempDir = await getTemporaryDirectory();
    final token = '${DateTime.now().microsecondsSinceEpoch}_${math.Random().nextInt(1 << 32)}';
    final originalPath = p.join(tempDir.path, 'post_original_$token.jpg');
    final thumbnailPath = p.join(tempDir.path, 'post_thumb_$token.jpg');

    final original = await FlutterImageCompress.compressAndGetFile(
      image.path,
      originalPath,
      minWidth: maxImageWidth,
      quality: jpegQuality,
      format: CompressFormat.jpeg,
      keepExif: false,
    );
    final thumbnail = await FlutterImageCompress.compressAndGetFile(
      image.path,
      thumbnailPath,
      minWidth: thumbnailWidth,
      quality: thumbnailQuality,
      format: CompressFormat.jpeg,
      keepExif: false,
    );

    if (original == null || thumbnail == null) {
      throw const MediaUploadException('Could not optimize the selected image. Please try another image.');
    }

    return PreparedPostImage(
      originalFile: File(original.path),
      thumbnailFile: File(thumbnail.path),
      contentType: 'image/jpeg',
    );
  }

  Future<UploadedPostImage> uploadPostImage({
    required String postId,
    required PreparedPostImage image,
  }) async {
    final options = FileOptions(
      contentType: image.contentType,
      cacheControl: '31536000',
      upsert: true,
    );
    final originalPath = 'posts/$postId/original';
    final thumbPath = 'posts/$postId/thumb';

    // Deterministic paths plus upsert make a failed publish retry-safe: the next
    // attempt overwrites the same objects instead of orphaning duplicate files.
    await _client.storage.from(bucket).upload(originalPath, image.originalFile, fileOptions: options);
    await _client.storage.from(bucket).upload(thumbPath, image.thumbnailFile, fileOptions: options);

    final storage = _client.storage.from(bucket);
    return UploadedPostImage(
      originalUrl: storage.getPublicUrl(originalPath),
      thumbnailUrl: storage.getPublicUrl(thumbPath),
    );
  }
}

class MediaUploadException implements Exception {
  const MediaUploadException(this.message);

  final String message;

  @override
  String toString() => message;
}
