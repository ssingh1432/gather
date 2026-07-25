// Web feed offline cache, backed by window.localStorage. Only ever
// compiled on web — selected via the conditional import in
// feed_offline_cache.dart.
import 'package:web/web.dart' as web;

const _key = 'gather_feed_cache';

Future<void> write(String payload) async {
  web.window.localStorage.setItem(_key, payload);
}

Future<String?> read() async {
  return web.window.localStorage.getItem(_key);
}
