import 'package:flutter/material.dart';

import '../data/repositories.dart';

/// Formal grievance / legal complaint form — for illegal content, privacy
/// violations, defamation, and impersonation, each optionally tied to a
/// specific legal framework (Phase 4 Nepal legal compliance). Distinct
/// from the lightweight peer "Report" flow in report_screen.dart, which
/// stays as the fast in-context report button on posts/profiles.
class FileComplaintScreen extends StatefulWidget {
  const FileComplaintScreen({super.key, this.postId, this.userId});

  final String? postId;
  final String? userId;

  @override
  State<FileComplaintScreen> createState() => _FileComplaintScreenState();
}

class _FileComplaintScreenState extends State<FileComplaintScreen> {
  final _repo = LegalRepository();
  final _description = TextEditingController();

  String _complaintType = 'illegal_content';
  String? _legalBasisCode;
  List<Map<String, dynamic>> _frameworks = const [];
  bool _loading = true;
  bool _submitting = false;
  bool _submitted = false;

  static const _typeLabels = {
    'illegal_content': 'Illegal content',
    'privacy_violation': 'Privacy violation',
    'defamation': 'Defamation',
    'impersonation': 'Impersonation',
    'other': 'Other',
  };

  @override
  void initState() {
    super.initState();
    _repo.legalFrameworks().then((f) {
      if (mounted) setState(() { _frameworks = f; _loading = false; });
    });
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_description.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please describe the issue.')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await _repo.fileComplaint(
        complaintType: _complaintType,
        description: _description.text.trim(),
        legalBasisCode: _legalBasisCode,
        targetPostId: widget.postId,
        targetUserId: widget.userId,
      );
      if (mounted) setState(() => _submitted = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not submit complaint: $e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_submitted) {
      return Scaffold(
        appBar: AppBar(title: const Text('Complaint filed')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_outline, size: 48, color: Colors.green),
                SizedBox(height: 12),
                Text(
                  "We've received your complaint and will review it. You can track its status "
                  'under Settings > Grievances & legal requests.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('File a complaint')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Use this form for formal complaints — illegal content, privacy violations, '
                  "defamation, or impersonation — that need a documented legal review, "
                  'rather than a quick community-standards report.',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _complaintType,
                  decoration: const InputDecoration(labelText: 'Complaint type'),
                  items: [
                    for (final e in _typeLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setState(() => _complaintType = v ?? _complaintType),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _legalBasisCode,
                  decoration: const InputDecoration(labelText: 'Relevant law (optional)'),
                  items: [
                    for (final f in _frameworks)
                      DropdownMenuItem(value: f['code'] as String, child: Text(f['name'] as String)),
                  ],
                  onChanged: (v) => setState(() => _legalBasisCode = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _description,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Describe the issue',
                    hintText: 'Include as much detail as possible: what happened, when, and any evidence.',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Submit complaint'),
                ),
              ],
            ),
    );
  }
}
