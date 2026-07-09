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
  final password = TextEditingController();
  final username = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    username.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = username.text.trim();
    final mail = email.text.trim();
    final pass = password.text.trim();
    if (name.isEmpty || mail.isEmpty || pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Username, email, and password are required.')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      await ref.read(authServiceProvider).signUp(mail, pass, username: name);
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
