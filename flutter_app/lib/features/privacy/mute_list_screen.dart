import 'package:flutter/material.dart';

import '../../shared/widgets/reusables.dart';
import '../data/repositories.dart';

/// Lists everyone the current user has muted, with a one-tap unmute.
/// Unlike blocking, muting is one-directional and never disclosed to the
/// muted user — reachable from Settings > Privacy > Muted accounts.
class MuteListScreen extends StatefulWidget {
  const MuteListScreen({super.key});

  @override
  State<MuteListScreen> createState() => _MuteListScreenState();
}

class _MuteListScreenState extends State<MuteListScreen> {
  final _repo = PrivacyRepository();
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repo.mutedUsers();
  }

  Future<void> _unmute(String userId) async {
    await _repo.unmuteUser(userId);
    if (mounted) setState(() => _future = _repo.mutedUsers());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Muted accounts')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ErrorRetryState(
              title: 'Unable to load muted accounts',
              message: 'Check your connection and try again.',
              onRetry: () => setState(() => _future = _repo.mutedUsers()),
            );
          }
          final rows = snapshot.data ?? const [];
          if (rows.isEmpty) {
            return const EmptyState(
              icon: Icons.volume_off_outlined,
              title: 'No muted accounts',
              message: "Accounts you mute won't show up in your feed, but you'll still stay connected.",
            );
          }
          return ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final row = rows[index];
              final userId = row['muted_id'] as String;
              final user = row['users'] as Map<String, dynamic>?;
              final username = user?['username'] as String? ?? 'Unknown';
              final avatarUrl = user?['profile_photo_url'] as String?;
              return ListTile(
                leading: ProfileAvatar(url: avatarUrl, radius: 20),
                title: Text(username),
                trailing: OutlinedButton(
                  onPressed: () => _unmute(userId),
                  child: const Text('Unmute'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
