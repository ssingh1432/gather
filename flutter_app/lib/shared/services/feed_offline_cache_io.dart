// Mobile/desktop feed offline cache. Only ever compiled where dart:io
// exists — selected via the conditional import in feed_offline_cache.dart.
import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<File> _file() async {
  final dir = await getApplicationDocumentsDirectory();
  return File('${dir.path}/gather_feed_cache.json');
}

Future<void> write(String payload) async {
  final file = await _file();
  await file.writeAsString(payload);
}

Future<String?> read() async {
  final file = await _file();
  if (!await file.exists()) return null;
  return file.readAsString();
}
