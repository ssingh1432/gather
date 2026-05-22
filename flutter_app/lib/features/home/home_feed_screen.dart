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

  @override
  void initState() {
    super.initState();
    _guardBannedUser();
  }

  Future<void> _guardBannedUser() async {
    final uid = SupabaseConfig.client.auth.currentUser?.id;
    if (uid == null) return;
    final user = await SupabaseConfig.client.from('users').select('status').eq('id', uid).maybeSingle();
    if (user?['status'] == 'banned' && mounted) {
      await SupabaseConfig.client.auth.signOut();
      if (mounted) context.go('/login');
    }
  }

  final repo = FeedRepository();
  Set<String> liked = <String>{};
  Set<String> bookmarked = <String>{};
  List<String> _lastLoadedIds = const [];

  Future<void> _refreshStates(List<String> ids, String uid) async {
    liked = await repo.likedPostIds(uid, ids);
    bookmarked = await repo.bookmarkedPostIds(uid, ids);
    setState(() {});
  }

  @override
  Widget build(BuildContext c) {
    final uid = SupabaseConfig.client.auth.currentUser?.id;
    final feed = ref.watch(homeFeedProvider(page));
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: feed.when(
        data: (posts) {
          final ids = posts.map((e) => e.id).toList();
          if (uid != null && ids.join(',') != _lastLoadedIds.join(',')) {
            _lastLoadedIds = ids;
            WidgetsBinding.instance.addPostFrameCallback((_) => _refreshStates(ids, uid));
          }
          return RefreshIndicator(
            onRefresh: () async => ref.refresh(homeFeedProvider(page)),
            child: ListView(
              children: [
                if (posts.isEmpty) const ListTile(title: Text('No posts yet')),
                ...posts.map((p) => PostCard(post: p, liked: liked.contains(p.id), bookmarked: bookmarked.contains(p.id), onLike: () async {
                      if (uid == null) return;
                      if (liked.contains(p.id)) {
                        await repo.unlikePost(p.id, uid);
                      } else {
                        await repo.likePost(p.id, uid);
                      }
                      await _refreshStates(posts.map((e) => e.id).toList(), uid);
                    }, onComment: () => context.push('/post?id=${p.id}'), onBookmark: () async {
                      if (uid == null) return;
                      if (bookmarked.contains(p.id)) {
                        await repo.unbookmarkPost(p.id, uid);
                      } else {
                        await repo.bookmarkPost(p.id, uid);
                      }
                      await _refreshStates(posts.map((e) => e.id).toList(), uid);
                    })),
              ],
            ),
          );
        },
        error: (e, _) => Center(child: Text('Error: $e')),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
