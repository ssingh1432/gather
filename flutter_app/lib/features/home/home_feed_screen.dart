import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase_client.dart';
import '../../features/data/repositories.dart';
import '../../shared/providers/app_providers.dart';
import '../../shared/widgets/reusables.dart';

class HomeFeedScreen extends ConsumerStatefulWidget {
  const HomeFeedScreen({super.key});
  @override
  ConsumerState<HomeFeedScreen> createState() => _S();
}

class _S extends ConsumerState<HomeFeedScreen> {
  int page = 0;
  final repo = FeedRepository();
  final liked = <String>{};
  final bookmarked = <String>{};

  @override
  Widget build(BuildContext c) {
    final uid = SupabaseConfig.client.auth.currentUser?.id;
    final feed = ref.watch(homeFeedProvider(page));
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: feed.when(
        data: (posts) => RefreshIndicator(
          onRefresh: () async => ref.refresh(homeFeedProvider(page)),
          child: ListView(
            children: [
              if (posts.isEmpty) const ListTile(title: Text('No posts yet')),
              ...posts.map(
                (p) => PostCard(
                  post: p,
                  liked: liked.contains(p.id),
                  bookmarked: bookmarked.contains(p.id),
                  onLike: () async {
                    if (uid == null) return;
                    if (liked.contains(p.id)) {
                      await repo.unlikePost(p.id, uid);
                      liked.remove(p.id);
                    } else {
                      await repo.likePost(p.id, uid);
                      liked.add(p.id);
                    }
                    setState(() {});
                  },
                  onComment: () => context.push('/post?id=${p.id}'),
                  onBookmark: () async {
                    if (uid == null) return;
                    if (bookmarked.contains(p.id)) {
                      await repo.unbookmarkPost(p.id, uid);
                      bookmarked.remove(p.id);
                    } else {
                      await repo.bookmarkPost(p.id, uid);
                      bookmarked.add(p.id);
                    }
                    setState(() {});
                  },
                ),
              ),
            ],
          ),
        ),
        error: (e, _) => Center(child: Text('Error: $e')),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
