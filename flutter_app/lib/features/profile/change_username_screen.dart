import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';
import '../../shared/utils/username_validator.dart';
import '../../shared/providers/app_providers.dart';

class ChangeUsernameScreen extends ConsumerStatefulWidget {
  const ChangeUsernameScreen({super.key});

  @override
  ConsumerState<ChangeUsernameScreen> createState() => _ChangeUsernameScreenState();
}

class _ChangeUsernameScreenState extends ConsumerState<ChangeUsernameScreen> {
  final _ctrl = TextEditingController();
  String? _current;
  DateTime? _nextChange;
  String? _error;
  bool _busy = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) return;
    try {
      final row = await SupabaseConfig.client.from('users').select('username, username_changed_at').eq('id', uid).single();
      final changed = row['username_changed_at'] as String?;
      if (!mounted) return;
      setState(() {
        _current = row['username'] as String?;
        if (changed != null) {
          final next = DateTime.parse(changed).toLocal().add(const Duration(days: 30));
          if (next.isAfter(DateTime.now())) _nextChange = next;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load your username.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final value = _ctrl.text.trim().toLowerCase();
    final localError = UsernameValidator.validate(value);
    if (localError != null) {
      setState(() => _error = localError);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change username?'),
        content: Text('Your username will become @$value. You can only change it once every 30 days. '
            'Links and mentions that use @${_current ?? 'your old name'} may stop pointing to you.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Change')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await SupabaseConfig.client.rpc('change_username', params: {'p_new': value});
      ref.invalidate(currentUserProfileProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Username changed to @$value')));
        context.pop();
      }
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not change username. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = _nextChange != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Change username')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_current != null) Text('Current username: @$_current', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                if (locked)
                  Text(
                    'You can change your username again on '
                    '${_nextChange!.year}-${_nextChange!.month.toString().padLeft(2, '0')}-${_nextChange!.day.toString().padLeft(2, '0')}.',
                  )
                else ...[
                  TextField(
                    controller: _ctrl,
                    autofocus: true,
                    maxLength: 30,
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.none,
                    decoration: InputDecoration(
                      labelText: 'New username',
                      prefixText: '@',
                      helperText: '3-30 characters: lowercase letters, numbers, _ and .',
                      errorText: _error,
                      errorMaxLines: 3,
                    ),
                    onSubmitted: (_) => _busy ? null : _save(),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    child: _busy
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Change username'),
                  ),
                ],
                if (locked && _error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!)),
              ],
            ),
    );
  }
}
