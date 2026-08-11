// package:web (JS-interop, already a direct dependency — see pubspec.yaml)
// is used here instead of dart:html, which is deprecated and flagged by the
// avoid_web_libraries_in_flutter lint. This file follows the existing
// _web.dart naming convention used elsewhere in this codebase
// (remember_me_service_web.dart etc.), paired with popup_stub.dart via
// web_popup.dart's conditional import.
import 'dart:js_interop';

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
  // `is web.Window` triggers invalid_runtime_check_with_js_interop_types
  // (JS interop types aren't platform-consistent under `is`) — use
  // `.isA<T>()` from dart:js_interop instead, which is the sanctioned way
  // to runtime-check a JS interop type.
  if (handle != null && (handle as JSAny).isA<web.Window>()) {
    (handle as web.Window).location.href = url;
  }
}
