/// Stub used on non-web platforms (Android/iOS/desktop) — [openBlankPopup]
/// / [navigatePopup] are no-ops there since native `launchUrl` opens an
/// external browser via a platform intent regardless of async timing, so
/// there's no popup-blocker problem to work around. See web_popup.dart
/// for why this pair of functions exists at all.
dynamic openBlankPopup() => null;

void navigatePopup(dynamic handle, String url) {}
