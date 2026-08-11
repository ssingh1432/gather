// Web implementation, selected by the conditional import in
// esewa_launcher.dart (only ever compiled when `dart:html` exists).
//
// eSewa's own login/OTP flow needs a real top-level browsing context (not
// an iframe — some browsers restrict cookies/biometric prompts there), so
// this opens a real new tab/window rather than embedding anything. The
// window is opened SYNCHRONOUSLY as the very first thing this function
// does, so browsers still treat it as a trusted user gesture even though
// everything after it is async — see donate_sheet.dart's doc comment on
// why "Open eSewa" is already deliberately its own fresh tap, separate
// from the RPC that creates the transaction. Fields are fetched *after*
// the window is open and written into it once ready; if that fails, the
// blank window is closed again instead of left hanging.
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'esewa_form_builder.dart';

Future<bool> openEsewaPayment(BuildContext context, String initUrl) async {
  final popup = web.window.open('', '_blank');
  if (popup == null) return false; // popup blocked by the browser

  try {
    final fields = await fetchEsewaFields(initUrl);
    final html = buildEsewaFormHtml(fields);
    popup.document.open();
    popup.document.write(html);
    popup.document.close();
    return true;
  } catch (_) {
    popup.close();
    return false;
  }
}
