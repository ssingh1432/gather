import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Full-screen in-app WebView that loads [html] (the auto-submitting
/// eSewa form built by esewa_form_builder.dart) and pops itself once the
/// browser navigates to a URL starting with [successUrlPrefix] or
/// [failureUrlPrefix] — the esewa-payment edge function's own /success
/// and /failure endpoints. Those endpoints do the real work server-side
/// (signature verification + independent status re-check + DB update)
/// regardless of what this screen renders (its own HTML response gets
/// downgraded to plain text by Supabase, same as everything else on GET —
/// irrelevant here since we're about to close this screen anyway).
///
/// The calling sheet's existing Realtime watch on the transaction row is
/// what actually reflects the payment outcome; this screen's only job is
/// to get the person through eSewa's UI and get out of the way once it's
/// done.
class EsewaWebViewScreen extends StatefulWidget {
  const EsewaWebViewScreen({
    super.key,
    required this.html,
    required this.successUrlPrefix,
    required this.failureUrlPrefix,
  });

  final String html;
  final String successUrlPrefix;
  final String failureUrlPrefix;

  @override
  State<EsewaWebViewScreen> createState() => _EsewaWebViewScreenState();
}

class _EsewaWebViewScreenState extends State<EsewaWebViewScreen> {
  late final WebViewController _controller;
  bool _closing = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFF4F6F5))
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() => _loading = true);
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
        },
        onNavigationRequest: (request) {
          final url = request.url;
          if (url.startsWith(widget.successUrlPrefix) || url.startsWith(widget.failureUrlPrefix)) {
            _closeSoon();
          }
          return NavigationDecision.navigate;
        },
      ))
      ..loadHtmlString(widget.html);
  }

  /// Lets the success/failure request actually finish server-side
  /// (signature verify + DB update) before popping, rather than racing
  /// the navigation.
  void _closeSoon() {
    if (_closing) return;
    _closing = true;
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('eSewa'),
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading) const LinearProgressIndicator(),
        ],
      ),
    );
  }
}
