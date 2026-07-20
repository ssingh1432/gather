import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/supabase_client.dart';
import '../data/repositories.dart';

/// Phase 3 privacy compliance hub: privacy-policy consent status, download
/// your data, review consent history, and request/cancel account deletion.
/// Reachable from Settings > Data & Privacy.
class DataPrivacyScreen extends StatefulWidget {
  const DataPrivacyScreen({super.key});

  @override
  State<DataPrivacyScreen> createState() => _DataPrivacyScreenState();
}

// Bump this whenever the privacy policy text changes; consent is recorded
// against this version so we always know exactly what a user agreed to.
const _kPrivacyPolicyVersion = '2026-07-19';
const _kPrivacyPolicyUrl = 'https://eiquoab.xyz/privacy-policy';

class _DataPrivacyScreenState extends State<DataPrivacyScreen> {
  final _repo = PrivacyRepository();

  bool _loading = true;
  Map<String, dynamic>? _latestPolicyConsent;
  List<Map<String, dynamic>> _exportRequests = const [];
  Map<String, dynamic>? _profile;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final uid = SupabaseConfig.currentUserId;
      final latestConsent = await _repo.latestConsent('privacy_policy');
      final exportRequests = await _repo.exportRequests();
      final profile = uid == null ? null : await SupabaseConfig.client.from('users').select().eq('id', uid).single();
      if (!mounted) return;
      setState(() {
        _latestPolicyConsent = latestConsent;
        _exportRequests = exportRequests;
        _profile = profile;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _hasCurrentConsent =>
      _latestPolicyConsent != null &&
      _latestPolicyConsent!['granted'] == true &&
      _latestPolicyConsent!['policy_version'] == _kPrivacyPolicyVersion;

  Future<void> _acceptPolicy() async {
    setState(() => _busy = true);
    try {
      await _repo.recordConsent(
        consentType: 'privacy_policy',
        policyVersion: _kPrivacyPolicyVersion,
        granted: true,
      );
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestExport() async {
    setState(() => _busy = true);
    try {
      final result = await _repo.requestDataExport();
      if (mounted) {
        final ready = result['status'] == 'ready';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ready
                  ? 'Your data is ready to download below.'
                  : "We're preparing your data. You'll be notified when it's ready.",
            ),
          ),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not start export: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestDeletion() async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete your account?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Your account will be scheduled for permanent deletion in 14 days. '
              'You can cancel any time before then. After that, your data is '
              'permanently removed and cannot be recovered.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(labelText: 'Reason (optional)'),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Schedule deletion'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await _repo.requestAccountDeletion(reason: reasonController.text.trim().isEmpty ? null : reasonController.text.trim());
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account deletion scheduled. You can cancel it below any time before it completes.')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not schedule deletion: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelDeletion() async {
    setState(() => _busy = true);
    try {
      await _repo.cancelAccountDeletion();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account deletion cancelled.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final pendingPurgeAt = _profile?['scheduled_purge_at'] as String?;

    return Scaffold(
      appBar: AppBar(title: const Text('Data & Privacy')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionCard(
            title: 'Privacy policy',
            icon: Icons.description_outlined,
            children: [
              Text(
                _hasCurrentConsent
                    ? "You've accepted the current privacy policy (version $_kPrivacyPolicyVersion)."
                    : 'You have not yet accepted the current privacy policy.',
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton(
                    onPressed: () => launchUrl(Uri.parse(_kPrivacyPolicyUrl), mode: LaunchMode.externalApplication),
                    child: const Text('Read privacy policy'),
                  ),
                  const Spacer(),
                  if (!_hasCurrentConsent)
                    FilledButton(onPressed: _busy ? null : _acceptPolicy, child: const Text('Accept')),
                ],
              ),
            ],
          ),
          _SectionCard(
            title: 'Download your data',
            icon: Icons.download_outlined,
            children: [
              const Text('Get a copy of your profile, posts, comments, and activity in a downloadable file.'),
              const SizedBox(height: 8),
              if (_exportRequests.isNotEmpty) ...[
                Builder(builder: (context) {
                  final latest = _exportRequests.first;
                  final status = latest['status'] as String? ?? 'pending';
                  final filePath = latest['file_path'] as String?;
                  if (status == 'ready' && filePath != null) {
                    return Row(
                      children: [
                        const Icon(Icons.check_circle_outline, color: Colors.green, size: 18),
                        const SizedBox(width: 6),
                        const Expanded(child: Text('Your export is ready — link valid for 7 days.')),
                        TextButton(
                          onPressed: () => launchUrl(Uri.parse(filePath), mode: LaunchMode.externalApplication),
                          child: const Text('Download'),
                        ),
                      ],
                    );
                  }
                  if (status == 'failed') {
                    return Text(
                      'Last attempt failed: ${latest['error_message'] ?? 'unknown error'}. Try again below.',
                      style: const TextStyle(color: Colors.red),
                    );
                  }
                  return Text('Last request: $status', style: Theme.of(context).textTheme.bodySmall);
                }),
                const SizedBox(height: 8),
              ],
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: _busy ? null : _requestExport,
                  child: const Text('Request my data'),
                ),
              ),
            ],
          ),
          _SectionCard(
            title: 'Delete your account',
            icon: Icons.delete_forever_outlined,
            children: [
              if (pendingPurgeAt != null) ...[
                Text('Your account is scheduled for deletion on ${pendingPurgeAt.split('T').first}.'),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(onPressed: _busy ? null : _cancelDeletion, child: const Text('Cancel deletion')),
                ),
              ] else ...[
                const Text('Permanently delete your account and personal data after a 14-day grace period.'),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                    onPressed: _busy ? null : _requestDeletion,
                    child: const Text('Delete my account'),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: () => context.push('/settings'),
              child: const Text('Back to settings'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.icon, required this.children});
  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }
}
