// package:web (JS-interop, already a direct dependency — see pubspec.yaml)
// is used here instead of dart:html, which is deprecated and flagged by the
// avoid_web_libraries_in_flutter lint. This file follows the existing
// _web.dart naming convention used elsewhere in this codebase
// (remember_me_service_web.dart etc.), paired with popup_stub.dart via
// web_popup.dart's conditional import.
import 'package:web/web.dart' as web;

/// Opens a blank popup window synchronously. Web browsers only allow
/// window.open() to bypass the popup blocker when it's called directly
/// within a user gesture (e.g. a button's onPressed) — NOT after an
/// `await`. Since the real destination URL usually isn't known until
/// after an async RPC call (initiate_page_payment), we open a blank
/// window immediately on tap (still synchronous, still "trusted" by the
/// browser) and redirect it once the URL is ready via [navigatePopup].
dynamic openBlankPopup() => web.window.open('', '_blank');

void navigatePopup(dynamic handle, String url) {
  if (handle is web.Window) {
    handle.location.href = url;
  }
}
