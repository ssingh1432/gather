import 'package:flutter/material.dart';

import '../../core/supabase_client.dart';
import '../../shared/services/beta_feedback_service.dart';

/// Phase 4 beta-only floating feedback entry point.
class BetaFeedbackButton extends StatelessWidget {
  const BetaFeedbackButton({super.key});

  @override
  Widget build(BuildContext context) {
    if (SupabaseConfig.currentUserId == null) return const SizedBox.shrink();
    return FloatingActionButton.extended(
      heroTag: 'beta-feedback',
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const _BetaFeedbackSheet(),
      ),
      icon: const Icon(Icons.feedback_outlined),
      label: const Text('Beta feedback'),
    );
  }
}

class _BetaFeedbackSheet extends StatefulWidget {
  const _BetaFeedbackSheet();

  @override
  State<_BetaFeedbackSheet> createState() => _BetaFeedbackSheetState();
}

class _BetaFeedbackSheetState extends State<_BetaFeedbackSheet> {
  final _message = TextEditingController();
  String _kind = 'bug';

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _message.text.trim();
    if (text.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please add a little more detail.')));
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    BetaFeedbackService.instance.submit(kind: _kind, message: text);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      const SnackBar(content: Text('Thanks — feedback sent in the background.')),
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Beta feedback', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('Tell us what broke, confused you, or should be considered later.'),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'bug', label: Text('Bug'), icon: Icon(Icons.bug_report_outlined)),
                ButtonSegment(value: 'general', label: Text('General'), icon: Icon(Icons.chat_bubble_outline)),
                ButtonSegment(value: 'feature_request', label: Text('Feature'), icon: Icon(Icons.lightbulb_outline)),
              ],
              selected: {_kind},
              onSelectionChanged: (value) => setState(() => _kind = value.single),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _message,
              minLines: 4,
              maxLines: 8,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                labelText: 'What happened?',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: FilledButton(onPressed: _submit, child: const Text('Send feedback'))),
          ],
        ),
      );
}
