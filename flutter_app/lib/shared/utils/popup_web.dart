// dart:html is used here (not package:web) so the API surface matches
// exactly what's documented and verified — package:web's JS-interop-typed
// Window.open()/Location bindings for the pinned pub version can't be
// confirmed without a local Flutter SDK to compile against, and this
// sandbox has no way to catch an interop-signature mismatch before CI
// does. This file follows the existing _web.dart naming convention used
// elsewhere in this codebase (remember_me_service_web.dart etc.), which
// is what exempts it from the avoid_web_libraries_in_flutter lint.
import 'dart:html' as html;

/// Opens a blank popup window synchronously. Web browsers only allow
/// window.open() to bypass the popup blocker when it's called directly
/// within a user gesture (e.g. a button's onPressed) — NOT after an
/// `await`. Since the real destination URL usually isn't known until
/// after an async RPC call (initiate_page_payment), we open a blank
/// window immediately on tap (still synchronous, still "trusted" by the
/// browser) and redirect it once the URL is ready via [navigatePopup].
dynamic openBlankPopup() => html.window.open('', '_blank');

void navigatePopup(dynamic handle, String url) {
  if (handle is html.WindowBase) {
    handle.location.href = url;
  }
}
