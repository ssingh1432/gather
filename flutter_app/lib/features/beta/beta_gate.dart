import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/providers/app_providers.dart';

/// Phase 4 beta-only UI guard. Supabase RLS/RPCs are authoritative; this only
/// gives non-allowlisted users a clear blocked state instead of empty screens.
class BetaGate extends ConsumerWidget {
  const BetaGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(betaAccessProvider);
    return access.when(
      data: (allowed) => allowed ? child : const _ClosedBetaBlocked(),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ClosedBetaError(message: '$error'),
    );
  }
}

class _ClosedBetaBlocked extends StatelessWidget {
  const _ClosedBetaBlocked();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 56, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text('Closed beta access required', style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              const Text(
                'Gather is currently limited to invited beta testers. If you were invited, log in with the same email address from your invite.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: () => context.go('/login'), child: const Text('Back to login')),
            ],
          ),
        ),
      );
}

class _ClosedBetaError extends StatelessWidget {
  const _ClosedBetaError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 12),
              Text('Could not verify beta access', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: () => context.go('/login'), child: const Text('Log in again')),
            ],
          ),
        ),
      );
}
