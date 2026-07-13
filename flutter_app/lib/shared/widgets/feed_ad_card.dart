// Conditional export: real banner-ad card on Android/iOS/desktop
// (dart:io present), inert stub on web — keeps google_mobile_ads (which
// doesn't support Flutter Web) completely out of the web build.
export 'feed_ad_card_stub.dart' if (dart.library.io) 'feed_ad_card_io.dart';
