/// Thrown when a picked image cannot be prepared for upload (e.g. the
/// native compressor failed on mobile). Platform-agnostic — safe to import
/// from Web, mobile, or shared UI code.
class MediaUploadException implements Exception {
  const MediaUploadException(this.message);

  final String message;

  @override
  String toString() => message;
}
