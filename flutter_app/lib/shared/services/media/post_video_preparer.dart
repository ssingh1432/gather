import 'package:image_picker/image_picker.dart';

import 'prepared_post_video.dart';
import 'post_video_preparer_io.dart' if (dart.library.html) 'post_video_preparer_web.dart' as impl;

/// Prepares a picked video [XFile] for upload, dispatching to a
/// platform-specific implementation resolved at compile time — same
/// pattern as `post_image_preparer.dart`:
///
/// - Android/iOS/desktop → `post_video_preparer_io.dart` (`dart:io` File)
/// - Web → `post_video_preparer_web.dart` (in-memory bytes)
Future<PreparedPostVideo> preparePostVideo(XFile video) => impl.preparePostVideo(video);
