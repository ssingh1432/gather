import 'media/media_download_service_io.dart'
    if (dart.library.html) 'media/media_download_service_web.dart' as impl;
export 'media/media_download_exception.dart';

/// Downloads [url] and saves it to the device.
///
/// - Android/iOS/desktop → saved into the Photos/Gallery app (via `gal`)
/// - Web → triggers a normal browser download into the Downloads folder
///
/// Throws a [MediaDownloadException] with a user-readable message on
/// failure (network error, permission denied, etc).
Future<void> saveMediaToDevice({
  required String url,
  required bool isVideo,
}) =>
    impl.saveMediaToDevice(url: url, isVideo: isVideo);
