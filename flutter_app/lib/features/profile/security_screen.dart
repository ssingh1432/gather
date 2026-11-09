import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/supabase_client.dart';
import '../../shared/services/device_service.dart';
import '../../shared/services/mfa_service.dart';

/// Account security: two-factor authentication (TOTP), signed-in devices,
/// trusted devices, and "sign out other devices".
class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  bool _loading = true;
  bool _mfaOn = false;
  String? _currentDeviceId;
  List<UserDevice> _devices = const [];
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final results = await Future.wait([
        MfaService.instance.isEnabled(),
        DeviceService.instance.listDevices(),
        DeviceService.instance.deviceId(),
      ]);
      if (!mounted) return;
      setState(() {
        _mfaOn = results[0] as bool;
        _devices = results[1] as List<UserDevice>;
        _currentDeviceId = results[2] as String;
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = 'Could not load security settings.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  /// Runs [action]; if the server demands a fresh 2FA step-up, prompts for a
  /// code, then retries once.
  Future<void> _withStepUp(Future<void> Function() action) async {
    try {
      await action();
    } on PostgrestException catch (e) {
      if (!e.message.contains('mfa_required')) rethrow;
      final ok = await _promptCode();
      if (ok != true) return;
      await action();
    }
  }

  Future<bool?> _promptCode() async {
    final factor = await MfaService.instance.verifiedTotpFactor();
    if (factor == null || !mounted) return false;
    final ctrl = TextEditingController();
    String? error;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Confirm it\u2019s you'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: '6-digit code', errorText: error),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                try {
                  await MfaService.instance.verify(factor.id, ctrl.text);
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (_) {
                  setLocal(() => error = 'Invalid or expired code');
                }
              },
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    return ok;
  }

  Future<void> _enable() async {
    try {
      final enrollment = await MfaService.instance.startEnrollment();
      if (!mounted) return;
      final done = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _EnrollDialog(enrollment: enrollment),
      );
      if (done == true) {
        _snack('Two-factor authentication is on.');
        await _load();
      } else {
        try {
          await MfaService.instance.disable(enrollment.factorId);
        } catch (_) {}
      }
    } catch (e) {
      _snack('Could not start two-factor setup. Make sure MFA is enabled for the project.');
    }
  }

  Future<void> _disable() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Turn off two-factor authentication?'),
        content: const Text('Your account will be protected by your password only.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Turn off')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final factor = await MfaService.instance.verifiedTotpFactor();
      if (factor == null) return;
      // Unenrolling requires an AAL2 session.
      final aal = SupabaseConfig.client.auth.mfa.getAuthenticatorAssuranceLevel();
      if (aal.currentLevel != AuthenticatorAssuranceLevels.aal2) {
        final ok = await _promptCode();
        if (ok != true) return;
      }
      await MfaService.instance.disable(factor.id);
      _snack('Two-factor authentication is off.');
      await _load();
    } catch (_) {
      _snack('Could not turn off two-factor authentication.');
    }
  }

  Future<void> _toggleTrust(UserDevice d, bool trusted) async {
    try {
      await _withStepUp(() => DeviceService.instance.setTrust(d.deviceId, trusted));
      await _load();
    } catch (_) {
      _snack('Could not update device trust.');
    }
  }

  Future<void> _revoke(UserDevice d) async {
    try {
      await _withStepUp(() => DeviceService.instance.revoke(d.id));
      if (d.deviceId != _currentDeviceId) {
        // Sessions are not tied to devices, so end all other sessions.
        await SupabaseConfig.client.auth.signOut(scope: SignOutScope.others);
      }
      _snack('Device removed.');
      await _load();
    } catch (_) {
      _snack('Could not remove device.');
    }
  }

  Future<void> _signOutOthers() async {
    try {
      await SupabaseConfig.client.auth.signOut(scope: SignOutScope.others);
      _snack('Signed out of all other devices.');
    } catch (_) {
      _snack('Could not sign out other devices.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Security')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_loadError!),
                    TextButton(onPressed: _load, child: const Text('Retry')),
                  ]),
                )
              : ListView(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.verified_user_outlined),
                      title: const Text('Two-factor authentication'),
                      subtitle: Text(_mfaOn
                          ? 'On \u2014 an authenticator app code is required at sign-in on new devices.'
                          : 'Off \u2014 add a second step to protect your account.'),
                      trailing: FilledButton.tonal(
                        onPressed: _mfaOn ? _disable : _enable,
                        child: Text(_mfaOn ? 'Turn off' : 'Turn on'),
                      ),
                    ),
                    const Divider(),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Text('Your devices', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    for (final d in _devices.where((d) => !d.revoked)) _deviceTile(d),
                    if (_devices.where((d) => !d.revoked).isEmpty)
                      const Padding(padding: EdgeInsets.all(16), child: Text('No devices recorded yet.')),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.logout),
                      title: const Text('Sign out of all other devices'),
                      onTap: _signOutOthers,
                    ),
                  ],
                ),
    );
  }

  Widget _deviceTile(UserDevice d) {
    final isThis = d.deviceId == _currentDeviceId;
    final seen = d.lastSeenAt;
    final when = '${seen.year}-${seen.month.toString().padLeft(2, '0')}-${seen.day.toString().padLeft(2, '0')}';
    return ListTile(
      leading: Icon(_iconFor(d.platform)),
      title: Text(isThis ? '${d.name} (this device)' : d.name),
      subtitle: Text('Last active $when${d.trusted ? ' \u00b7 Trusted' : ''}'),
      trailing: PopupMenuButton<String>(
        onSelected: (v) {
          if (v == 'trust') _toggleTrust(d, true);
          if (v == 'untrust') _toggleTrust(d, false);
          if (v == 'remove') _revoke(d);
        },
        itemBuilder: (_) => [
          if (_mfaOn) PopupMenuItem(value: d.trusted ? 'untrust' : 'trust', child: Text(d.trusted ? 'Stop trusting' : 'Trust for 30 days')),
          if (!isThis) const PopupMenuItem(value: 'remove', child: Text('Remove')),
        ],
      ),
    );
  }

  IconData _iconFor(String platform) {
    switch (platform) {
      case 'android':
      case 'ios':
        return Icons.smartphone;
      case 'web':
        return Icons.language;
      default:
        return Icons.computer;
    }
  }
}

class _EnrollDialog extends StatefulWidget {
  const _EnrollDialog({required this.enrollment});
  final TotpEnrollment enrollment;

  @override
  State<_EnrollDialog> createState() => _EnrollDialogState();
}

class _EnrollDialogState extends State<_EnrollDialog> {
  final _code = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await MfaService.instance.verify(widget.enrollment.factorId, _code.text);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) setState(() => _error = 'Invalid or expired code. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.enrollment;
    return AlertDialog(
      title: const Text('Set up authenticator app'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('1. Add this key to an authenticator app (Google Authenticator, Authy, 1Password\u2026).'),
            const SizedBox(height: 8),
            SelectableText(e.secret, style: const TextStyle(fontFamily: 'monospace', fontSize: 15)),
            Row(children: [
              TextButton.icon(
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copy key'),
                onPressed: () => Clipboard.setData(ClipboardData(text: e.secret)),
              ),
              TextButton.icon(
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Open app'),
                onPressed: () async {
                  final uri = Uri.tryParse(e.uri);
                  if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
                },
              ),
            ]),
            const SizedBox(height: 8),
            const Text('2. Enter the 6-digit code it shows.'),
            TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: '6-digit code', errorText: _error),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _confirm, child: const Text('Turn on')),
      ],
    );
  }
}
