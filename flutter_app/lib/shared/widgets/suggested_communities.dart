import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase_client.dart';
import '../../features/data/repositories.dart';
import '../models/models.dart';
import '../providers/app_providers.dart';
import 'reusables.dart';

/// "Suggested for you" — a horizontally-scrollable row of public,
/// not-already-joined communities shown in the home feed, the same way
/// [PeopleYouMayKnow] recommends people. Deliberately built as its own
/// section (not a reuse of CommunitiesScreen's list-row CommunityCard,
/// which is a different, denser layout meant for a dedicated discovery
/// screen) so it reads as a feed break the way Facebook's own "Suggested
/// for you" groups row does.
///
/// Only ever shows visibility == 'public' communities — enforced both by
/// [CommunityRepository.suggestedCommunitiesForFeed]'s explicit filter and
/// by RLS underneath it, which already hides secret communities from
/// non-members.
class SuggestedCommunities extends ConsumerWidget {
  const SuggestedCommunities({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (SupabaseConfig.currentUserId == null) return const SizedBox.shrink();

    final suggestedAsync = ref.watch(suggestedCommunitiesProvider);

    return suggestedAsync.when(
      loading: () => const _SuggestedCommunitiesSkeleton(),
      error: (error, stackTrace) => const SizedBox.shrink(),
      data: (communities) {
        final dismissed = ref.watch(dismissedSuggestedCommunitiesProvider);
        final joined = ref.watch(joinedSuggestedCommunitiesProvider);
        final visible = communities.where((c) => !dismissed.contains(c.id) && !joined.contains(c.id)).toList();
        if (visible.isEmpty) return const SizedBox.shrink();
        return _SuggestedCommunitiesSection(communities: visible);
      },
    );
  }
}

class _SuggestedCommunitiesSection extends ConsumerWidget {
  const _SuggestedCommunitiesSection({required this.communities});
  final List<SuggestedCommunity> communities;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Expanded(child: Text('Suggested groups', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
                IconButton(
                  tooltip: 'Hide',
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () {
                    final ids = communities.map((c) => c.id);
                    ref.read(dismissedSuggestedCommunitiesProvider.notifier).update((prev) => {...prev, ...ids});
                  },
                ),
              ],
            ),
          ),
          SizedBox(
            height: 214,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: communities.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) => _CommunityCard(community: communities[index]),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommunityCard extends ConsumerStatefulWidget {
  const _CommunityCard({required this.community});
  final SuggestedCommunity community;

  @override
  ConsumerState<_CommunityCard> createState() => _CommunityCardState();
}

class _CommunityCardState extends ConsumerState<_CommunityCard> {
  bool _joining = false;

  Future<void> _join() async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) return;
    setState(() => _joining = true);
    try {
      await CommunityRepository().joinCommunity(widget.community.id, uid);
      ref.read(joinedSuggestedCommunitiesProvider.notifier).update((prev) => {...prev, widget.community.id});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Joined ${widget.community.name}.')));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _joining = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not join. Please try again.')));
      }
    }
  }

  void _notInterested() {
    ref.read(dismissedSuggestedCommunitiesProvider.notifier).update((prev) => {...prev, widget.community.id});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final community = widget.community;
    return SizedBox(
      width: 168,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/community?id=${community.id}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 16 / 10,
                child: community.imageUrl != null
                    ? Image.network(community.imageUrl!, fit: BoxFit.cover)
                    : Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: Icon(Icons.groups_outlined, size: 32, color: theme.colorScheme.outline),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      community.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, height: 1.2),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${community.memberCount} members',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                    ),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: SizedBox(
                          height: 30,
                          child: FilledButton(
                            onPressed: _joining ? null : _join,
                            style: FilledButton.styleFrom(padding: EdgeInsets.zero, textStyle: theme.textTheme.labelSmall),
                            child: Text(_joining ? '…' : 'Join'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        height: 30,
                        child: OutlinedButton(
                          onPressed: _notInterested,
                          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), textStyle: theme.textTheme.labelSmall),
                          child: const Text('Not interested'),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuggestedCommunitiesSkeleton extends StatelessWidget {
  const _SuggestedCommunitiesSkeleton();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: SkeletonBox(height: 16, width: 160),
            ),
            SizedBox(
              height: 214,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: 3,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) => const SizedBox(
                  width: 168,
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SkeletonBox(height: 90),
                          SizedBox(height: 10),
                          SkeletonBox(height: 12, width: 100),
                          SizedBox(height: 8),
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
