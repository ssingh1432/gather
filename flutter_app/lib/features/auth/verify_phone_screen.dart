import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/responsive.dart';
import '../../shared/providers/app_providers.dart';
import 'profile_prompt.dart';

/// Shown right after signup to verify the mobile number via an SMS OTP
/// (sent through Supabase's Phone provider, backed by Twilio).
///
/// Verification is optional — if the SMS provider isn't configured yet, or
/// the person just wants to do it later, they can skip and still use the
/// account normally. We never want a flaky SMS step to block registration.
class VerifyPhoneScreen extends ConsumerStatefulWidget {
  const VerifyPhoneScreen({super.key, required this.phone});

  /// Normalized 10-digit Nepali number (no country code).
  final String phone;

  @override
  ConsumerState<VerifyPhoneScreen> createState() => _VerifyPhoneScreenState();
}

class _VerifyPhoneScreenState extends ConsumerState<VerifyPhoneScreen> {
  final _code = TextEditingController();
  bool _sending = true;
  bool _verifying = false;
  String? _sendError;
  int _resendCooldown = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _send();
  }

  @override
  void dispose() {
    _code.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      await ref.read(authServiceProvider).sendPhoneOtp(widget.phone);
      _startCooldown();
    } catch (e) {
      if (mounted) setState(() => _sendError = 'Could not send the code: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
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

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the code sent to your phone.')),
      );
      return;
    }
    setState(() => _verifying = true);
    try {
      await ref.read(authServiceProvider).verifyPhoneOtp(widget.phone, code);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Phone number verified!')),
      );
      await showProfileCompletionPrompt(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Verification failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _skip() async {
    await showProfileCompletionPrompt(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify your number')),
      body: ResponsiveCenter(
        maxWidth: 420,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.sms_outlined, size: 48, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              Text(
                'We sent a code to +977 ${widget.phone}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              const Text(
                'Enter it below to verify your number.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              if (_sendError != null) ...[
                const SizedBox(height: 12),
                Text(_sendError!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
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
                onPressed: _verifying || _sending ? null : _verify,
                child: _verifying
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Verify'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: (_resendCooldown > 0 || _sending) ? null : _send,
                child: Text(_resendCooldown > 0 ? 'Resend code in ${_resendCooldown}s' : 'Resend code'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _verifying ? null : _skip,
                child: const Text('Skip for now'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
