import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase_client.dart';
import '../../shared/models/models.dart';
import '../data/repositories.dart';

/// Lists the current user's bookmarked posts. Reuses [FeedRepository.getPost]
/// per bookmark rather than adding a new repository method/RPC.
class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key});

  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  late Future<List<PostModel>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadBookmarks();
  }

  Future<List<PostModel>> _loadBookmarks() async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) return [];

    final rows = await SupabaseConfig.client
        .from('bookmarks')
        .select('post_id')
        .eq('user_id', uid)
        .order('created_at', ascending: false);
    final postIds = (rows as List).map((e) => e['post_id'].toString()).toList();

    final repo = FeedRepository();
    final posts = <PostModel>[];
    for (final id in postIds) {
      try {
        posts.add(await repo.getPost(id));
      } catch (_) {
        // Post was removed/deleted since being bookmarked; skip it.
      }
    }
    return posts;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bookmarks')),
      body: FutureBuilder<List<PostModel>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final posts = snapshot.data!;
          if (posts.isEmpty) {
            return const Center(child: Text('No bookmarks yet.'));
          }
          return ListView.builder(
            itemCount: posts.length,
            itemBuilder: (context, index) {
              final p = posts[index];
              return ListTile(
                leading: p.thumbnailUrl != null
                    ? CircleAvatar(backgroundImage: NetworkImage(p.thumbnailUrl!))
                    : const CircleAvatar(child: Icon(Icons.article_outlined)),
                title: Text(p.textContent, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(p.authorUsername ?? ''),
                onTap: () => context.push('/post?id=${p.id}'),
              );
            },
          );
        },
      ),
    );
  }
}
