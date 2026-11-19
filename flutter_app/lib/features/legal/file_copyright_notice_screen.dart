import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'copyright_repository.dart';

/// Form for rights holders to file a DMCA-style copyright notice (migration 130).
/// Opened from a post (with [postId]) or on its own (with a link to the content).
class FileCopyrightNoticeScreen extends StatefulWidget {
  const FileCopyrightNoticeScreen({super.key, this.postId});

  final String? postId;

  @override
  State<FileCopyrightNoticeScreen> createState() => _FileCopyrightNoticeScreenState();
}

class _FileCopyrightNoticeScreenState extends State<FileCopyrightNoticeScreen> {
  final _repo = CopyrightRepository();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _work = TextEditingController();
  final _originalUrl = TextEditingController();
  final _infringingUrl = TextEditingController();
  final _signature = TextEditingController();

  bool _goodFaith = false;
  bool _accuracy = false;
  bool _submitting = false;
  bool _submitted = false;

  @override
  void dispose() {
    for (final c in [_name, _email, _address, _work, _originalUrl, _infringingUrl, _signature]) {
      c.dispose();
    }
    super.dispose();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submit() async {
    final error = CopyrightFormValidator.validateNotice(
      name: _name.text,
      email: _email.text,
      workDescription: _work.text,
      signature: _signature.text,
      originalWorkUrl: _originalUrl.text,
      infringingUrl: _infringingUrl.text,
      targetPostId: widget.postId,
      goodFaith: _goodFaith,
      accuracy: _accuracy,
    );
    if (error != null) {
      _toast(error);
      return;
    }
    setState(() => _submitting = true);
    try {
      await _repo.submitNotice(
        claimantName: _name.text,
        claimantEmail: _email.text,
        claimantAddress: _address.text,
        workDescription: _work.text,
        originalWorkUrl: _originalUrl.text,
        targetPostId: widget.postId,
        infringingUrl: _infringingUrl.text,
        goodFaith: _goodFaith,
        accuracy: _accuracy,
        signature: _signature.text,
      );
      if (mounted) setState(() => _submitted = true);
    } catch (e) {
      if (mounted) _toast(CopyrightFormValidator.friendlyError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_submitted) {
      return Scaffold(
        appBar: AppBar(title: const Text('Notice received')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_outline, size: 48, color: AppColors.success),
                const SizedBox(height: 12),
                const Text(
                  'Your copyright notice has been received. A moderator will review it. '
                  'You can follow its status under Settings > Copyright notices.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Report copyright infringement')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Use this form only if you own the copyright, or act for the owner, and content on Gather '
            'uses your work without permission. Knowingly false notices can have legal consequences.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Your full legal name', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Contact email', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _address,
            decoration: const InputDecoration(labelText: 'Postal address (optional)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _work,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Describe the copyrighted work',
              hintText: 'What is the work, and how do you own it?',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _originalUrl,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'Link to your original work (optional)', border: OutlineInputBorder()),
          ),
          if (widget.postId == null) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _infringingUrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'Link to the infringing content', border: OutlineInputBorder()),
            ),
          ] else ...[
            const SizedBox(height: 12),
            Text('Reporting the post you opened this form from.', style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _goodFaith,
            onChanged: (v) => setState(() => _goodFaith = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text('I have a good-faith belief that this use is not authorised by the copyright owner, its agent, or the law.'),
          ),
          CheckboxListTile(
            value: _accuracy,
            onChanged: (v) => setState(() => _accuracy = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text('The information in this notice is accurate, and I am the owner or authorised to act for the owner.'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _signature,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Electronic signature (type your full name)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Submit notice'),
          ),
        ],
      ),
    );
  }
}
