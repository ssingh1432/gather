import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase_client.dart';
import '../../core/responsive.dart';
import '../data/repositories.dart';

const _providers = [
  ('esewa', 'eSewa'),
  ('khalti', 'Khalti'),
  ('bank', 'Bank account'),
];

class MonetizationSettingsScreen extends StatefulWidget {
  const MonetizationSettingsScreen({super.key});

  @override
  State<MonetizationSettingsScreen> createState() => _MonetizationSettingsScreenState();
}

class _MonetizationSettingsScreenState extends State<MonetizationSettingsScreen> {
  final _repo = MonetizationRepository();
  final _holderName = TextEditingController();
  final _maskedReference = TextEditingController();
  String _provider = _providers.first.$1;

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _eligibility;
  bool _optedIn = false;
  String _status = 'not_started';
  Map<String, dynamic>? _payoutPref;
  bool _savingOptIn = false;
  bool _savingPayout = false;

  String? get _uid => SupabaseConfig.currentUserId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _holderName.dispose();
    _maskedReference.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = _uid;
    if (uid == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _repo.checkEligibility(),
        ProfileRepository().loadProfile(uid),
        _repo.loadPayoutPreference(uid),
      ]);
      final eligibility = results[0] as Map<String, dynamic>;
      final profile = results[1];
      final payoutPref = results[2];
      if (mounted) {
        setState(() {
          _eligibility = eligibility;
          _optedIn = (profile?['monetization_opt_in'] as bool?) ?? false;
          _status = (profile?['monetization_status'] as String?) ?? 'not_started';
          _payoutPref = payoutPref;
          if (payoutPref != null) {
            _provider = (payoutPref['provider'] as String?) ?? _provider;
            _holderName.text = (payoutPref['holder_name'] as String?) ?? '';
            _maskedReference.text = (payoutPref['masked_reference'] as String?) ?? '';
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load monetization settings: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleOptIn(bool value) async {
    setState(() => _savingOptIn = true);
    try {
      await _repo.setOptIn(value);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update: $e')));
      }
    } finally {
      if (mounted) setState(() => _savingOptIn = false);
    }
  }

  Future<void> _savePayoutPreference() async {
    final uid = _uid;
    if (uid == null) return;
    final holder = _holderName.text.trim();
    final reference = _maskedReference.text.trim();
    if (holder.isEmpty || reference.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fill in the account holder name and reference.')),
      );
      return;
    }
    setState(() => _savingPayout = true);
    try {
      await _repo.savePayoutPreference(
        userId: uid,
        provider: _provider,
        holderName: holder,
        maskedReference: reference,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved. Submitted for review.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    } finally {
      if (mounted) setState(() => _savingPayout = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Monetization')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        OutlinedButton(onPressed: _load, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : ResponsiveCenter(
                  maxWidth: 560,
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        _buildIntro(),
                        const SizedBox(height: 24),
                        _buildEligibilityCard(),
                        const SizedBox(height: 24),
                        _buildOptInCard(),
                        if (_optedIn) ...[
                          const SizedBox(height: 24),
                          _buildPayoutForm(),
                        ],
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildIntro() {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35),
      child: const Padding(
        padding: EdgeInsets.all(14),
        child: Text(
          'Earn a share of ad revenue when ads appear on your posts. This is early — payouts are '
          'reviewed and sent manually while Gather is small, not automatic. There are a few steps '
          'to unlock it.',
        ),
      ),
    );
  }

  /// Same 10-digit-with-optional-prefix normalization as signup.
  String? _normalizedPhoneOrNull(String raw) {
    var digits = raw.trim().replaceAll(RegExp(r'[\s-]'), '');
    if (digits.startsWith('+977')) digits = digits.substring(4);
    if (digits.startsWith('977')) digits = digits.substring(3);
    if (digits.startsWith('0')) digits = digits.substring(1);
    if (!RegExp(r'^9\d{9}$').hasMatch(digits)) return null;
    return digits;
  }

  Future<void> _promptAddPhone() async {
    final controller = TextEditingController();
    final normalized = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add mobile number'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Mobile number',
            hintText: '98XXXXXXXX',
            prefixText: '+977 ',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final n = _normalizedPhoneOrNull(controller.text);
              if (n == null) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('Enter a valid 10-digit mobile number.')),
                );
                return;
              }
              Navigator.pop(dialogContext, n);
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (normalized != null && mounted) {
      context.push('/verify-phone?phone=$normalized');
    }
  }

  Widget _buildEligibilityCard() {
    final e = _eligibility ?? const {};
    final rows = <_CheckRow>[
      _CheckRow('Account age', '${e['account_age_days_required'] ?? 14}+ days', e['account_age_days_met'] ?? ((e['account_age_days'] ?? 0) >= (e['account_age_days_required'] ?? 14))),
      _CheckRow('Posts published', '${e['post_count_required'] ?? 5}+ posts', (e['post_count'] ?? 0) >= (e['post_count_required'] ?? 5)),
      _CheckRow('Phone verified', null, e['phone_verified'] == true),
      _CheckRow('Email verified', null, e['email_verified'] == true),
    ];
    final eligible = e['eligible'] == true;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(eligible ? Icons.check_circle : Icons.pending_outlined,
                    color: eligible ? Colors.green : Colors.orange),
                const SizedBox(width: 8),
                Text(eligible ? 'You meet the requirements' : 'Steps to unlock monetization',
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            for (final r in rows) r,
            if (e['phone_verified'] != true) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _promptAddPhone,
                icon: const Icon(Icons.phone_outlined),
                label: const Text('Add & verify phone number'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOptInCard() {
    final eligible = _eligibility?['eligible'] == true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show ads on my posts'),
              subtitle: Text(
                !eligible
                    ? 'Complete the steps above first'
                    : _optedIn
                        ? _statusLabel(_status)
                        : 'Off',
              ),
              value: _optedIn,
              onChanged: (eligible || _optedIn) && !_savingOptIn ? _toggleOptIn : null,
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(String status) => switch (status) {
        'pending_review' => 'Submitted — under review',
        'approved' => 'Approved — active',
        'rejected' => 'Not approved. Contact support for details.',
        _ => 'On',
      };

  Widget _buildPayoutForm() {
    final currentStatus = (_payoutPref?['status'] as String?) ?? 'pending_review';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Payout preference', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text(
              'For manual payouts once you\'re earning. Only enter the last 4 digits of your '
              'account — never your full account number, PIN, password, or OTP. We will never ask '
              'for those.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _provider,
              decoration: const InputDecoration(labelText: 'Payout method', border: OutlineInputBorder()),
              items: [for (final p in _providers) DropdownMenuItem(value: p.$1, child: Text(p.$2))],
              onChanged: (v) => setState(() => _provider = v ?? _provider),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _holderName,
              decoration: const InputDecoration(labelText: 'Account holder name', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _maskedReference,
              maxLength: 8,
              decoration: const InputDecoration(
                labelText: 'Last 4 digits only',
                hintText: 'e.g. 1234',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 8),
            if (_payoutPref != null)
              Text('Status: ${_statusLabel(currentStatus == 'verified' ? 'approved' : currentStatus)}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _savingPayout ? null : _savePayoutPreference,
              child: _savingPayout
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow(this.label, this.hint, this.met);
  final String label;
  final String? hint;
  final bool met;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(met ? Icons.check_circle_outline : Icons.radio_button_unchecked,
              size: 18, color: met ? Colors.green : Colors.grey),
          const SizedBox(width: 8),
          Expanded(child: Text(hint == null ? label : '$label ($hint)')),
        ],
      ),
    );
  }
}
