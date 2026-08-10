import 'popup_stub.dart' if (dart.library.html) 'popup_web.dart' as impl;

/// Opens a blank popup window — call this synchronously, directly inside
/// a button's onPressed/onTap, BEFORE any `await`. On Flutter Web this
/// works around a real bug found via a live eSewa test: url_launcher's
/// externalApplication mode calls window.open() under the hood, but
/// browsers only allow that to bypass the popup blocker when it happens
/// synchronously within a user gesture. Payment flows here need to
/// `await` an RPC (initiate_page_payment) before the real URL is known,
/// which breaks that chain — the popup got silently blocked with no error
/// surfaced anywhere, which is exactly what made this one hard to
/// diagnose. Returns an opaque handle for [navigatePopup]; no-op (returns
/// null) on native platforms, where this isn't needed at all.
dynamic openBlankPopup() => impl.openBlankPopup();

/// Points a popup opened via [openBlankPopup] at the real destination
/// [url] once it's known. No-op on native platforms.
void navigatePopup(dynamic handle, String url) => impl.navigatePopup(handle, url);
