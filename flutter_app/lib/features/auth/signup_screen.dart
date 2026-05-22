import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/providers/app_providers.dart';

class SignupScreen extends ConsumerWidget {
  SignupScreen({super.key});
  final email = TextEditingController();
  final password = TextEditingController();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Signup')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          TextField(controller: email),
          TextField(controller: password, obscureText: true),
          ElevatedButton(
            onPressed: () async {
              await ref.read(authServiceProvider).signUp(email.text.trim(), password.text.trim());
            },
            child: const Text('Create account'),
          )
        ]),
      ),
    );
  }
}
