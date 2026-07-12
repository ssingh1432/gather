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
  final username = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    email.dispose();
    phone.dispose();
    password.dispose();
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
    if (name.isEmpty || mail.isEmpty || pass.isEmpty || phone.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Username, email, mobile number, and password are required.')),
      );
      return;
    }
    final normalizedPhone = _normalizedPhoneOrNull(phone.text);
    if (normalizedPhone == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid 10-digit mobile number (e.g. 98XXXXXXXX).')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      await ref.read(authServiceProvider).signUp(mail, pass, username: name, phoneNumber: normalizedPhone);
      if (!mounted) return;

      if (SupabaseConfig.currentUserId != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account created. You can continue now.')),
        );
        context.go(_safeRedirect(widget.redirect) ?? '/');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account created. Please verify your email, then log in.')),
        );
        context.go(_loginLocation(widget.redirect));
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
      appBar: AppBar(title: const Text('Signup')),
      body: ResponsiveCenter(
        maxWidth: 420,
        child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          TextField(controller: username, decoration: const InputDecoration(labelText: 'Username')),
          TextField(
            controller: email,
            decoration: const InputDecoration(labelText: 'Email'),
            keyboardType: TextInputType.emailAddress,
          ),
          TextField(
            controller: phone,
            decoration: const InputDecoration(
              labelText: 'Mobile number',
              hintText: '98XXXXXXXX',
              prefixText: '+977 ',
            ),
            keyboardType: TextInputType.phone,
          ),
          TextField(
            controller: password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password'),
            onSubmitted: (_) => _loading ? null : _submit(),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loading ? null : _submit,
            child: _loading
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Create account'),
          ),
          TextButton(
            onPressed: () => context.push(loginLocation),
            child: const Text('Already have an account? Log in'),
          ),
        ]),
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
