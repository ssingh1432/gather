import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase_client.dart';
import '../../features/data/repositories.dart';
import '../models/models.dart';
import '../providers/app_providers.dart';
import 'reusables.dart';

/// "Suggested Pages" — a horizontally-scrollable row of published pages
/// the user doesn't already follow, shown in the home feed a few rows
/// below "Suggested groups" so the two breaks don't land back-to-back.
///
/// This exists because Pages had no ambient presence anywhere in the
/// app's primary navigation — unlike Communities, which is a first-class
/// bottom-nav tab. Rather than restructuring navigation (a much bigger,
/// higher-risk change touching the app's shell), this gives Pages the
/// same lightweight, low-risk discovery surface Communities already gets
/// on Home, following the exact same pattern as [SuggestedCommunities].
///
/// Only ever shows `status == 'published'` pages — enforced both by
/// [PageRepository.suggestedPagesForFeed]'s explicit filter and by RLS
/// underneath it, which already hides drafts from non-team-members.
class SuggestedPages extends ConsumerWidget {
  const SuggestedPages({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (SupabaseConfig.currentUserId == null) return const SizedBox.shrink();

    final suggestedAsync = ref.watch(suggestedPagesProvider);

    return suggestedAsync.when(
      loading: () => const _SuggestedPagesSkeleton(),
      error: (error, stackTrace) => const SizedBox.shrink(),
      data: (pages) {
        final dismissed = ref.watch(dismissedSuggestedPagesProvider);
        final followed = ref.watch(followedSuggestedPagesProvider);
        final visible = pages.where((p) => !dismissed.contains(p.id) && !followed.contains(p.id)).toList();
        if (visible.isEmpty) return const SizedBox.shrink();
        return _SuggestedPagesSection(pages: visible);
      },
    );
  }
}

class _SuggestedPagesSection extends ConsumerWidget {
  const _SuggestedPagesSection({required this.pages});
  final List<SuggestedPage> pages;

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
                Expanded(child: Text('Suggested Pages', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
                IconButton(
                  tooltip: 'Hide',
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () {
                    final ids = pages.map((p) => p.id);
                    ref.read(dismissedSuggestedPagesProvider.notifier).update((prev) => {...prev, ...ids});
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
              itemCount: pages.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) => _PageCard(page: pages[index]),
            ),
          ),
        ],
      ),
    );
  }
}

class _PageCard extends ConsumerStatefulWidget {
  const _PageCard({required this.page});
  final SuggestedPage page;

  @override
  ConsumerState<_PageCard> createState() => _PageCardState();
}

class _PageCardState extends ConsumerState<_PageCard> {
  bool _following = false;

  Future<void> _follow() async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) return;
    setState(() => _following = true);
    try {
      await PageRepository().followPage(widget.page.id);
      ref.read(followedSuggestedPagesProvider.notifier).update((prev) => {...prev, widget.page.id});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Following ${widget.page.name}.')));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _following = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not follow. Please try again.')));
      }
    }
  }

  void _notInterested() {
    ref.read(dismissedSuggestedPagesProvider.notifier).update((prev) => {...prev, widget.page.id});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final page = widget.page;
    return SizedBox(
      width: 168,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/page-profile?id=${page.id}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 16 / 10,
                child: page.logoUrl != null
                    ? Image.network(page.logoUrl!, fit: BoxFit.cover)
                    : Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: Icon(Icons.storefront_outlined, size: 32, color: theme.colorScheme.outline),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      page.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, height: 1.2),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${page.followerCount} followers',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                    ),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: SizedBox(
                          height: 30,
                          child: FilledButton(
                            onPressed: _following ? null : _follow,
                            style: FilledButton.styleFrom(padding: EdgeInsets.zero, textStyle: theme.textTheme.labelSmall),
                            child: Text(_following ? '…' : 'Follow'),
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

class _SuggestedPagesSkeleton extends StatelessWidget {
  const _SuggestedPagesSkeleton();

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
