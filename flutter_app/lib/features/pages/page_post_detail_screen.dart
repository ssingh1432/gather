import 'package:flutter/material.dart';

import '../data/repositories.dart';
import '../../shared/models/models.dart';
import 'page_owner_post_home_card.dart';

class PagePostDetailScreen extends StatefulWidget {
  const PagePostDetailScreen({super.key, required this.pageId, required this.postId});
  final String pageId;
  final String postId;
  @override State<PagePostDetailScreen> createState() => _PagePostDetailScreenState();
}

class _PagePostDetailScreenState extends State<PagePostDetailScreen> {
  final _repo = PageRepository();
  bool _loading = true;
  String? _error;
  PostModel? _post;
  Map<String, dynamic>? _page;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final page = await _repo.getPage(widget.pageId);
      final posts = await _repo.listPagePosts(widget.pageId, status: 'published');
      final raw = posts.cast<Map<String, dynamic>?>().firstWhere((p) => p?['id']?.toString() == widget.postId, orElse: () => null);
      if (raw == null) throw StateError('Post not found.');
      if (!mounted) return;
      setState(() { _page = page; _post = _toModel(raw, page); _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'This Page post is no longer available.'; });
    }
  }

  PostModel _toModel(Map<String, dynamic> raw, Map<String, dynamic> page) {
    final media = <PostMediaItem>[];
    final rawMedia = raw['media'];
    if (rawMedia is List) {
      for (final item in rawMedia) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        final url = (m['url'] ?? m['media_url'])?.toString();
        if (url == null || url.isEmpty) continue;
        final parsed = PostMediaItem.fromMap({'media_url': url, 'media_type': m['type'] ?? m['media_type'] ?? raw['post_type'] ?? 'image', if (m['thumbnail_url'] != null) 'thumbnail_url': m['thumbnail_url']});
        if (parsed != null) media.add(parsed);
      }
    }
    return PostModel(
      id: raw['id'].toString(),
      authorId: raw['author_id']?.toString() ?? '',
      authorUsername: page['name']?.toString(),
      authorAvatarUrl: page['logo_url']?.toString(),
      textContent: raw['content']?.toString() ?? '',
      createdAt: DateTime.tryParse((raw['published_at'] ?? raw['created_at'])?.toString() ?? '') ?? DateTime.now(),
      mediaItems: media,
      imageUrl: media.isEmpty ? null : media.first.mediaUrl,
      mediaType: media.isEmpty ? null : media.first.mediaType,
      contentType: 'page_owner',
      visibility: 'public',
    );
  }

  @override
  Widget build(BuildContext context) {
    final post = _post;
    final page = _page;
    return Scaffold(
      appBar: AppBar(title: Text(page?['name']?.toString() ?? 'Page post')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
              : post == null || page == null
                  ? const SizedBox.shrink()
                  : ListView(padding: EdgeInsets.zero, children: [PageOwnerPostHomeCard(post: post, pageId: widget.pageId, pageName: page['name']?.toString() ?? 'Page')]),
    );
  }
}
