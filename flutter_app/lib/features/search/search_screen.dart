import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase_client.dart';
import '../../shared/models/models.dart';
import '../data/repositories.dart';

/// Step 17 — Search Integration. Text/hashtag/@mention/author/community/
/// media-type/date-range filters plus sort, backed by the search_posts
/// RPC (migration 037). Communities are still found via a separate
/// name search — they aren't posts, so they don't go through the same
/// filter set.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.initialQuery});
  final String? initialQuery;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

const _mediaTypeOptions = {null: 'Any media', 'image': 'Photos', 'video': 'Videos', 'audio': 'Audio', 'document': 'Documents'};
const _sortOptions = {'recent': 'Most recent', 'popular': 'Most liked'};

class _SearchScreenState extends State<SearchScreen> with SingleTickerProviderStateMixin {
  final _query = TextEditingController();
  final _authorCtrl = TextEditingController();
  final _searchRepo = SearchRepository();
  final _communityRepository = CommunityRepository();
  late final TabController _tabs;

  bool _loading = false;
  List<Map<String, dynamic>> _communities = [];
  List<PostModel> _posts = [];
  List<Map<String, dynamic>> _trending = [];
  bool _loadingTrending = true;

  // Filters
  String? _mediaType;
  String _sort = 'recent';
  DateTimeRange? _dateRange;
  bool _filtersExpanded = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _loadTrending();
    final initial = widget.initialQuery;
    if (initial != null && initial.isNotEmpty) {
      _query.text = initial;
      _search();
    }
  }

  Future<void> _loadTrending() async {
    try {
      final rows = await SupabaseConfig.client.rpc('trending_hashtags', params: {'days_back': 7, 'result_limit': 15});
      if (mounted) setState(() => _trending = (rows as List).cast<Map<String, dynamic>>());
    } catch (_) {
      // Trending is a nice-to-have on the empty state; search itself still works without it.
    } finally {
      if (mounted) setState(() => _loadingTrending = false);
    }
  }

  @override
  void dispose() {
    _query.dispose();
    _authorCtrl.dispose();
    _tabs.dispose();
    super.dispose();
  }

  bool get _hasActiveFilters => _mediaType != null || _authorCtrl.text.trim().isNotEmpty || _dateRange != null || _sort != 'recent';

  Future<void> _search() async {
    final raw = _query.text.trim();
    final author = _authorCtrl.text.trim();
    if (raw.isEmpty && author.isEmpty && !_hasActiveFilters) {
      setState(() {
        _communities = [];
        _posts = [];
      });
      return;
    }

    setState(() => _loading = true);
    try {
      String? textQuery = raw;
      String? tag;
      String? mention;
      if (raw.startsWith('#') && raw.length > 1) {
        tag = raw.substring(1);
        textQuery = null;
      } else if (raw.startsWith('@') && raw.length > 1) {
        mention = raw.substring(1);
        textQuery = null;
      }

      final results = await Future.wait([
        raw.isEmpty ? Future.value(<Map<String, dynamic>>[]) : _communityRepository.listCommunities(raw),
        _searchRepo.searchPosts(
          query: textQuery == null || textQuery.isEmpty ? null : textQuery,
          tag: tag,
          mentionedUsername: mention,
          authorUsername: author.isEmpty ? null : author,
          mediaType: _mediaType,
          dateFrom: _dateRange?.start,
          dateTo: _dateRange?.end,
          sort: _sort,
        ),
      ]);

      if (mounted) {
        setState(() {
          _communities = results[0] as List<Map<String, dynamic>>;
          _posts = results[1] as List<PostModel>;
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

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: _dateRange,
    );
    if (picked != null) {
      setState(() => _dateRange = picked);
      _search();
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
            hintText: 'Search posts, #tags, @mentions',
            border: InputBorder.none,
          ),
          onSubmitted: (_) => _search(),
          textInputAction: TextInputAction.search,
        ),
        actions: [
          IconButton(
            icon: Icon(_filtersExpanded ? Icons.filter_alt : Icons.filter_alt_outlined, color: _hasActiveFilters ? Theme.of(context).colorScheme.primary : null),
            tooltip: 'Filters',
            onPressed: () => setState(() => _filtersExpanded = !_filtersExpanded),
          ),
          IconButton(icon: const Icon(Icons.search), onPressed: _search),
        ],
        bottom: TabBar(controller: _tabs, tabs: const [Tab(text: 'Posts'), Tab(text: 'Communities')]),
      ),
      body: Column(
        children: [
          if (_filtersExpanded) _buildFilterPanel(context),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabs,
                    children: [
                      _buildPostsTab(),
                      _buildCommunitiesTab(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterPanel(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _authorCtrl,
            decoration: const InputDecoration(labelText: 'From author (username)', isDense: true),
            onSubmitted: (_) => _search(),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              DropdownButton<String?>(
                value: _mediaType,
                hint: const Text('Any media'),
                items: [for (final e in _mediaTypeOptions.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) {
                  setState(() => _mediaType = v);
                  _search();
                },
              ),
              DropdownButton<String>(
                value: _sort,
                items: [for (final e in _sortOptions.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _sort = v);
                  _search();
                },
              ),
              ActionChip(
                avatar: const Icon(Icons.date_range_outlined, size: 18),
                label: Text(_dateRange == null ? 'Date range' : '${_fmt(_dateRange!.start)} – ${_fmt(_dateRange!.end)}'),
                onPressed: _pickDateRange,
              ),
              if (_dateRange != null)
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    setState(() => _dateRange = null);
                    _search();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime d) => '${d.month}/${d.day}/${d.year}';

  Widget _buildPostsTab() {
    if (_posts.isEmpty) {
      return _query.text.isEmpty && !_hasActiveFilters
          ? _buildTrending()
          : const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No results found.')));
    }
    return ListView.builder(
      itemCount: _posts.length,
      itemBuilder: (context, i) {
        final p = _posts[i];
        return ListTile(
          leading: Icon(p.isVideo
              ? Icons.videocam_outlined
              : p.isAudio
                  ? Icons.audiotrack_outlined
                  : p.isDocument
                      ? Icons.description_outlined
                      : Icons.article_outlined),
          title: Text(p.textContent, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text('${p.authorUsername ?? ''} · ${p.likeCount} likes'),
          onTap: () => context.push('/post?id=${p.id}'),
        );
      },
    );
  }

  Widget _buildCommunitiesTab() {
    if (_communities.isEmpty) {
      return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No communities found.')));
    }
    return ListView.builder(
      itemCount: _communities.length,
      itemBuilder: (context, i) {
        final c = _communities[i];
        return ListTile(
          leading: const Icon(Icons.groups_outlined),
          title: Text(c['name']?.toString() ?? ''),
          onTap: () => context.push('/community?id=${c['id']}'),
        );
      },
    );
  }

  Widget _buildTrending() {
    if (_loadingTrending || _trending.isEmpty) return const SizedBox.shrink();
    return ListView(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('Trending hashtags', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in _trending)
                ActionChip(
                  label: Text('#${t['tag']} · ${t['post_count']}'),
                  onPressed: () {
                    _query.text = '#${t['tag']}';
                    _search();
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}
