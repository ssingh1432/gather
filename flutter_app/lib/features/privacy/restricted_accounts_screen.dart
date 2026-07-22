import 'package:flutter/material.dart';

import '../../shared/widgets/reusables.dart';
import '../data/repositories.dart';

/// Lists everyone the current user has restricted, with a one-tap
/// unrestrict. Restricting is one-directional and never disclosed to the
/// restricted user — reachable from Settings > Privacy > Restricted
/// accounts.
class RestrictedAccountsScreen extends StatefulWidget {
  const RestrictedAccountsScreen({super.key});

  @override
  State<RestrictedAccountsScreen> createState() => _RestrictedAccountsScreenState();
}

class _RestrictedAccountsScreenState extends State<RestrictedAccountsScreen> {
  final _repo = PrivacyRepository();
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repo.restrictedUsers();
  }

  Future<void> _unrestrict(String userId) async {
    await _repo.unrestrictUser(userId);
    if (mounted) setState(() => _future = _repo.restrictedUsers());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Restricted accounts')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ErrorRetryState(
              title: 'Unable to load restricted accounts',
              message: 'Check your connection and try again.',
              onRetry: () => setState(() => _future = _repo.restrictedUsers()),
            );
          }
          final rows = snapshot.data ?? const [];
          if (rows.isEmpty) {
            return const EmptyState(
              icon: Icons.shield_outlined,
              title: 'No restricted accounts',
              message: "Comments from accounts you restrict only show to you and them, and they're never told.",
            );
          }
          return ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final row = rows[index];
              final userId = row['restricted_id'] as String;
              final user = row['users'] as Map<String, dynamic>?;
              final username = user?['username'] as String? ?? 'Unknown';
              final avatarUrl = user?['profile_photo_url'] as String?;
              return ListTile(
                leading: ProfileAvatar(url: avatarUrl, radius: 20),
                title: Text(username),
                trailing: OutlinedButton(
                  onPressed: () => _unrestrict(userId),
                  child: const Text('Unrestrict'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
