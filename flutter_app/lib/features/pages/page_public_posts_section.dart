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

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _pagePosts = const [];
  List<Map<String, dynamic>> _visitorPosts = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final results = await Future.wait([
        _pageRepo.listPagePosts(widget.pageId, status: 'published'),
        _visitorRepo.listVisitorPosts(widget.pageId),
      ]);
      if (!mounted) return;
      setState(() {
        _pagePosts = List<Map<String, dynamic>>.from(results[0] as List);
        _visitorPosts = List<Map<String, dynamic>>.from(results[1] as List);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load Page posts.';
        _loading = false;
      });
    }
  }

  DateTime _dateOf(Map<String, dynamic> post) {
    final raw = post['published_at'] ?? post['created_at'];
    return DateTime.tryParse(raw?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: PageTokens.spaceLg),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: PageTokens.spaceMd),
        child: Column(
          children: [
            Text(_error!),
            TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Retry')),
          ],
        ),
      );
    }

    final combined = <Map<String, dynamic>>[
      ..._pagePosts.map((post) => {...post, '_isPagePost': true}),
      ..._visitorPosts.map((post) => {...post, '_isPagePost': false}),
    ]..sort((a, b) => _dateOf(b).compareTo(_dateOf(a)));

    if (combined.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: PageTokens.spaceLg),
        child: Center(child: Text('No posts yet.')),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: PageTokens.spaceLg),
        Text('Posts', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: PageTokens.spaceSm),
        ...combined.map((post) => Padding(
          padding: const EdgeInsets.only(bottom: PageTokens.spaceMd),
          child: post['_isPagePost'] == true
              ? _PageAuthoredPostCard(post: post, page: widget.page)
              : PageVisitorPostCard(post: post, page: widget.page),
        )),
        Align(
          alignment: Alignment.center,
          child: TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh, size: 18), label: const Text('Refresh posts')),
        ),
      ],
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
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          ProfileAvatar(url: page['logo_url']?.toString(), radius: 20),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(pageName, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(created?.toString() ?? '', style: Theme.of(context).textTheme.bodySmall),
          ])),
          const Icon(Icons.verified_outlined, size: 18),
        ]),
        if (content.isNotEmpty) ...[
          const SizedBox(height: PageTokens.spaceMd),
          Text(content, style: Theme.of(context).textTheme.bodyLarge),
        ],
        if (media.isNotEmpty) ...[
          const SizedBox(height: PageTokens.spaceMd),
          PageMediaGallery(items: media),
        ],
      ]),
    );
  }
}
