import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase_client.dart';
import '../../features/data/repositories.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/reusables.dart';

class CommunityDetailScreen extends StatefulWidget {
  const CommunityDetailScreen({super.key, this.communityId = ''});
  final String communityId;

  @override
  State<CommunityDetailScreen> createState() => _CommunityDetailScreenState();
}

class _CommunityDetailScreenState extends State<CommunityDetailScreen> {
  final repo = FeedRepository();
  final postCtrl = TextEditingController();

  Set<String> liked = <String>{};
  Set<String> bookmarked = <String>{};
  List<PostModel> _posts = const [];
  bool _loading = true;
  bool _posting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uid = SupabaseConfig.client.auth.currentUser?.id;
      final posts = await repo.communityFeed(widget.communityId);
      _posts = posts;
      final ids = posts.map((e) => e.id).toList();
      if (uid != null) {
        liked = await repo.likedPostIds(uid, ids);
        bookmarked = await repo.bookmarkedPostIds(uid, ids);
      } else {
        liked = <String>{};
        bookmarked = <String>{};
      }
    } catch (e) {
      _error = 'Failed to load community posts. Please try again.\n$e';
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Community')),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(controller: postCtrl, decoration: const InputDecoration(labelText: 'Create post text')),
          ),
          ElevatedButton(
            onPressed: _posting
                ? null
                : () async {
                    final uid = SupabaseConfig.client.auth.currentUser?.id;
                    if (uid == null) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please log in to create a post.')));
                      }
                      return;
                    }
                    if (postCtrl.text.trim().isEmpty) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Post text cannot be empty.')));
                      }
                      return;
                    }
                    setState(() => _posting = true);
                    try {
                      await PostRepository().createPost({'author_id': uid, 'community_id': widget.communityId, 'text_content': postCtrl.text.trim()});
                      postCtrl.clear();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Post published.')));
                      }
                      await _load();
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to publish post: $e')));
                      }
                    } finally {
                      if (mounted) setState(() => _posting = false);
                    }
                  },
            child: _posting
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Post'),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text('Error: $_error'))
                    : _posts.isEmpty
                        ? const Center(child: Text('No posts'))
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView(
                              children: _posts
                                  .map((p) => PostCard(
                                        post: p,
                                        liked: liked.contains(p.id),
                                        bookmarked: bookmarked.contains(p.id),
                                        onLike: () async {
                                          final uid = SupabaseConfig.client.auth.currentUser?.id;
                                          if (uid == null) return;
                                          if (liked.contains(p.id)) {
                                            await repo.unlikePost(p.id, uid);
                                          } else {
                                            await repo.likePost(p.id, uid);
                                          }
                                          await _load();
                                        },
                                        onComment: () => context.push('/post?id=${p.id}'),
                                        onBookmark: () async {
                                          final uid = SupabaseConfig.client.auth.currentUser?.id;
                                          if (uid == null) return;
                                          if (bookmarked.contains(p.id)) {
                                            await repo.unbookmarkPost(p.id, uid);
                                          } else {
                                            await repo.bookmarkPost(p.id, uid);
                                          }
                                          await _load();
                                        },
                                      ))
                                  .toList(),
                            ),
                          ),
          )
        ]),
      );

}
