import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';

/// On Flutter Web, `image_picker` hands back an [XFile] backed by a browser
/// `blob:` object URL rather than real bytes. If reading it is deferred —
/// e.g. until after a network round-trip like `createPost()` completes —
/// the browser can revoke that blob URL first. The read then fails with
/// "Could not load Blob from its URL. Has it been revoked?" at upload time,
/// even though the pick itself looked completely fine ("Photo selected"),
/// which is what made this look like a silent failure.
///
/// Call this immediately after every `pickImage`/`pickVideo` call, before
/// storing the result in state. It reads the bytes right away and rewraps
/// them in a memory-backed [XFile], so nothing later depends on the blob
/// URL still being alive — it can sit in state for as long as the user
/// takes to hit Publish/Save.
///
/// No-op on mobile/desktop: compression there (`flutter_image_compress`)
/// needs a real file path, not bytes, so the original [XFile] is returned
/// unchanged.
Future<XFile> materializeIfWeb(XFile picked) async {
  if (!kIsWeb) return picked;
  final bytes = await picked.readAsBytes();
  return XFile.fromData(bytes, name: picked.name, mimeType: picked.mimeType);
}
