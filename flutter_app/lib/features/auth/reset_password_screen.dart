import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';
import '../../core/responsive.dart';
import '../../shared/providers/app_providers.dart';

/// Where the "Reset password" email link lands (see
/// `AuthService.resetPassword`'s `redirectTo`). supabase_flutter picks up
/// the recovery token from the URL automatically on web and fires a
/// [AuthChangeEvent.passwordRecovery] event with an active session, which
/// is all this screen needs to call `updateUser`.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  bool _done = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    // If the recovery link already established a session by the time this
    // screen builds, we're ready immediately. Otherwise wait for the
    // passwordRecovery auth event (covers the brief moment supabase_flutter
    // is still parsing the URL fragment on web).
    _ready = SupabaseConfig.maybeClient?.auth.currentSession != null;
    SupabaseConfig.maybeClient?.auth.onAuthStateChange.listen((state) {
      if (!mounted) return;
      if (state.event == AuthChangeEvent.passwordRecovery || state.session != null) {
        setState(() => _ready = true);
      }
    });
  }

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pass = _password.text.trim();
    final confirm = _confirm.text.trim();
    if (pass.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password must be at least 6 characters.')),
      );
      return;
    }
    if (pass != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match.')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      await ref.read(authServiceProvider).updatePassword(pass);
      if (mounted) setState(() => _done = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update password: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: ResponsiveCenter(
        maxWidth: 420,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _done
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text("Your password has been updated. You're signed in."),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => context.go('/'),
                      child: const Text('Continue to Gather'),
                    ),
                  ],
                )
              : !_ready
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          "This reset link is invalid or has expired. Request a new one from the login screen.",
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () => context.go('/forgot'),
                          child: const Text('Request new link'),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('Choose a new password for your account.'),
                        const SizedBox(height: 20),
                        TextField(
                          controller: _password,
                          obscureText: _obscure,
                          decoration: InputDecoration(
                            labelText: 'New password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                              onPressed: () => setState(() => _obscure = !_obscure),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _confirm,
                          obscureText: _obscure,
                          decoration: const InputDecoration(
                            labelText: 'Confirm new password',
                            prefixIcon: Icon(Icons.lock_outline),
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _loading ? null : _submit(),
                        ),
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _loading ? null : _submit,
                          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                          child: _loading
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Update password'),
                        ),
                      ],
                    ),
        ),
      ),
    );
  }
}
