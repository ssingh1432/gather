// Flutter Web media download.
//
// Only ever compiled when `dart:html` exists (Web) — selected via the
// conditional import in `media_download_service.dart`.
//
// There's no "save to device gallery" concept on the Web platform; the
// closest, most honest equivalent is triggering the browser's normal file
// download (same as right-click → Save As), which drops the file into the
// person's Downloads folder.

import 'package:web/web.dart' as web;
import 'media_download_exception.dart';

Future<void> saveMediaToDevice({
  required String url,
  required bool isVideo,
}) async {
  web.XMLHttpRequest request;
  try {
    request = await web.fetch(url).then((response) => response as web.XMLHttpRequest);
  } catch (_) {
    throw const MediaDownloadException('Could not download this media. Please try again.');
  }

  final buffer = request.response;
  if (buffer == null) {
    throw const MediaDownloadException('Could not download this media. Please try again.');
  }

  final mimeType = isVideo ? 'video/mp4' : 'image/jpeg';
  final blob = web.Blob([buffer], mimeType);
  final blobUrl = web.URL.createObjectURL(blob);
  final fileName = 'gather_${DateTime.now().millisecondsSinceEpoch}.${isVideo ? 'mp4' : 'jpg'}';

  final anchor = web.HTMLAnchorElement()
    ..href = blobUrl
    ..download = fileName
    ..style.display = 'none';

  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(blobUrl);
}
