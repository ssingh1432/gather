/// Thrown when a media download/save fails, with a message safe to show
/// directly to the person (e.g. in a SnackBar).
class MediaDownloadException implements Exception {
  const MediaDownloadException(this.message);
  final String message;
  @override
  String toString() => message;
}
