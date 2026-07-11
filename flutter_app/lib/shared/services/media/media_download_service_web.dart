import 'package:web/web.dart' as web;
import 'media_download_exception.dart';

Future<void> saveMediaToDevice({
  required String url,
  required bool isVideo,
}) async {
  try {
    final request = web.XMLHttpRequest();
    request.open('GET', url);
    request.responseType = 'blob';
    await request.onLoad.first;
    final blob = request.response as web.Blob;
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
