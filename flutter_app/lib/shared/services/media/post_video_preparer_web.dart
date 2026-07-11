// Flutter Web video preparer.
//
// This file is only ever compiled when `dart:html` exists (Web) — selected
// via the conditional import in `post_video_preparer.dart`.
//
// Deliberately does NOT import `dart:io`: Web has no writable filesystem,
// so the picked video is read straight into memory and uploaded with
// `uploadBinary`, exactly like the Web image preparer.
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'prepared_post_video.dart';

class _WebPreparedPostVideo implements PreparedPostVideo {
  const _WebPreparedPostVideo(this.bytes, this._contentType);

  final Uint8List bytes;
  final String _contentType;

  @override
  String get contentType => _contentType;

  @override
  Future<void> uploadTo(StorageFileApi storageApi, String path, FileOptions options) {
    return storageApi.uploadBinary(path, bytes, fileOptions: options);
  }
}

Future<PreparedPostVideo> preparePostVideo(XFile video) async {
  final bytes = await video.readAsBytes();
  return _WebPreparedPostVideo(bytes, _resolveContentType(video));
}

String _resolveContentType(XFile video) {
  final mimeType = video.mimeType;
  if (mimeType != null && mimeType.isNotEmpty) return mimeType;
  final name = video.name.toLowerCase();
  if (name.endsWith('.mov')) return 'video/quicktime';
  if (name.endsWith('.webm')) return 'video/webm';
  return 'video/mp4';
}
