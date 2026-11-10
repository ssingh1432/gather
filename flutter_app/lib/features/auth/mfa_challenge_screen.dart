import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/services/auth_service.dart';
import '../../shared/services/device_service.dart';
import '../../shared/services/mfa_service.dart';

/// Shown after a password/Google sign-in when the account has 2FA enabled
/// and this device is not trusted. The router keeps the user here until the
/// session reaches AAL2 (see [MfaGate]).
class MfaChallengeScreen extends StatefulWidget {
  const MfaChallengeScreen({super.key});

  @override
  State<MfaChallengeScreen> createState() => _MfaChallengeScreenState();
}

class _MfaChallengeScreenState extends State<MfaChallengeScreen> {
  final _code = TextEditingController();
  bool _trust = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code from your authenticator app.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final factor = await MfaService.instance.verifiedTotpFactor();
      if (factor == null) {
        // Factor was removed elsewhere; nothing left to challenge.
        await MfaGate.refresh();
        if (mounted) context.go('/');
        return;
      }
      await MfaService.instance.verify(factor.id, code);
      if (_trust) {
        try {
          await DeviceService.instance.setTrust(await DeviceService.instance.deviceId(), true);
        } catch (_) {
          // Trusting is optional; never block login on it.
        }
      }
      await MfaGate.refresh();
      if (mounted) context.go('/');
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = 'That code is not valid or has expired. Try the next one. (${e.message})');
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not verify the code. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    await AuthService().signOut();
    MfaGate.clear();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(title: const Text('Two-factor authentication'), automaticallyImplyLeading: false),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.shield_outlined, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'Enter the 6-digit code from your authenticator app to finish signing in.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _code,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 6,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(fontSize: 24, letterSpacing: 8),
                    decoration: InputDecoration(
                      labelText: 'Authentication code',
                      errorText: _error,
                      errorMaxLines: 3,
                    ),
                    onSubmitted: (_) => _busy ? null : _verify(),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _trust,
                    onChanged: _busy ? null : (v) => setState(() => _trust = v ?? false),
                    title: const Text('Trust this device for 30 days'),
                    subtitle: const Text('Only on a device you own.'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _busy ? null : _verify,
                    child: _busy
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Verify'),
                  ),
                  TextButton(onPressed: _busy ? null : _cancel, child: const Text('Cancel and sign out')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
