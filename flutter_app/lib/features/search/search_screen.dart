import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase_client.dart';
import '../../shared/models/models.dart';
import '../data/repositories.dart';

/// Searches communities (by name) and posts (by text content). Uses only
/// existing repository/table access — no new RPCs or tables required.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _query = TextEditingController();
  final _communityRepository = CommunityRepository();
  bool _loading = false;
  List<Map<String, dynamic>> _communities = [];
  List<PostModel> _posts = [];

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search(String value) async {
    final q = value.trim();
    if (q.isEmpty) {
      setState(() {
        _communities = [];
        _posts = [];
      });
      return;
    }

    setState(() => _loading = true);
    try {
      final communities = await _communityRepository.listCommunities(q);
      final postRows = await SupabaseConfig.client
          .from('posts')
          .select('*, users!posts_author_id_fkey(username), post_media(media_url)')
          .eq('is_removed', false)
          .ilike('text_content', '%$q%')
          .order('created_at', ascending: false)
          .limit(20);
      final posts = (postRows as List).map((e) => PostModel.fromMap(e)).toList();
      if (mounted) {
        setState(() {
          _communities = communities;
          _posts = posts;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Search failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _query,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search communities and posts',
            border: InputBorder.none,
          ),
          onSubmitted: _search,
          textInputAction: TextInputAction.search,
        ),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: () => _search(_query.text)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                if (_communities.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text('Communities', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  for (final c in _communities)
                    ListTile(
                      leading: const Icon(Icons.groups_outlined),
                      title: Text(c['name']?.toString() ?? ''),
                      onTap: () => context.push('/community?id=${c['id']}'),
                    ),
                ],
                if (_posts.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text('Posts', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  for (final p in _posts)
                    ListTile(
                      leading: const Icon(Icons.article_outlined),
                      title: Text(p.textContent, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(p.authorUsername ?? ''),
                      onTap: () => context.push('/post?id=${p.id}'),
                    ),
                ],
                if (!_loading && _communities.isEmpty && _posts.isEmpty && _query.text.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('No results found.')),
                  ),
              ],
            ),
    );
  }
}
