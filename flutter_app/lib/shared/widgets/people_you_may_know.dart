import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase_client.dart';
import '../models/models.dart';
import '../providers/app_providers.dart';
import 'auth_redirects.dart';
import 'reusables.dart';

/// "You may know these people" — a horizontally-scrollable row of
/// recommended-user cards shown near the top of the home feed. Each card
/// lets the person send a friend request without leaving the feed.
class PeopleYouMayKnow extends ConsumerWidget {
  const PeopleYouMayKnow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Logged-out visitors have nothing to be recommended, so stay out of
    // their way entirely rather than showing a login-gated skeleton.
    if (SupabaseConfig.currentUserId == null) return const SizedBox.shrink();

    final recommendedAsync = ref.watch(recommendedUsersProvider);

    return recommendedAsync.when(
      loading: () => const _PeopleYouMayKnowSkeleton(),
      error: (error, stackTrace) => _ErrorRow(onRetry: () => ref.invalidate(recommendedUsersProvider)),
      data: (users) {
        if (users.isEmpty) return const SizedBox.shrink();
        return _PeopleYouMayKnowSection(users: users);
      },
    );
  }
}

class _PeopleYouMayKnowSection extends StatelessWidget {
  const _PeopleYouMayKnowSection({required this.users});
  final List<RecommendedUser> users;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text('You may know these people', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
          SizedBox(
            height: 168,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: users.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) => _PersonCard(user: users[index]),
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonCard extends ConsumerWidget {
  const _PersonCard({required this.user});
  final RecommendedUser user;

  Future<void> _sendRequest(BuildContext context, WidgetRef ref) async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) {
      redirectToLogin(context, redirect: '/', message: 'Please log in or create an account to add friends.');
      return;
    }

    // Optimistically flip to "Requested" so the tap feels instant; roll
    // back and surface an error if the request actually fails.
    ref.read(sentFriendRequestsProvider.notifier).update((ids) => {...ids, user.id});
    try {
      await ref.read(profileRepositoryProvider).sendFriendRequest(user.id, uid);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Friend request sent to ${user.username}.')));
    } catch (_) {
      ref.read(sentFriendRequestsProvider.notifier).update((ids) => {...ids}..remove(user.id));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not send request. Please try again.')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final requested = ref.watch(sentFriendRequestsProvider).contains(user.id);

    return SizedBox(
      width: 128,
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => context.push('/user?id=${user.id}'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ProfileAvatar(url: user.avatarUrl, radius: 30),
                const SizedBox(height: 10),
                Text(
                  user.username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 32,
                  child: requested
                      ? OutlinedButton(
                          onPressed: null,
                          style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, textStyle: theme.textTheme.labelSmall),
                          child: const Text('Requested'),
                        )
                      : FilledButton(
                          onPressed: () => _sendRequest(context, ref),
                          style: FilledButton.styleFrom(padding: EdgeInsets.zero, textStyle: theme.textTheme.labelSmall),
                          child: const Text('Add Friend'),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PeopleYouMayKnowSkeleton extends StatelessWidget {
  const _PeopleYouMayKnowSkeleton();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: SkeletonBox(height: 16, width: 200),
            ),
            SizedBox(
              height: 168,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: 4,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) => const SizedBox(
                  width: 128,
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SkeletonBox(height: 60, width: 60),
                          SizedBox(height: 10),
                          SkeletonBox(height: 12, width: 80),
                          SizedBox(height: 10),
                          SkeletonBox(height: 28),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}

class _ErrorRow extends StatelessWidget {
  const _ErrorRow({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                "Couldn't load people you may know.",
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
}
