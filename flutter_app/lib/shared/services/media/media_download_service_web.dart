import 'package:web/web.dart' as web;
import 'media_download_exception.dart';

Future<void> saveMediaToDevice({
  required String url,
  required bool isVideo,
}) async {
  try {
    final response = await web.fetch(url);
    final buffer = await response.arrayBuffer();
    final mimeType = isVideo ? 'video/mp4' : 'image/jpeg';
    final blob = web.Blob([buffer] as List<Object?>, mimeType);
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
  } catch (_) {
    throw const MediaDownloadException('Could not download this media. Please try again.');
  }
}
