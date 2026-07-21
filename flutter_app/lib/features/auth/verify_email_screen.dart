import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/responsive.dart';
import '../../shared/providers/app_providers.dart';
import 'profile_prompt.dart';

/// Shown right after signup to confirm the account via a 6-digit email
/// code (Supabase's "Confirm signup" OTP, sent through Resend).
///
/// Replaces the old "click the link we emailed you" flow: the person never
/// has to leave the app, which also sidesteps deep-link/redirect handling
/// entirely. Requires the Supabase "Confirm signup" email template to use
/// `{{ .Token }}` instead of `{{ .ConfirmationURL }}`.
///
/// Unlike phone verification, this step can't be skipped — until it's
/// done there's no session at all, so there's nothing to "skip" into.
class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key, required this.email, this.phone});

  final String email;

  /// Normalized 10-digit Nepali number, if one was entered at signup.
  /// Carried through so we can chain into phone verification once the
  /// email is confirmed and a session exists.
  final String? phone;

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  final _code = TextEditingController();
  bool _resending = false;
  bool _verifying = false;
  String? _error;
  int _resendCooldown = 30;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  @override
  void dispose() {
    _code.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _resendCooldown = 30;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _resendCooldown--);
      if (_resendCooldown <= 0) t.cancel();
    });
  }

  Future<void> _resend() async {
    setState(() {
      _resending = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).resendSignupEmail(widget.email);
      _startCooldown();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('New code sent.')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not resend the code: $e');
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the code sent to your email.')),
      );
      return;
    }
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      final auth = ref.read(authServiceProvider);
      await auth.verifySignupEmailOtp(widget.email, code);
      if (!mounted) return;

      // This is the first moment a session exists when confirmation was
      // required, so beta access — normally claimed right after signUp()
      // — gets claimed here instead.
      final betaAllowed = await auth.claimBetaAccessForCurrentUser();
      if (!betaAllowed) {
        await auth.signOut();
        if (mounted) setState(() => _error = 'Closed beta access required for this account.');
        return;
      }

      if (!mounted) return;
      if (widget.phone != null) {
        context.go('/verify-phone?phone=${widget.phone}');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Welcome to Gather!')),
        );
        await showProfileCompletionPrompt(context);
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'That code didn\'t work: $e');
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Confirm your email')),
      body: ResponsiveCenter(
        maxWidth: 420,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.mark_email_read_outlined, size: 48, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              Text(
                'We sent a code to ${widget.email}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              const Text(
                'Enter it below to activate your account.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 24),
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 6,
                style: const TextStyle(fontSize: 24, letterSpacing: 8),
                decoration: const InputDecoration(
                  counterText: '',
                  border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                  hintText: '••••••',
                ),
                onSubmitted: (_) => _verifying ? null : _verify(),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _verifying ? null : _verify,
                child: _verifying
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Confirm'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: (_resendCooldown > 0 || _resending) ? null : _resend,
                child: Text(_resendCooldown > 0 ? 'Resend code in ${_resendCooldown}s' : 'Resend code'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
