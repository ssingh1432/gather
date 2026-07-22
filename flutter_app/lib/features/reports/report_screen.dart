import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/supabase_client.dart';
import '../data/repositories.dart';

/// Generic report form, submitted via [ModerationRepository.report] (the
/// existing `reports` table insert used elsewhere). Accepts optional
/// `postId` / `userId` query params so a future "Report" button on a post
/// or profile can deep-link straight to a pre-filled target; falls back to
/// manual entry if opened directly (e.g. from the bottom nav / router).
class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key, this.postId, this.userId});

  final String? postId;
  final String? userId;

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final _reason = TextEditingController();
  String? _category;
  bool _loading = false;
  bool _submitted = false;
  XFile? _evidenceImage;
  String? _lastReportId;
  bool _evidenceUploading = false;
  bool _evidenceUploadFailed = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pickEvidence() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked != null && mounted) setState(() => _evidenceImage = picked);
  }

  /// Uploads the picked screenshot after the report row itself exists
  /// (evidence rows FK to `reports.id`, so this must run second). A failure
  /// here doesn't roll back the report — the report was the point, the
  /// screenshot is a bonus a mod can ask the reporter to resend if needed.
  Future<void> _uploadEvidenceIfAny(String reportId) async {
    if (_evidenceImage == null) return;
    final uploaderId = SupabaseConfig.currentUserId;
    if (uploaderId == null) return;
    setState(() => _evidenceUploading = true);
    try {
      await ModerationRepository().uploadAndAddEvidence(
        reportId: reportId,
        uploaderId: uploaderId,
        image: _evidenceImage!,
      );
    } catch (_) {
      if (mounted) setState(() => _evidenceUploadFailed = true);
    } finally {
      if (mounted) setState(() => _evidenceUploading = false);
    }
  }

  Future<void> _submit() async {
    if (_category == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose a reason.')),
      );
      return;
    }

    final reason = _reason.text.trim().isEmpty
        ? ModerationRepository.reportCategoryLabels[_category!]!
        : _reason.text.trim();

    final reporterId = SupabaseConfig.currentUserId;
    if (reporterId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be signed in to report content.')),
      );
      return;
    }

    // The `reports` table has a CHECK constraint: target_type must be
    // 'post' or 'user', and exactly the matching target_*_id column must
    // be set (the other must be null). Prefer postId when both are somehow
    // present.
    final isPostReport = widget.postId != null;
    if (!isPostReport && widget.userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing to report — missing post or user.')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final reportId = await ModerationRepository().report({
        'reporter_id': reporterId,
        'target_type': isPostReport ? 'post' : 'user',
        'target_post_id': isPostReport ? widget.postId : null,
        'target_user_id': isPostReport ? null : widget.userId,
        'reason': reason,
        'category': _category,
        'status': 'open',
      });
      _lastReportId = reportId;
      if (mounted) setState(() => _submitted = true);
      await _uploadEvidenceIfAny(reportId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not submit report: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Report')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _submitted
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Thanks — your report has been submitted for review.'),
                  if (_evidenceImage != null) ...[
                    const SizedBox(height: 12),
                    if (_evidenceUploading)
                      const Row(children: [
                        SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 8),
                        Text('Uploading attached screenshot…'),
                      ])
                    else if (_evidenceUploadFailed)
                      Row(
                        children: [
                          const Expanded(child: Text('Screenshot didn\'t upload — you can still add it later.', style: TextStyle(color: Colors.orange))),
                          TextButton(
                            onPressed: _lastReportId == null ? null : () => _uploadEvidenceIfAny(_lastReportId!),
                            child: const Text('Retry'),
                          ),
                        ],
                      )
                    else
                      const Text('Screenshot attached.', style: TextStyle(color: Colors.green)),
                  ],
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => context.pop(),
                    child: const Text('Done'),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('What\'s wrong? Our moderation team will review this.'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: ModerationRepository.reportCategories.map((c) {
                      final selected = _category == c;
                      return ChoiceChip(
                        label: Text(ModerationRepository.reportCategoryLabels[c]!),
                        selected: selected,
                        onSelected: (_) => setState(() => _category = c),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _reason,
                    decoration: const InputDecoration(labelText: 'Additional detail (optional)'),
                    maxLines: 4,
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _pickEvidence,
                    icon: const Icon(Icons.attach_file, size: 18),
                    label: Text(_evidenceImage == null ? 'Attach a screenshot (optional)' : 'Screenshot selected — tap to change'),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Submit report'),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    icon: const Icon(Icons.gavel_outlined, size: 18),
                    label: const Text('This is illegal content or a privacy violation'),
                    onPressed: () {
                      final params = <String, String>{
                        if (widget.postId != null) 'postId': widget.postId!,
                        if (widget.userId != null) 'userId': widget.userId!,
                      };
                      context.push(Uri(path: '/file-complaint', queryParameters: params.isEmpty ? null : params).toString());
                    },
                  ),
                ],
              ),
      ),
    );
  }
}
