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

    final loadOrError = Future.any([
      request.onLoad.first,
      request.onError.first.then((_) => throw const MediaDownloadException(
          'Could not download this media. Please try again.')),
    ]);
    request.send();
    await loadOrError;

    if (request.status < 200 || request.status >= 300) {
      throw const MediaDownloadException('Could not download this media. Please try again.');
    }

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
