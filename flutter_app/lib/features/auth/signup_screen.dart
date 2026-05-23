import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/providers/app_providers.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Signup')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          TextField(controller: username, decoration: const InputDecoration(labelText: 'Username')),
          TextField(controller: email, decoration: const InputDecoration(labelText: 'Email')),
          TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
          ElevatedButton(
            onPressed: _loading
                ? null
                : () async {
                    final name = username.text.trim();
                    final mail = email.text.trim();
                    final pass = password.text.trim();
                    if (name.isEmpty || mail.isEmpty || pass.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Username, email, and password are required.')));
                      return;
                    }
                    setState(() => _loading = true);
                    try {
                      await ref.read(authServiceProvider).signUp(mail, pass, username: name);
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account created. Please verify your email if prompted.')));
                    } catch (e) {
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Signup failed: $e')));
                    } finally {
                      if (mounted) setState(() => _loading = false);
                    }
                  },
            child: _loading
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Create account'),
          )
        ]),
      ),
    );
  }
}
