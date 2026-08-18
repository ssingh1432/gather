import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';

class PagePostMediaRepository {
  static const bucket = 'page-media';
  static const maxBytes = 25 * 1024 * 1024;

  SupabaseClient get _client => SupabaseConfig.client;

  Future<String> upload({
    required String pageId,
    required String postId,
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    if (bytes.length > maxBytes) {
      throw const PagePostMediaException('This file is larger than the 25 MB limit.');
    }
    final safeName = _safeFileName(fileName);
    final path = '$pageId/posts/$postId/${DateTime.now().microsecondsSinceEpoch}_$safeName';
    try {
      await _client.storage.from(bucket).uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(
          contentType: mimeType,
          cacheControl: '3600',
          upsert: false,
        ),
      );
      return path;
    } on StorageException catch (e) {
      throw PagePostMediaException(_friendlyStorageError(e));
    }
  }

  String publicUrl(String path) => _client.storage.from(bucket).getPublicUrl(path);

  Future<void> deletePaths(Iterable<String> paths) async {
    final valid = paths.where((p) => p.trim().isNotEmpty).toList();
    if (valid.isEmpty) return;
    try {
      await _client.storage.from(bucket).remove(valid);
    } on StorageException catch (e) {
      throw PagePostMediaException(_friendlyStorageError(e));
    }
  }

  static String _safeFileName(String value) {
    final name = value.trim().split('/').last.split('\\').last;
    final cleaned = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return cleaned.isEmpty ? 'file' : cleaned;
  }

  static String _friendlyStorageError(StorageException e) {
    final message = e.message.toLowerCase();
    if (message.contains('mime') || message.contains('type')) return 'This file type is not supported.';
    if (message.contains('size') || message.contains('large')) return 'This file is larger than the 25 MB limit.';
    if (message.contains('permission') || message.contains('row-level')) return 'You do not have permission to upload Page media.';
    return 'The media upload failed. Please try again.';
  }
}

class PagePostMediaException implements Exception {
  const PagePostMediaException(this.message);
  final String message;

  @override
  String toString() => message;
}
