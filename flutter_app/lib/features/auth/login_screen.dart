import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/providers/app_providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          TextField(controller: _email, decoration: const InputDecoration(labelText: 'Email')),
          TextField(controller: _password, decoration: const InputDecoration(labelText: 'Password'), obscureText: true),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () async {
              await ref.read(authServiceProvider).signIn(_email.text.trim(), _password.text.trim());
            },
            child: const Text('Login'),
          )
        ]),
      ),
    );
  }
}
