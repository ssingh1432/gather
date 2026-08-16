import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/repositories.dart';
import 'esewa_launcher.dart';
import 'pages_theme.dart';

/// Real-money donation flow (Step 15b): amount entry -> initiate_page_payment
/// RPC -> a fresh "Open eSewa" tap -> watch the transaction row over
/// Realtime until the edge function's callback resolves it. Nothing here
/// ever touches a secret; that all happens server-side.
///
/// The RPC and the eSewa launch are deliberately two separate taps, not
/// one. A live test found that combining them (creating the transaction,
/// then immediately opening the URL in the same async handler) works
/// fine on native platforms but silently fails on Flutter Web: browsers
/// only allow window.open() to bypass the popup blocker when it happens
/// synchronously within a user gesture, and the `await` on the RPC breaks
/// that chain with no error surfaced anywhere. Making "Open eSewa" its
/// own fresh button tap keeps it a trusted gesture on every platform —
/// esewa_launcher.dart's Web implementation still calls window.open() as
/// the very first (synchronous) statement of that tap handler, before any
/// `await`, for the same reason.
Future<void> showDonateSheet(BuildContext context, {required String pageId, required String pageName}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _DonateSheetBody(pageId: pageId, pageName: pageName),
    ),
  );
}

class _DonateSheetBody extends StatefulWidget {
  const _DonateSheetBody({required this.pageId, required this.pageName});
  final String pageId;
  final String pageName;

  @override
  State<_DonateSheetBody> createState() => _DonateSheetBodyState();
}

enum _DonateStage { amount, ready, waiting, success, failed }

class _DonateSheetBodyState extends State<_DonateSheetBody> {
  final _repo = PageRepository();
  final _amountController = TextEditingController(text: '100');
  final _messageController = TextEditingController();
  _DonateStage _stage = _DonateStage.amount;
  String? _error;
  String? _pendingUrl;
  RealtimeChannel? _channel;

  static const _quickAmounts = [50, 100, 500, 1000];

  @override
  void dispose() {
    _amountController.dispose();
    _messageController.dispose();
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _prepare() async {
    final rupees = int.tryParse(_amountController.text.trim());
    if (rupees == null || rupees <= 0) {
      setState(() => _error = 'Enter a valid amount');
      return;
    }
    setState(() => _error = null);
    try {
      final txnId = await _repo.initiatePagePayment(
        pageId: widget.pageId,
        purpose: 'donation',
        amountCents: rupees * 100,
        message: _messageController.text.trim().isEmpty ? null : _messageController.text.trim(),
      );

      _channel = _repo.watchPaymentTransaction(txnId, (row) {
        final status = row['status'] as String?;
        if (!mounted) return;
        if (status == 'completed') {
          setState(() => _stage = _DonateStage.success);
        } else if (status == 'failed' || status == 'cancelled') {
          setState(() => _stage = _DonateStage.failed);
        }
      });

      if (mounted) {
        setState(() {
          _pendingUrl = _repo.esewaInitUrl(txnId);
          _stage = _DonateStage.ready;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not start payment: $e');
    }
  }

  /// See the class-doc note above on why this stays its own fresh tap,
  /// separate from _prepare().
  Future<void> _openEsewa() async {
    final url = _pendingUrl;
    if (url == null) return;
    setState(() => _stage = _DonateStage.waiting);
    final opened = await openEsewaPayment(context, url);
    if (!opened && mounted) {
      setState(() {
        _error = 'Could not open eSewa. Please try again.';
        _stage = _DonateStage.ready;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(PageTokens.spaceLg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          switch (_stage) {
            _DonateStage.amount => _buildAmountForm(context),
            _DonateStage.ready => _buildReady(context),
            _DonateStage.waiting => _buildWaiting(context),
            _DonateStage.success => _buildResult(context, success: true),
            _DonateStage.failed => _buildResult(context, success: false),
          },
        ],
      ),
    );
  }

  Widget _buildAmountForm(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Support ${widget.pageName}', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('Pay securely via eSewa. This opens eSewa in your browser.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: PageTokens.spaceLg),
        Wrap(
          spacing: 8,
          children: [
            for (final amt in _quickAmounts)
              ChoiceChip(
                label: Text('Rs. $amt'),
                selected: _amountController.text == '$amt',
                onSelected: (_) => setState(() => _amountController.text = '$amt'),
              ),
          ],
        ),
        const SizedBox(height: PageTokens.spaceMd),
        TextField(
          controller: _amountController,
          keyboardType: TextInputType.number,
          decoration: pageFieldDecoration(context, labelText: 'Amount (NPR)', prefixIcon: const Icon(Icons.currency_rupee)),
        ),
        const SizedBox(height: PageTokens.spaceMd),
        TextField(
          controller: _messageController,
          decoration: pageFieldDecoration(context, labelText: 'Message (optional)'),
          maxLength: 200,
        ),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        const SizedBox(height: PageTokens.spaceMd),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _prepare,
            icon: const Icon(Icons.volunteer_activism_outlined),
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
          const Icon(Icons.volunteer_activism_outlined, size: 40),
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
          Text(success ? 'Thank you for your support!' : 'Payment did not complete', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: PageTokens.spaceMd),
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        ],
      ),
    );
  }
}
