// Conditional export: on any platform with dart:io (Android/iOS/desktop),
// use the real bootstrap that touches google_mobile_ads. On web (no
// dart:io), use the no-op stub — this guarantees google_mobile_ads is
// never part of the web compilation graph at all, since that package
// doesn't support web.
export 'ads_bootstrap_stub.dart' if (dart.library.io) 'ads_bootstrap_io.dart';
