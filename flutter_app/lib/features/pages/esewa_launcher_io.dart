// Non-web implementation, selected by the conditional import in
// esewa_launcher.dart. Split further at runtime by [defaultTargetPlatform]
// since Android/iOS get a proper in-app WebView but desktop
// (Windows/macOS/Linux) has no bundled WebView in this project yet.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'esewa_form_builder.dart';
import 'esewa_webview_screen.dart';

Future<bool> openEsewaPayment(BuildContext context, String initUrl) async {
  final EsewaFormFields fields;
  try {
    fields = await fetchEsewaFields(initUrl);
  } catch (_) {
    return false;
  }
  final html = buildEsewaFormHtml(fields);

  final isMobile = defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

  if (isMobile) {
    if (!context.mounted) return false;
    await Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => EsewaWebViewScreen(
        html: html,
        successUrlPrefix: fields.successUrl ?? '\u0000',
        failureUrlPrefix: fields.failureUrl ?? '\u0000',
      ),
    ));
    return true;
  }

  // Desktop fallback (Windows/macOS/Linux): this project has no bundled
  // desktop WebView yet, so open the system browser via a `data:` URI
  // instead — built entirely on-device, so it never depends on Supabase
  // serving HTML (which it can't; see esewa_launcher.dart). url_launcher
  // hands this to the OS (`start`/`open`/`xdg-open`), which is a
  // different code path than a page's own JS calling window.open() on a
  // data: URI, so it isn't subject to the same-origin top-level-navigation
  // block some browsers apply there — but this path is far less tested
  // than the mobile WebView flow. If desktop eSewa payments become a real
  // usage pattern, replace this with a small local relay (e.g.
  // package:shelf on 127.0.0.1) serving the form instead, since that's
  // the more robust long-term answer for every desktop browser.
  final dataUri = Uri.parse('data:text/html;charset=utf-8;base64,${base64Encode(utf8.encode(html))}');
  return launchUrl(dataUri, mode: LaunchMode.externalApplication);
}
