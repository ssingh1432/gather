import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/utils/web_popup.dart';
import '../data/repositories.dart';
import 'pages_theme.dart';

/// Real-money donation flow (Step 15b): amount entry -> initiate_page_payment
/// RPC -> open the eSewa redirect externally -> watch the transaction row
/// over Realtime until the edge function's callback resolves it. Nothing
/// here ever touches a secret; that all happens server-side.
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

enum _DonateStage { amount, waiting, success, failed }

class _DonateSheetBodyState extends State<_DonateSheetBody> {
  final _repo = PageRepository();
  final _amountController = TextEditingController(text: '100');
  final _messageController = TextEditingController();
  _DonateStage _stage = _DonateStage.amount;
  String? _error;
  RealtimeChannel? _channel;

  static const _quickAmounts = [50, 100, 500, 1000];

  @override
  void dispose() {
    _amountController.dispose();
    _messageController.dispose();
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _startPayment() async {
    final rupees = int.tryParse(_amountController.text.trim());
    if (rupees == null || rupees <= 0) {
      setState(() => _error = 'Enter a valid amount');
      return;
    }
    // Must happen synchronously, before any await, or Chrome's popup
    // blocker silently swallows the window.open() call later — found via
    // a live test where "Continue to eSewa" appeared to do nothing on
    // Flutter Web (the RPC below breaks the direct-user-gesture chain).
    final popup = kIsWeb ? openBlankPopup() : null;
    setState(() {
      _error = null;
      _stage = _DonateStage.waiting;
    });
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

      final url = _repo.esewaPaymentUrl(txnId);
      if (kIsWeb) {
        navigatePopup(popup, url);
      } else {
        final opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        if (!opened && mounted) {
          setState(() {
            _error = 'Could not open eSewa. Please try again.';
            _stage = _DonateStage.amount;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not start payment: $e';
          _stage = _DonateStage.amount;
        });
      }
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
            onPressed: _startPayment,
            icon: const Icon(Icons.volunteer_activism_outlined),
            label: const Text('Continue to eSewa'),
          ),
        ),
      ],
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
