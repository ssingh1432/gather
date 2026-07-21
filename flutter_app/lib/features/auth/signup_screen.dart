import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/legal_constants.dart';
import '../../core/supabase_client.dart';
import '../../core/responsive.dart';
import '../../shared/providers/app_providers.dart';
import '../../shared/utils/external_link.dart';
import '../../shared/utils/password_validator.dart';

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
  bool _agreedToPolicy = false;

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
    final passwordError = PasswordValidator.validate(pass);
    if (passwordError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(passwordError)),
      );
      return;
    }
    if (pass != confirmPass) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match.')),
      );
      return;
    }
    if (!_agreedToPolicy) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please agree to the Privacy Policy and Terms of Service to continue.')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final auth = ref.read(authServiceProvider);
      await auth.signUp(mail, pass, username: name, phoneNumber: normalizedPhone);
      if (!mounted) return;

      // Consent (privacy policy + terms) is now recorded server-side by
      // the handle_new_user DB trigger at account-creation time — it no
      // longer depends on a client session existing, so it can't be
      // silently skipped by the confirmation-required path below.

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
        // Confirmation required — finish it in-app with a 6-digit email
        // code instead of a link to click.
        final phoneParam = normalizedPhone == null ? '' : '&phone=$normalizedPhone';
        context.go('/verify-email?email=${Uri.encodeComponent(mail)}$phoneParam');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Signup failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loginLocation = _loginLocation(widget.redirect);

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
                  helperText: 'At least 8 characters, with upper, lower case and a number',
                  helperMaxLines: 2,
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
              const SizedBox(height: 16),
              CheckboxListTile(
                value: _agreedToPolicy,
                onChanged: (v) => setState(() => _agreedToPolicy = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: RichText(
                  text: TextSpan(
                    style: DefaultTextStyle.of(context).style.copyWith(fontSize: 13),
                    children: [
                      const TextSpan(text: 'I agree to the '),
                      TextSpan(
                        text: 'Privacy Policy',
                        style: const TextStyle(color: Colors.teal, decoration: TextDecoration.underline),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () => openExternalLink(context, kPrivacyPolicyUrl),
                      ),
                      const TextSpan(text: ' and '),
                      TextSpan(
                        text: 'Terms of Service',
                        style: const TextStyle(color: Colors.teal, decoration: TextDecoration.underline),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () => openExternalLink(context, kTermsOfServiceUrl),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
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
