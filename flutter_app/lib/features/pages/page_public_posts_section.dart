import 'package:flutter/material.dart';

import '../data/repositories.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/reusables.dart';
import 'page_owner_post_home_card.dart';
import 'page_visitor_post_card.dart';
import 'page_visitor_post_repository.dart';
import 'pages_theme.dart';

class PagePublicPostsSection extends StatefulWidget {
  const PagePublicPostsSection({super.key, required this.pageId, required this.page});
  final String pageId;
  final Map<String, dynamic> page;
  @override State<PagePublicPostsSection> createState() => _PagePublicPostsSectionState();
}

class _PagePublicPostsSectionState extends State<PagePublicPostsSection> {
  final _pageRepo = PageRepository();
  final _visitorRepo = PageVisitorPostRepository();
  bool _pageLoading = true;
  bool _visitorLoading = true;
  String? _pageError;
  String? _visitorError;
  List<Map<String, dynamic>> _pagePosts = const [];
  List<Map<String, dynamic>> _visitorPosts = const [];

  @override
  void initState() { super.initState(); _loadPagePosts(); _loadVisitorPosts(); }

  Future<void> _loadPagePosts() async {
    try {
      final posts = await _pageRepo.listPagePosts(widget.pageId, status: 'published');
      if (!mounted) return;
      setState(() { _pagePosts = posts; _pageLoading = false; _pageError = null; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _pageLoading = false; _pageError = 'Could not load Page posts.'; });
    }
  }

  Future<void> _loadVisitorPosts() async {
    try {
      final posts = await _visitorRepo.listVisitorPosts(widget.pageId);
      if (!mounted) return;
      setState(() { _visitorPosts = posts; _visitorLoading = false; _visitorError = null; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _visitorLoading = false; _visitorError = 'Could not load visitor posts.'; });
    }
  }

  Future<void> _refreshAll() async => Future.wait([_loadPagePosts(), _loadVisitorPosts()]);

  DateTime _dateOf(Map<String, dynamic> post) => DateTime.tryParse((post['published_at'] ?? post['created_at'])?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);

  PostModel _pagePostModel(Map<String, dynamic> raw) {
    final mediaRaw = raw['media'];
    final media = <PostMediaItem>[];
    if (mediaRaw is List) {
      for (final item in mediaRaw) {
        if (item is Map) {
          final m = Map<String, dynamic>.from(item);
          final url = (m['url'] ?? m['media_url'])?.toString();
          if (url != null && url.isNotEmpty) {
            final normalized = {'media_url': url, 'media_type': m['type'] ?? m['media_type'] ?? raw['post_type'] ?? 'image', if (m['thumbnail_url'] != null) 'thumbnail_url': m['thumbnail_url']};
            final parsed = PostMediaItem.fromMap(normalized);
            if (parsed != null) media.add(parsed);
          }
        }
      }
    }
    final createdRaw = raw['published_at'] ?? raw['created_at'];
    return PostModel(
      id: raw['id'].toString(),
      authorId: raw['author_id']?.toString() ?? '',
      authorUsername: widget.page['name']?.toString(),
      authorAvatarUrl: widget.page['logo_url']?.toString(),
      textContent: raw['content']?.toString() ?? '',
      createdAt: DateTime.tryParse(createdRaw?.toString() ?? '') ?? DateTime.now(),
      mediaItems: media,
      imageUrl: media.isEmpty ? null : media.first.mediaUrl,
      mediaType: media.isEmpty ? null : media.first.mediaType,
      contentType: 'page_owner',
      visibility: 'public',
      isPinned: raw['pinned'] == true,
      editedAt: DateTime.tryParse(raw['edited_at']?.toString() ?? ''),
      editCount: (raw['version'] is num ? (raw['version'] as num).toInt() - 1 : 0).clamp(0, 1000000),
    );
  }

  @override
  Widget build(BuildContext context) {
    final combined = <Map<String, dynamic>>[
      ..._pagePosts.map((p) => {...p, '_isPagePost': true}),
      ..._visitorPosts.map((p) => {...p, '_isPagePost': false}),
    ]..sort((a, b) => _dateOf(b).compareTo(_dateOf(a)));
    final initialLoading = combined.isEmpty && _pageLoading && _visitorLoading;
    if (initialLoading) return const Padding(padding: EdgeInsets.symmetric(vertical: PageTokens.spaceMd), child: Center(child: CircularProgressIndicator(strokeWidth: 2)));

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: PageTokens.spaceLg),
      Row(children: [
        Expanded(child: Text('Posts', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
        if (_pageLoading || _visitorLoading) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        IconButton(onPressed: _refreshAll, tooltip: 'Refresh posts', icon: const Icon(Icons.refresh)),
      ]),
      if (_pageError != null && _pagePosts.isEmpty) _PostSourceError(message: _pageError!, onRetry: _loadPagePosts),
      if (_visitorError != null && _visitorPosts.isEmpty) _PostSourceError(message: _visitorError!, onRetry: _loadVisitorPosts),
      if (combined.isEmpty && !_pageLoading && !_visitorLoading && _pageError == null && _visitorError == null)
        const Padding(padding: EdgeInsets.symmetric(vertical: PageTokens.spaceLg), child: Center(child: Text('No posts yet.'))),
      ...combined.map((post) => Padding(
        padding: const EdgeInsets.only(bottom: PageTokens.spaceMd),
        child: post['_isPagePost'] == true
            ? PageOwnerPostHomeCard(post: _pagePostModel(post), pageId: widget.pageId, pageName: widget.page['name']?.toString() ?? 'Page')
            : PageVisitorPostCard(post: post, page: widget.page),
      )),
    ]);
  }
}

class _PostSourceError extends StatelessWidget {
  const _PostSourceError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: PageTokens.spaceSm),
    child: Row(children: [Expanded(child: Text(message)), TextButton(onPressed: onRetry, child: const Text('Retry'))]),
  );
}
