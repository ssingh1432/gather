import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/providers/app_providers.dart';

class SignupScreen extends ConsumerWidget {
  SignupScreen({super.key});
  final email = TextEditingController();
  final password = TextEditingController();
  final username = TextEditingController();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Signup')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          TextField(controller: username, decoration: const InputDecoration(labelText: 'Username')),
          TextField(controller: email, decoration: const InputDecoration(labelText: 'Email')),
          TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
          ElevatedButton(
            onPressed: () async {
              await ref.read(authServiceProvider).signUp(email.text.trim(), password.text.trim(), username: username.text.trim());
            },
            child: const Text('Create account'),
          )
        ]),
      ),
    );
  }
}
