import 'package:flutter/material.dart';

import '../data/repositories.dart';
import '../../shared/widgets/reusables.dart';
import 'page_media_gallery.dart';
import 'page_visitor_post_card.dart';
import 'page_visitor_post_repository.dart';
import 'pages_theme.dart';

class PagePublicPostsSection extends StatefulWidget {
  const PagePublicPostsSection({super.key, required this.pageId, required this.page});

  final String pageId;
  final Map<String, dynamic> page;

  @override
  State<PagePublicPostsSection> createState() => _PagePublicPostsSectionState();
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
  void initState() {
    super.initState();
    _loadPagePosts();
    _loadVisitorPosts();
  }

  Future<void> _loadPagePosts() async {
    try {
      final posts = await _pageRepo.listPagePosts(widget.pageId, status: 'published');
      if (!mounted) return;
      setState(() {
        _pagePosts = posts;
        _pageLoading = false;
        _pageError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pageLoading = false;
        _pageError = 'Could not load Page posts.';
      });
    }
  }

  Future<void> _loadVisitorPosts() async {
    try {
      final posts = await _visitorRepo.listVisitorPosts(widget.pageId);
      if (!mounted) return;
      setState(() {
        _visitorPosts = posts;
        _visitorLoading = false;
        _visitorError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _visitorLoading = false;
        _visitorError = 'Could not load visitor posts.';
      });
    }
  }

  Future<void> _refreshAll() async {
    await Future.wait([_loadPagePosts(), _loadVisitorPosts()]);
  }

  DateTime _dateOf(Map<String, dynamic> post) {
    final raw = post['published_at'] ?? post['created_at'];
    return DateTime.tryParse(raw?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  @override
  Widget build(BuildContext context) {
    final combined = <Map<String, dynamic>>[
      ..._pagePosts.map((post) => {...post, '_isPagePost': true}),
      ..._visitorPosts.map((post) => {...post, '_isPagePost': false}),
    ]..sort((a, b) => _dateOf(b).compareTo(_dateOf(a)));

    final initialLoading = combined.isEmpty && _pageLoading && _visitorLoading;
    if (initialLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: PageTokens.spaceMd),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: PageTokens.spaceLg),
        Row(
          children: [
            Expanded(
              child: Text(
                'Posts',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            if (_pageLoading || _visitorLoading)
              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            IconButton(onPressed: _refreshAll, tooltip: 'Refresh posts', icon: const Icon(Icons.refresh)),
          ],
        ),
        if (_pageError != null && _pagePosts.isEmpty)
          _PostSourceError(message: _pageError!, onRetry: _loadPagePosts),
        if (_visitorError != null && _visitorPosts.isEmpty)
          _PostSourceError(message: _visitorError!, onRetry: _loadVisitorPosts),
        if (combined.isEmpty && !_pageLoading && !_visitorLoading && _pageError == null && _visitorError == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: PageTokens.spaceLg),
            child: Center(child: Text('No posts yet.')),
          ),
        ...combined.map((post) => Padding(
          padding: const EdgeInsets.only(bottom: PageTokens.spaceMd),
          child: post['_isPagePost'] == true
              ? _PageAuthoredPostCard(post: post, page: widget.page)
              : PageVisitorPostCard(post: post, page: widget.page),
        )),
      ],
    );
  }
}

class _PostSourceError extends StatelessWidget {
  const _PostSourceError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: PageTokens.spaceSm),
      child: Row(
        children: [
          Expanded(child: Text(message)),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _PageAuthoredPostCard extends StatelessWidget {
  const _PageAuthoredPostCard({required this.post, required this.page});

  final Map<String, dynamic> post;
  final Map<String, dynamic> page;

  List<Map<String, dynamic>> _media() {
    final raw = post['media'];
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final media = _media();
    final content = post['content']?.toString().trim() ?? '';
    final created = post['published_at'] ?? post['created_at'];
    final pageName = page['name']?.toString() ?? 'Page';

    return Container(
      decoration: BoxDecoration(
        color: PageColors.surfaceCard(context),
        borderRadius: BorderRadius.circular(PageTokens.radiusMd),
        border: Border.all(color: PageColors.border(context)),
      ),
      padding: const EdgeInsets.all(PageTokens.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ProfileAvatar(url: page['logo_url']?.toString(), radius: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pageName, style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text(created?.toString() ?? '', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              const Icon(Icons.verified_outlined, size: 18),
            ],
          ),
          if (content.isNotEmpty) ...[
            const SizedBox(height: PageTokens.spaceMd),
            Text(content, style: Theme.of(context).textTheme.bodyLarge),
          ],
          if (media.isNotEmpty) ...[
            const SizedBox(height: PageTokens.spaceMd),
            PageMediaGallery(items: media),
          ],
        ],
      ),
    );
  }
}
