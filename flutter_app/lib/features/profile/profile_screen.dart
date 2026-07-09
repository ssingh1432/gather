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
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit profile',
            onPressed: () => context.push('/edit-profile'),
          ),
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
          final displayName = (u['display_name'] as String?)?.isNotEmpty == true
              ? u['display_name'] as String
              : (u['username'] ?? '');
          final interests = ((u['interests'] as List?) ?? []).cast<String>();
          final isProfileBare = (u['bio'] as String?)?.isEmpty != false &&
              u['profile_photo_url'] == null &&
              interests.isEmpty;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (isProfileBare) ...[
                Card(
                  color: const Color(0xFF1D9E75).withValues(alpha: 0.08),
                  child: ListTile(
                    leading: const Icon(Icons.person_add_alt_1, color: Color(0xFF1D9E75)),
                    title: const Text('Complete your profile'),
                    subtitle: const Text('Add a photo, bio, and interests so others can find you'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/edit-profile'),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (u['profile_photo_url'] != null) ...[
                CircleAvatar(radius: 40, backgroundImage: NetworkImage(u['profile_photo_url'])),
                const SizedBox(height: 12),
              ],
              Text(displayName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              if (u['location'] != null) ...[
                const SizedBox(height: 4),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.place_outlined, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(u['location'], style: const TextStyle(color: Colors.grey)),
                ]),
              ],
              if ((u['bio'] as String?)?.isNotEmpty ?? false) ...[
                const SizedBox(height: 8),
                Text(u['bio']),
              ],
              if (interests.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [for (final tag in interests) Chip(label: Text(tag), visualDensity: VisualDensity.compact)],
                ),
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
