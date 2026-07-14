import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/supabase_client.dart';
import '../../shared/models/models.dart';
import '../../shared/utils/external_link.dart';
import '../../shared/widgets/auth_redirects.dart';
import '../../shared/widgets/profile_view.dart';
import '../../shared/widgets/reusables.dart';
import '../data/repositories.dart';

/// Someone else's profile — cover/avatar, bio, member-since/location/
/// website, stats, a Follow/Unfollow toggle, and their post grid. Distinct
/// from [ProfileScreen], which is the signed-in person's own tab.
class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key, this.userId = ''});
  final String userId;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  late Future<_OtherProfileBundle> _future;
  bool _followBusy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_OtherProfileBundle> _load() async {
    final profileRepo = ProfileRepository();
    final me = SupabaseConfig.currentUserId;
    final results = await Future.wait([
      profileRepo.loadProfile(widget.userId),
      profileRepo.followers(widget.userId),
      profileRepo.following(widget.userId),
      profileRepo.postCount(widget.userId),
      FeedRepository().postsByUser(widget.userId),
      me == null ? Future.value(false) : profileRepo.isFollowing(widget.userId, me),
      me == null ? Future.value(false) : profileRepo.isBlocked(widget.userId, me),
    ]);
    final profile = results[0] as Map<String, dynamic>?;
    if (profile == null) throw StateError('Profile not found');
    return _OtherProfileBundle(
      profile: profile,
      followerCount: results[1] as int,
      followingCount: results[2] as int,
      postCount: results[3] as int,
      posts: results[4] as List<PostModel>,
      isFollowing: results[5] as bool,
      isBlocked: results[6] as bool,
    );
  }

  Future<void> _refresh() async {
    final next = _load();
    await next;
    if (mounted) setState(() => _future = next);
  }

  Future<void> _toggleFollow(_OtherProfileBundle bundle) async {
    final me = SupabaseConfig.currentUserId;
    if (me == null) {
      redirectToLogin(context, redirect: '/user?id=${widget.userId}', message: 'Please log in or create an account to follow people.');
      return;
    }
    setState(() => _followBusy = true);
    try {
      if (bundle.isFollowing) {
        await ProfileRepository().unfollow(widget.userId, me);
      } else {
        await ProfileRepository().follow(widget.userId, me);
      }
      await _refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not update follow status. Please try again.')));
      }
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  Future<void> _toggleBlock(_OtherProfileBundle bundle) async {
    final me = SupabaseConfig.currentUserId;
    if (me == null) return;

    if (!bundle.isBlocked) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Block @${bundle.profile['username'] ?? 'this user'}?'),
          content: const Text("They won't be able to see your posts or contact you, and you won't see theirs."),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Block'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    try {
      if (bundle.isBlocked) {
        await ProfileRepository().unblock(widget.userId, me);
      } else {
        await ProfileRepository().block(widget.userId, me);
      }
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(bundle.isBlocked ? 'Unblocked.' : 'Blocked.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not update block status. Please try again.')));
      }
    }
  }

  void _openMoreMenu(_OtherProfileBundle bundle) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: const Text('Share profile'),
              onTap: () {
                Navigator.pop(sheetContext);
                Share.share('Check out @${bundle.profile['username'] ?? ''} on Gather: https://eiquoab.xyz/user?id=${widget.userId}');
              },
            ),
            ListTile(
              leading: Icon(bundle.isBlocked ? Icons.block_flipped : Icons.block_outlined),
              title: Text(bundle.isBlocked ? 'Unblock' : 'Block'),
              onTap: () {
                Navigator.pop(sheetContext);
                _toggleBlock(bundle);
              },
            ),
            ListTile(
              leading: Icon(Icons.flag_outlined, color: Theme.of(context).colorScheme.error),
              title: Text('Report user', style: TextStyle(color: Theme.of(context).colorScheme.error)),
              onTap: () {
                Navigator.pop(sheetContext);
                final me = SupabaseConfig.currentUserId;
                if (me == null) {
                  redirectToLogin(context, redirect: '/user?id=${widget.userId}', message: 'Please log in or create an account to report a profile.');
                  return;
                }
                context.push('/report?userId=${widget.userId}');
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = SupabaseConfig.currentUserId;
    final isOwnProfile = me != null && me == widget.userId;

    // Editing your own profile goes through the dedicated tab; visiting
    // /user?id=<yourself> (e.g. tapping your own name somewhere) just sends
    // you there instead of duplicating the whole screen.
    if (isOwnProfile) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/profile');
      });
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: FutureBuilder<_OtherProfileBundle>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ErrorRetryState(
              title: 'Unable to load this profile',
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
                      if (bundle.isBlocked) ...[
                        Card(
                          color: Theme.of(context).colorScheme.errorContainer,
                          child: const Padding(
                            padding: EdgeInsets.all(12),
                            child: Text('You have blocked this person.'),
                          ),
                        ),
                        const SizedBox(height: 12),
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
                        onTapFollowers: () => showUserListSheet(context, title: 'Followers', loader: () => ProfileRepository().followersList(widget.userId)),
                        onTapFollowing: () => showUserListSheet(context, title: 'Following', loader: () => ProfileRepository().followingList(widget.userId)),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _followBusy ? null : () => _toggleFollow(bundle),
                              icon: Icon(bundle.isFollowing ? Icons.how_to_reg : Icons.person_add_alt_1, size: 18),
                              label: Text(_followBusy ? 'Please wait…' : (bundle.isFollowing ? 'Following' : 'Follow')),
                              style: bundle.isFollowing
                                  ? FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest, foregroundColor: Theme.of(context).colorScheme.onSurface)
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.outlined(onPressed: () => _openMoreMenu(bundle), icon: const Icon(Icons.more_horiz)),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text('Posts', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: ((u['is_private'] as bool?) ?? false) && !bundle.isFollowing && u['id'] != SupabaseConfig.currentUserId
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 32),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(Icons.lock_outline, size: 40, color: Colors.grey),
                                SizedBox(height: 8),
                                Text('This account is private', style: TextStyle(fontWeight: FontWeight.w600)),
                                SizedBox(height: 4),
                                Text('Follow to see their posts', style: TextStyle(color: Colors.grey)),
                              ],
                            ),
                          ),
                        )
                      : ProfilePostsGrid(posts: bundle.posts, pinnedPostId: u['pinned_post_id'] as String?),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _OtherProfileBundle {
  const _OtherProfileBundle({
    required this.profile,
    required this.followerCount,
    required this.followingCount,
    required this.postCount,
    required this.posts,
    required this.isFollowing,
    required this.isBlocked,
  });

  final Map<String, dynamic> profile;
  final int followerCount;
  final int followingCount;
  final int postCount;
  final List<PostModel> posts;
  final bool isFollowing;
  final bool isBlocked;
}
