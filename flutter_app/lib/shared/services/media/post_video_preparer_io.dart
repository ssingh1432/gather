// Mobile/desktop video preparer.
//
// This file is only ever compiled for targets where `dart:io` exists
// (Android, iOS, desktop) — selected via the conditional import in
// `post_video_preparer.dart` and never part of the Flutter Web bundle.
//
// Videos aren't re-encoded client-side (no equivalent of
// `flutter_image_compress` for video without pulling in a much heavier
// native transcoding dependency) — the picked file is uploaded as-is.
import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'prepared_post_video.dart';

class _IoPreparedPostVideo implements PreparedPostVideo {
  const _IoPreparedPostVideo(this.file, this._contentType);

  final File file;
  final String _contentType;

  @override
  String get contentType => _contentType;

  @override
  Future<void> uploadTo(StorageFileApi storageApi, String path, FileOptions options) {
    return storageApi.upload(path, file, fileOptions: options);
  }
}

Future<PreparedPostVideo> preparePostVideo(XFile video) async {
  return _IoPreparedPostVideo(File(video.path), _resolveContentType(video));
}

String _resolveContentType(XFile video) {
  final mimeType = video.mimeType;
  if (mimeType != null && mimeType.isNotEmpty) return mimeType;
  final name = video.name.toLowerCase();
  if (name.endsWith('.mov')) return 'video/quicktime';
  if (name.endsWith('.webm')) return 'video/webm';
  return 'video/mp4';
}
