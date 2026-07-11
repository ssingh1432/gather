// Mobile/desktop media download.
//
// Only ever compiled where `dart:io` exists (Android, iOS, desktop) —
// selected via the conditional import in `media_download_service.dart`.
// Downloads the remote media to a temp file, then hands it to `gal` to
// save into the device's Photos/Gallery app.
import 'dart:io';

import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'media_download_exception.dart';

const String _album = 'Gather';

Future<void> saveMediaToDevice({required String url, required bool isVideo}) async {
  final response = await http.get(Uri.parse(url)).catchError((_) {
    throw const MediaDownloadException('Could not download this media. Check your connection and try again.');
  });

  if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
    throw const MediaDownloadException('Could not download this media. Please try again.');
  }

  final hasAccess = await Gal.hasAccess();
  if (!hasAccess) {
    final granted = await Gal.requestAccess();
    if (!granted) {
      throw const MediaDownloadException('Permission to save to your gallery was denied.');
    }
  }

  final tempDir = await getTemporaryDirectory();
  final extension = isVideo ? 'mp4' : 'jpg';
  final token = DateTime.now().microsecondsSinceEpoch;
  final filePath = p.join(tempDir.path, 'gather_download_$token.$extension');
  final file = File(filePath);

  try {
    await file.writeAsBytes(response.bodyBytes);
    if (isVideo) {
      await Gal.putVideo(filePath, album: _album);
    } else {
      await Gal.putImage(filePath, album: _album);
    }
  } catch (_) {
    throw const MediaDownloadException('Could not save media to your gallery. Please try again.');
  } finally {
    // Best-effort cleanup — the OS reclaims temp storage regardless.
    if (await file.exists()) {
      await file.delete().catchError((_) => file);
    }
  }
}
