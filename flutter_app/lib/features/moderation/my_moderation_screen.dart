import 'package:flutter/material.dart';

import '../data/repositories.dart';

/// Lets a user see moderation actions taken against their account
/// (warnings, strikes, suspensions, bans) and submit an appeal.
class MyModerationScreen extends StatefulWidget {
  const MyModerationScreen({super.key});

  @override
  State<MyModerationScreen> createState() => _MyModerationScreenState();
}

class _MyModerationScreenState extends State<MyModerationScreen> {
  final repo = ModerationRepository();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _actions = const [];
  List<Map<String, dynamic>> _appeals = const [];

  static const _labels = {
    'warning_issued': 'Warning',
    'strike_added': 'Strike',
    'user_suspended': 'Suspension',
    'user_banned': 'Ban',
    'user_reinstated': 'Reinstated',
  };

  static const _appealable = {'warning_issued', 'strike_added', 'user_suspended', 'user_banned'};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _actions = await repo.myModerationActions();
      _appeals = await repo.myAppeals();
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _hasAppeal(String actionId) => _appeals.any((a) => a['action_id'] == actionId);

  Future<void> _appeal(Map<String, dynamic> action) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Submit an appeal'),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          decoration: const InputDecoration(hintText: 'Explain why you believe this action should be reversed'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Submit')),
        ],
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    try {
      await repo.submitAppeal(action['id'].toString(), ctrl.text.trim());
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Appeal submitted — a moderator will review it.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not submit appeal: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account & moderation history')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : _actions.isEmpty
                  ? const Center(child: Text('No moderation actions on your account.'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        itemCount: _actions.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final a = _actions[index];
                          final action = a['action']?.toString() ?? '';
                          final appealed = _hasAppeal(a['id'].toString());
                          return ListTile(
                            leading: const Icon(Icons.gavel_outlined),
                            title: Text(_labels[action] ?? action),
                            subtitle: Text('${a['note'] ?? ''}\n${a['created_at']}'),
                            isThreeLine: true,
                            trailing: !_appealable.contains(action)
                                ? null
                                : appealed
                                    ? const Chip(label: Text('Appeal submitted'))
                                    : TextButton(onPressed: () => _appeal(a), child: const Text('Appeal')),
                          );
                        },
                      ),
                    ),
    );
  }
}
