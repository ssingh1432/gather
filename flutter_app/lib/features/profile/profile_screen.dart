import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase_client.dart';
import '../../shared/providers/app_providers.dart';
import '../data/repositories.dart';

/// The current user's own profile tab (bottom nav "Profile"). Distinct from
/// [UserProfileScreen], which renders someone else's profile by [userId]
/// and shows Follow/Block actions instead of Sign out.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) {
      return const Scaffold(body: Center(child: Text('Not signed in.')));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () async {
              await ref.read(authServiceProvider).signOut();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: FutureBuilder(
        future: ProfileRepository().loadProfile(uid),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final u = snapshot.data;
          if (u == null) {
            return const Center(child: Text('Profile not found.'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(u['username'] ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              if ((u['bio'] as String?)?.isNotEmpty ?? false) ...[
                const SizedBox(height: 8),
                Text(u['bio']),
              ],
              const SizedBox(height: 16),
              FutureBuilder<List<int>>(
                future: Future.wait([
                  ProfileRepository().followers(uid),
                  ProfileRepository().following(uid),
                ]),
                builder: (context, counts) {
                  final followers = counts.data?[0] ?? 0;
                  final following = counts.data?[1] ?? 0;
                  return Row(
                    children: [
                      Text('$followers followers'),
                      const SizedBox(width: 16),
                      Text('$following following'),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              ListTile(
                leading: const Icon(Icons.bookmark_outline),
                title: const Text('Bookmarks'),
                onTap: () => context.push('/bookmarks'),
              ),
              ListTile(
                leading: const Icon(Icons.notifications_outlined),
                title: const Text('Notifications'),
                onTap: () => context.push('/notifications'),
              ),
            ],
          );
        },
      ),
    );
  }
}
