import 'package:flutter/material.dart';

import '../../core/supabase_client.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/reusables.dart';
import '../data/repositories.dart';

/// Lists everyone the current user has blocked, with a one-tap unblock —
/// reachable from Settings > Privacy > Blocked accounts.
class BlockedAccountsScreen extends StatefulWidget {
  const BlockedAccountsScreen({super.key});

  @override
  State<BlockedAccountsScreen> createState() => _BlockedAccountsScreenState();
}

class _BlockedAccountsScreenState extends State<BlockedAccountsScreen> {
  final _repo = ProfileRepository();
  late Future<List<RecommendedUser>> _future;

  String? get _uid => SupabaseConfig.currentUserId;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<RecommendedUser>> _load() {
    final uid = _uid;
    if (uid == null) return Future.value(const []);
    return _repo.blockedUsersList(uid);
  }

  Future<void> _unblock(RecommendedUser user) async {
    final uid = _uid;
    if (uid == null) return;
    await _repo.unblock(user.id, uid);
    if (mounted) setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Blocked accounts')),
      body: FutureBuilder<List<RecommendedUser>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ErrorRetryState(
              title: 'Unable to load blocked accounts',
              message: 'Check your connection and try again.',
              onRetry: () => setState(() => _future = _load()),
            );
          }
          final users = snapshot.data ?? const [];
          if (users.isEmpty) {
            return const EmptyState(
              icon: Icons.block_outlined,
              title: 'No blocked accounts',
              message: 'Accounts you block will show up here.',
            );
          }
          return ListView.separated(
            itemCount: users.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final user = users[index];
              return ListTile(
                leading: ProfileAvatar(url: user.avatarUrl, radius: 20),
                title: Text(user.username),
                trailing: OutlinedButton(
                  onPressed: () => _unblock(user),
                  child: const Text('Unblock'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
