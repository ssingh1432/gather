import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/repositories.dart';
import 'esewa_launcher.dart';
import 'pages_theme.dart';

/// Real-money subscription checkout (Step 15b continuation): fixed tier
/// price -> initiate_page_payment(purpose: 'subscription') -> a fresh
/// "Open eSewa" tap -> watch the transaction over Realtime. On success,
/// the esewa-payment edge function itself activates the page_subscribers
/// row (sets status='active', a 30-day period) — this sheet only reflects
/// that outcome, it doesn't touch subscriber status directly.
///
/// The RPC and the eSewa launch are two separate taps, not one — see
/// donate_sheet.dart's doc comment for why: browsers only trust
/// window.open() as a real user gesture when it happens synchronously
/// within a tap handler, and the `await` on the RPC breaks that chain on
/// Flutter Web with no error surfaced anywhere.
Future<void> showSubscribeSheet(
  BuildContext context, {
  required String pageId,
  required String pageName,
  required Map<String, dynamic> tier,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _SubscribeSheetBody(pageId: pageId, pageName: pageName, tier: tier),
    ),
  );
}

class _SubscribeSheetBody extends StatefulWidget {
  const _SubscribeSheetBody({required this.pageId, required this.pageName, required this.tier});
  final String pageId;
  final String pageName;
  final Map<String, dynamic> tier;

  @override
  State<_SubscribeSheetBody> createState() => _SubscribeSheetBodyState();
}

enum _Stage { confirm, ready, waiting, success, failed }

class _SubscribeSheetBodyState extends State<_SubscribeSheetBody> {
  final _repo = PageRepository();
  _Stage _stage = _Stage.confirm;
  String? _error;
  String? _pendingUrl;
  RealtimeChannel? _channel;

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  int get _priceCents => widget.tier['price_cents'] as int? ?? 0;
  String get _tierName => widget.tier['name'] as String? ?? 'Subscription';

  Future<void> _prepare() async {
    setState(() => _error = null);
    try {
      final txnId = await _repo.initiatePagePayment(
        pageId: widget.pageId,
        purpose: 'subscription',
        amountCents: _priceCents,
        tierId: widget.tier['id'] as String,
      );

      _channel = _repo.watchPaymentTransaction(txnId, (row) {
        final status = row['status'] as String?;
        if (!mounted) return;
        if (status == 'completed') {
          setState(() => _stage = _Stage.success);
        } else if (status == 'failed' || status == 'cancelled') {
          setState(() => _stage = _Stage.failed);
        }
      });

      if (mounted) {
        setState(() {
          _pendingUrl = _repo.esewaInitUrl(txnId);
          _stage = _Stage.ready;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not start payment: $e');
    }
  }

  Future<void> _openEsewa() async {
    final url = _pendingUrl;
    if (url == null) return;
    setState(() => _stage = _Stage.waiting);
    final opened = await openEsewaPayment(context, url);
    if (!opened && mounted) {
      setState(() {
        _error = 'Could not open eSewa. Please try again.';
        _stage = _Stage.ready;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(PageTokens.spaceLg),
      child: switch (_stage) {
        _Stage.confirm => _buildConfirm(context),
        _Stage.ready => _buildReady(context),
        _Stage.waiting => _buildWaiting(context),
        _Stage.success => _buildResult(context, success: true),
        _Stage.failed => _buildResult(context, success: false),
      },
    );
  }

  Widget _buildConfirm(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Subscribe to ${widget.pageName}', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: PageTokens.spaceMd),
        Container(
          padding: const EdgeInsets.all(PageTokens.spaceMd),
          decoration: BoxDecoration(
            color: PageColors.surfaceMuted(context),
            borderRadius: BorderRadius.circular(PageTokens.radiusMd),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_tierName, style: const TextStyle(fontWeight: FontWeight.w700)),
                    if ((widget.tier['description'] as String?)?.isNotEmpty ?? false)
                      Text(widget.tier['description'] as String, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              Text('Rs. ${(_priceCents / 100).toStringAsFixed(0)}/mo', style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        const SizedBox(height: PageTokens.spaceMd),
        Text(
          'Renews monthly. Pay securely via eSewa — this opens eSewa in your browser.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        const SizedBox(height: PageTokens.spaceMd),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _prepare,
            icon: const Icon(Icons.workspace_premium_outlined),
            label: const Text('Continue'),
          ),
        ),
      ],
    );
  }

  Widget _buildReady(BuildContext context) {
    return SizedBox(
      height: 220,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.workspace_premium_outlined, size: 40),
          const SizedBox(height: PageTokens.spaceMd),
          Text("You're all set", style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Text(
            'Tap below to complete your payment on eSewa.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          const SizedBox(height: PageTokens.spaceMd),
          FilledButton.icon(onPressed: _openEsewa, icon: const Icon(Icons.open_in_new), label: const Text('Open eSewa')),
        ],
      ),
    );
  }

  Widget _buildWaiting(BuildContext context) {
    return SizedBox(
      height: 220,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: PageTokens.spaceLg),
          Text('Waiting for payment confirmation…', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Text(
            'Complete the payment in eSewa, then return here — this updates automatically.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildResult(BuildContext context, {required bool success}) {
    return SizedBox(
      height: 220,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(success ? Icons.check_circle_outline : Icons.error_outline, size: 48, color: success ? AppColors.brandTeal : Theme.of(context).colorScheme.error),
          const SizedBox(height: PageTokens.spaceMd),
          Text(success ? "You're subscribed!" : 'Payment did not complete', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: PageTokens.spaceMd),
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        ],
      ),
    );
  }
}
