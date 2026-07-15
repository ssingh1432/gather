import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase_client.dart';
import '../../core/responsive.dart';
import '../../shared/providers/app_providers.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key, this.redirect});

  final String? redirect;

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final email = TextEditingController();
  final phone = TextEditingController();
  final password = TextEditingController();
  final confirmPassword = TextEditingController();
  final username = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _resending = false;
  // Non-null once signup succeeds but the account still needs email
  // confirmation (i.e. there's no session yet). Drives the "check your
  // email" state below instead of a snackbar that's easy to miss.
  String? _awaitingConfirmationFor;

  @override
  void dispose() {
    email.dispose();
    phone.dispose();
    password.dispose();
    confirmPassword.dispose();
    username.dispose();
    super.dispose();
  }

  /// Normalizes a Nepali mobile number to a plain 10-digit string
  /// (accepts an optional +977 / 977 / 0 prefix). Returns null if invalid.
  String? _normalizedPhoneOrNull(String raw) {
    var digits = raw.trim().replaceAll(RegExp(r'[\s-]'), '');
    if (digits.startsWith('+977')) digits = digits.substring(4);
    if (digits.startsWith('977')) digits = digits.substring(3);
    if (digits.startsWith('0')) digits = digits.substring(1);
    if (!RegExp(r'^9\d{9}$').hasMatch(digits)) return null;
    return digits;
  }

  Future<void> _submit() async {
    final name = username.text.trim();
    final mail = email.text.trim();
    final pass = password.text.trim();
    final confirmPass = confirmPassword.text.trim();
    final phoneRaw = phone.text.trim();

    if (name.isEmpty || mail.isEmpty || pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Username, email, and password are required.')),
      );
      return;
    }
    // Phone is optional — only validate format if the person entered one.
    String? normalizedPhone;
    if (phoneRaw.isNotEmpty) {
      normalizedPhone = _normalizedPhoneOrNull(phoneRaw);
      if (normalizedPhone == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid 10-digit mobile number (e.g. 98XXXXXXXX), or leave it blank.')),
        );
        return;
      }
    }
    if (pass.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password must be at least 6 characters.')),
      );
      return;
    }
    if (pass != confirmPass) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match.')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      await ref.read(authServiceProvider).signUp(mail, pass, username: name, phoneNumber: normalizedPhone);
      if (!mounted) return;

      if (SupabaseConfig.currentUserId != null) {
        // Email confirmation is off (or this address was pre-confirmed) —
        // there's already a session, so the person is logged in.
        if (normalizedPhone != null) {
          context.go('/verify-phone?phone=$normalizedPhone');
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Welcome to Gather!')),
          );
          context.go('/');
        }
      } else {
        // Show a clear, persistent "check your email" state instead of a
        // snackbar the person might miss.
        setState(() => _awaitingConfirmationFor = mail);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Signup failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    final mail = _awaitingConfirmationFor;
    if (mail == null) return;
    setState(() => _resending = true);
    try {
      await ref.read(authServiceProvider).resendSignupEmail(mail);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Confirmation email resent.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not resend: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loginLocation = _loginLocation(widget.redirect);

    if (_awaitingConfirmationFor != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Check your email')),
        body: ResponsiveCenter(
          maxWidth: 420,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.mark_email_unread_outlined, size: 48),
                const SizedBox(height: 16),
                Text(
                  'Confirm your email',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'We sent a confirmation link to ${_awaitingConfirmationFor!}. '
                  'Open it on this device to activate your account — you\'ll be signed in automatically, '
                  'no need to come back and log in.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                OutlinedButton(
                  onPressed: _resending ? null : _resend,
                  child: _resending
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Resend email'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => context.go(loginLocation),
                  child: const Text('Back to login'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: ResponsiveCenter(
        maxWidth: 420,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Image.asset('assets/brand/gather_mark.png', width: 64, height: 64),
              const SizedBox(height: 8),
              Text(
                'Join Gather',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 20),
              TextField(
                controller: username,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: email,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email_outlined),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: phone,
                decoration: const InputDecoration(
                  labelText: 'Mobile number (optional)',
                  hintText: '98XXXXXXXX',
                  helperText: "Add it now or later — required only for monetization",
                  prefixIcon: Icon(Icons.phone_outlined),
                  prefixText: '+977 ',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: password,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: confirmPassword,
                obscureText: _obscureConfirm,
                decoration: InputDecoration(
                  labelText: 'Confirm password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
                onSubmitted: (_) => _loading ? null : _submit(),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _loading ? null : _submit,
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                child: _loading
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Create account'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => context.push(loginLocation),
                child: const Text('Already have an account? Log in'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _loginLocation(String? redirect) => redirect == null || redirect.isEmpty
    ? '/login'
    : '/login?redirect=${Uri.encodeComponent(redirect)}';
