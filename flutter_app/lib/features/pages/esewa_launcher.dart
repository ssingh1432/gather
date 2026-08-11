import 'package:flutter/material.dart';

import 'esewa_launcher_io.dart' if (dart.library.html) 'esewa_launcher_web.dart' as impl;

/// Launches the eSewa payment flow for the transaction whose signed form
/// fields live at [initUrl] (`PageRepository.esewaInitUrl(transactionId)`).
///
/// WHY THIS EXISTS: eSewa v2 needs a real signed POST straight to
/// `rc-epay.esewa.com.np` / `epay.esewa.com.np`, which means an HTML page
/// with an auto-submitting `<form>`. Supabase Edge Functions silently
/// rewrite any `text/html` response on a GET request to `text/plain`
/// (confirmed via Supabase's own docs — a platform-level anti-phishing
/// measure), so the esewa-payment edge function can never itself serve a
/// renderable redirect page. Instead it returns the signed fields as JSON
/// (`/init/<id>`), and this file builds the tiny form on-device and opens
/// it the right way per platform:
///   - Android/iOS: an in-app WebView (esewa_launcher_io.dart)
///   - Web: a real new browser tab, written to directly via JS interop
///     (esewa_launcher_web.dart) — the restriction is server-side, so
///     Flutter Web hits it too if it ever tries to open the old HTML URL
///   - Desktop: a `data:` URI opened in the system browser, as a
///     best-effort fallback (see esewa_launcher_io.dart for caveats)
///
/// Returns true if the flow was launched — NOT whether the payment
/// itself succeeded. That's still tracked the same way as before: each
/// payment sheet watches its transaction row over Supabase Realtime and
/// reacts once the edge function's /success or /failure callback resolves
/// it server-side.
Future<bool> openEsewaPayment(BuildContext context, String initUrl) => impl.openEsewaPayment(context, initUrl);
