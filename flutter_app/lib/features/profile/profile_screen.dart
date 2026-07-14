import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/supabase_client.dart';
import '../../shared/models/models.dart';
import '../../shared/providers/app_providers.dart';
import '../../shared/utils/external_link.dart';
import '../../shared/widgets/profile_view.dart';
import '../../shared/widgets/reusables.dart';
import '../data/repositories.dart';

/// The current user's own profile tab (bottom nav "Profile"). Distinct from
/// [UserProfileScreen], which renders someone else's profile by [userId]
/// and shows Follow/Block actions instead of Sign out.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late Future<_ProfileBundle> _future;
  bool _signingOut = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ProfileBundle> _load() async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) throw StateError('Not signed in');
    final profileRepo = ProfileRepository();
    final results = await Future.wait([
      profileRepo.loadProfile(uid),
      profileRepo.followers(uid),
      profileRepo.following(uid),
      profileRepo.postCount(uid),
      FeedRepository().postsByUser(uid),
    ]);
    final profile = results[0] as Map<String, dynamic>?;
    if (profile == null) throw StateError('Profile not found');
    return _ProfileBundle(
      profile: profile,
      followerCount: results[1] as int,
      followingCount: results[2] as int,
      postCount: results[3] as int,
      posts: results[4] as List<PostModel>,
    );
  }

  Future<void> _refresh() async {
    final next = _load();
    await next;
    if (mounted) setState(() => _future = next);
  }

  Future<void> _confirmAndSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text("You'll need to log in again to use Gather."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Sign out')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _signingOut = true);
    try {
      await ref.read(authServiceProvider).signOut();
      ref.invalidate(recommendedUsersProvider);
      ref.invalidate(sentFriendRequestsProvider);
      if (mounted) context.go('/login');
    } catch (e) {
      if (mounted) {
        setState(() => _signingOut = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not sign out. Please check your connection and try again. $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
            onPressed: () => context.push('/edit-profile').then((_) => _refresh()),
          ),
          PopupMenuButton<String>(
            icon: _signingOut ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'share') {
                Share.share('Check out my profile on Gather: https://eiquoab.xyz/user?id=$uid');
              } else if (value == 'signout') {
                _confirmAndSignOut();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'share', child: ListTile(leading: Icon(Icons.ios_share), title: Text('Share profile'), contentPadding: EdgeInsets.zero)),
              PopupMenuItem(
                value: 'signout',
                child: ListTile(leading: Icon(Icons.logout), title: Text('Sign out'), contentPadding: EdgeInsets.zero),
              ),
            ],
          ),
        ],
      ),
      body: FutureBuilder<_ProfileBundle>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ErrorRetryState(
              title: 'Unable to load your profile',
              message: 'Check your connection and try again.',
              onRetry: () => setState(() => _future = _load()),
            );
          }

          final bundle = snapshot.data!;
          final u = bundle.profile;
          final displayName = (u['display_name'] as String?)?.isNotEmpty == true ? u['display_name'] as String : (u['username'] ?? '');
          final interests = ((u['interests'] as List?) ?? []).cast<String>();
          final bio = u['bio'] as String?;
          final createdAt = u['created_at'] != null ? DateTime.tryParse(u['created_at']) : null;
          final isProfileBare = (bio?.isEmpty ?? true) && u['profile_photo_url'] == null && interests.isEmpty;

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                ProfileCoverAndIdentity(
                  coverUrl: u['cover_photo_url'] as String?,
                  avatarUrl: u['profile_photo_url'] as String?,
                  displayName: displayName,
                  username: (u['username'] as String?) ?? '',
                  role: (u['role'] as String?) ?? 'user',
                  isVerified: (u['is_verified'] as bool?) ?? false,
                  pronouns: u['pronouns'] as String?,
                  isPrivate: (u['is_private'] as bool?) ?? false,
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isProfileBare) ...[
                        Card(
                          color: const Color(0xFF1D9E75).withValues(alpha: 0.08),
                          child: ListTile(
                            leading: const Icon(Icons.person_add_alt_1, color: Color(0xFF1D9E75)),
                            title: const Text('Complete your profile'),
                            subtitle: const Text('Add a photo, bio, and interests so others can find you'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.push('/edit-profile').then((_) => _refresh()),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (bio != null && bio.isNotEmpty) ...[
                        Text(bio),
                        const SizedBox(height: 10),
                      ],
                      ProfileFactsRow(
                        createdAt: createdAt,
                        location: u['location'] as String?,
                        websiteUrl: u['website_url'] as String?,
                        onTapWebsite: (url) => openExternalLink(context, url),
                      ),
                      if (interests.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [for (final tag in interests) Chip(label: Text(tag), visualDensity: VisualDensity.compact)],
                        ),
                      ],
                      const SizedBox(height: 16),
                      ProfileStatsRow(
                        postCount: bundle.postCount,
                        followerCount: bundle.followerCount,
                        followingCount: bundle.followingCount,
                        onTapFollowers: () => showUserListSheet(context, title: 'Followers', loader: () => ProfileRepository().followersList(uid)),
                        onTapFollowing: () => showUserListSheet(context, title: 'Following', loader: () => ProfileRepository().followingList(uid)),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => context.push('/edit-profile').then((_) => _refresh()),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Edit Profile'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.bookmark_outline),
                        title: const Text('Bookmarks'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/bookmarks'),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.notifications_outlined),
                        title: const Text('Notifications'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/notifications'),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.payments_outlined),
                        title: const Text('Monetization'),
                        subtitle: const Text('Earn from ads on your posts'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/monetization'),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.star_outline),
                        title: const Text('Close Friends'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/close-friends'),
                      ),
                      if ((u['role'] as String?) == 'admin' || (u['role'] as String?) == 'moderator')
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.shield_outlined),
                          title: const Text('Moderation'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push('/admin'),
                        ),
                      const SizedBox(height: 20),
                      Text('Posts', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: ProfilePostsGrid(
                    posts: bundle.posts,
                    pinnedPostId: u['pinned_post_id'] as String?,
                    isOwnProfile: true,
                    onTogglePin: (post, pin) async {
                      try {
                        await ProfileRepository().setPinnedPost(uid, pin ? post.id : null);
                        await _refresh();
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update pin: $e')));
                        }
                      }
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ProfileBundle {
  const _ProfileBundle({
    required this.profile,
    required this.followerCount,
    required this.followingCount,
    required this.postCount,
    required this.posts,
  });

  final Map<String, dynamic> profile;
  final int followerCount;
  final int followingCount;
  final int postCount;
  final List<PostModel> posts;
}
