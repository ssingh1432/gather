import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Shown right after a new account is created (and after the optional phone
/// verification step). Completing the profile is optional — either choice
/// takes the person into the app.
Future<void> showProfileCompletionPrompt(BuildContext context) async {
  if (!context.mounted) return;
  final addNow = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('Welcome to Gather! 🎉'),
      content: const Text(
        'Want to add a profile photo and a short bio now? It helps people recognize you. '
        'You can always do this later from your profile.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Later'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Add now'),
        ),
      ],
    ),
  );

  if (!context.mounted) return;
  if (addNow == true) {
    context.go('/edit-profile');
  } else {
    context.go('/');
  }
}
