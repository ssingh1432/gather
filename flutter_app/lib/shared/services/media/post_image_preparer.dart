import 'package:image_picker/image_picker.dart';

import 'prepared_post_image.dart';
import 'post_image_preparer_io.dart' if (dart.library.html) 'post_image_preparer_web.dart' as impl;

/// Prepares a picked [XFile] for upload, dispatching to a platform-specific
/// implementation resolved at compile time via a conditional import:
///
/// - Android/iOS/desktop → `post_image_preparer_io.dart`
///   (compresses to a temp file with `flutter_image_compress` +
///   `path_provider`)
/// - Web → `post_image_preparer_web.dart`
///   (reads bytes in memory with `XFile.readAsBytes()`)
///
/// Only ONE of those two files is ever compiled into a given build, so
/// `dart:io` / `path_provider` never end up in the Web bundle, and there is
/// no `kIsWeb` runtime branching needed here.
Future<PreparedImageSet> preparePostImage(XFile image) => impl.preparePostImage(image);
