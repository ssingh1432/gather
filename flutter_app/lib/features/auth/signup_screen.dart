import '../../core/l10n/app_l10n.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
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
  bool _googleLoading = false;
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
        SnackBar(content: Text(AppL10n.of(context).authRequiredSignup)),
      );
      return;
    }
    // Phone is optional — only validate format if the person entered one.
    String? normalizedPhone;
    if (phoneRaw.isNotEmpty) {
      normalizedPhone = _normalizedPhoneOrNull(phoneRaw);
      if (normalizedPhone == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppL10n.of(context).authPhoneInvalid)),
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
        SnackBar(content: Text(AppL10n.of(context).authPwMismatch)),
      );
      return;
    }
    if (!_agreedToPolicy) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppL10n.of(context).authAgreeTerms)),
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
            SnackBar(content: Text(AppL10n.of(context).authWelcome)),
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

  Future<void> _submitGoogle() async {
    if (!_agreedToPolicy) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppL10n.of(context).authAgreeTerms)),
      );
      return;
    }

    setState(() => _googleLoading = true);
    try {
      final auth = ref.read(authServiceProvider);
      if (auth.isNativeGoogleSignInSupported) {
        await auth.signInWithGoogle();
        if (mounted) context.go(_safeRedirect(widget.redirect) ?? '/');
      } else {
        // Desktop: opens the system browser; main.dart's deep-link handler
        // finishes the sign-in once the person returns to the app.
        await auth.signInWithGoogleOAuth();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Google sign-up failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loginLocation = _loginLocation(widget.redirect);

    return Scaffold(
      appBar: AppBar(title: Text(AppL10n.of(context).authCreateAccount)),
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
              OutlinedButton.icon(
                onPressed: (_loading || _googleLoading) ? null : _submitGoogle,
                icon: _googleLoading
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const FaIcon(FontAwesomeIcons.google, size: 18),
                label: Text(AppL10n.of(context).authContinueGoogle),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(AppL10n.of(context).authOr, style: Theme.of(context).textTheme.bodySmall),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: username,
                decoration: InputDecoration(
                  labelText: AppL10n.of(context).authUsername,
                  prefixIcon: Icon(Icons.person_outline),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: email,
                decoration: InputDecoration(
                  labelText: AppL10n.of(context).authEmail,
                  prefixIcon: Icon(Icons.email_outlined),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: phone,
                decoration: InputDecoration(
                  labelText: AppL10n.of(context).authMobileOptional,
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
                  labelText: AppL10n.of(context).authPassword,
                  helperText: AppL10n.of(context).authPwHelper,
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
                  labelText: AppL10n.of(context).authConfirmPw,
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
                        text: AppL10n.of(context).setPrivacyPolicy,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          decoration: TextDecoration.underline,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () => openExternalLink(context, kPrivacyPolicyUrl),
                      ),
                      const TextSpan(text: ' and '),
                      TextSpan(
                        text: AppL10n.of(context).setTerms,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          decoration: TextDecoration.underline,
                        ),
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
                    : Text(AppL10n.of(context).authCreateAccount),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => context.push(loginLocation),
                child: Text(AppL10n.of(context).authHaveAccount),
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

String? _safeRedirect(String? redirect) {
  if (redirect == null || redirect.isEmpty) return null;
  final uri = Uri.tryParse(redirect);
  if (uri == null || !uri.hasAbsolutePath || uri.hasScheme || uri.hasAuthority) {
    return null;
  }
  return uri.toString();
}
