import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase_client.dart';
import '../data/repositories.dart';
import '../../shared/widgets/reusables.dart';
import 'pages_theme.dart';

/// Page Discovery (Step 12 of the Professional Page System): typo-tolerant
/// search, category browse, nearby (text-based today — see migration 085's
/// note on `page_nearby_geo` for the future-ready geo path), suggested (for
/// signed-in users, based on existing follows), trending (recent follower
/// growth), and a verified directory. Mirrors CommunitiesScreen's
/// sort-chip + search-field pattern for a familiar, consistent feel.
class PageDiscoveryScreen extends StatefulWidget {
  const PageDiscoveryScreen({super.key});
  @override
  State<PageDiscoveryScreen> createState() => _PageDiscoveryScreenState();
}

enum _DiscoverySort { popular, trending, verified, nearby }

class _PageDiscoveryScreenState extends State<PageDiscoveryScreen> {
  final _repo = PageRepository();
  final _q = TextEditingController();
  late Future<List<Map<String, dynamic>>> _future = _load();
  Future<List<Map<String, dynamic>>>? _suggestedFuture;
  List<Map<String, dynamic>> _categories = const [];
  String? _selectedCategoryId;
  _DiscoverySort _sort = _DiscoverySort.popular;
  final Map<String, bool> _following = {};

  @override
  void initState() {
    super.initState();
    _repo.discoverCategories().then((rows) {
      if (mounted) setState(() => _categories = rows);
    }).catchError((_) {});
    if (SupabaseConfig.currentUserId != null) {
      _suggestedFuture = _repo.suggestedPages(limit: 10).catchError((_) => <Map<String, dynamic>>[]);
    }
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final query = _q.text.trim();
    List<Map<String, dynamic>> data;
    switch (_sort) {
      case _DiscoverySort.trending:
        data = await _repo.trendingPages();
      case _DiscoverySort.verified:
        data = await _repo.verifiedPages();
      case _DiscoverySort.nearby:
        // No lat/lng UI yet (see migration 085's `page_nearby_geo` note),
        // and no reliable per-user location signal in this build, so
        // "Nearby" defaults to Gather's primary market for now. Once a
        // profile location or device geolocation is available, swap this
        // for `_repo.nearbyPagesByGeo(lat, lng)`.
        data = await _repo.nearbyPagesByText(country: 'Nepal');
      case _DiscoverySort.popular:
        data = await _repo.searchPages(query: query.isEmpty ? null : query, categoryId: _selectedCategoryId);
    }
    if (_sort != _DiscoverySort.popular && _selectedCategoryId != null) {
      data = data.where((p) => p['category_id'] == _selectedCategoryId).toList();
    }
    if (mounted) {
      final uid = SupabaseConfig.currentUserId;
      if (uid != null) {
        for (final p in data) {
          final state = await _repo.getFollowState(p['id'] as String).catchError((_) => null);
          _following[p['id'] as String] = state != null;
        }
      }
    }
    return data;
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _toggleFollow(String pageId) async {
    final was = _following[pageId] ?? false;
    setState(() => _following[pageId] = !was);
    try {
      if (was) {
        await _repo.unfollowPage(pageId);
      } else {
        await _repo.followPage(pageId);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _following[pageId] = was);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update follow: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Discover Pages', style: TextStyle(fontWeight: FontWeight.w700)), bottom: appBarBottomBorder(context)),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: ListView(
          padding: const EdgeInsets.all(PageTokens.spaceLg),
          children: [
            TextField(
              controller: _q,
              decoration: pageFieldDecoration(context, labelText: 'Search pages', hintText: 'Business, creator, NGO…', prefixIcon: const Icon(Icons.search)),
              onSubmitted: (_) {
                setState(() => _sort = _DiscoverySort.popular);
                _reload();
              },
            ),
            const SizedBox(height: PageTokens.spaceMd),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _sortChip('Popular', _DiscoverySort.popular, Icons.local_fire_department_outlined),
                  _sortChip('Trending', _DiscoverySort.trending, Icons.trending_up),
                  _sortChip('Verified', _DiscoverySort.verified, Icons.verified_outlined),
                  _sortChip('Nearby', _DiscoverySort.nearby, Icons.place_outlined),
                ],
              ),
            ),
            if (_categories.isNotEmpty) ...[
              const SizedBox(height: PageTokens.spaceMd),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _categoryChip(null, 'All'),
                    for (final c in _categories) _categoryChip(c['id'] as String, '${c['name']} (${c['page_count']})'),
                  ],
                ),
              ),
            ],
            if (_suggestedFuture != null) ...[
              const SizedBox(height: PageTokens.spaceLg),
              PageSectionHeader(title: 'Suggested for you'),
              SizedBox(
                height: 168,
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _suggestedFuture,
                  builder: (context, snap) {
                    final items = snap.data ?? const [];
                    if (items.isEmpty) return const SizedBox.shrink();
                    return ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(width: PageTokens.spaceMd),
                      itemBuilder: (context, i) => SizedBox(width: 150, child: _PageResultCard(page: items[i], compact: true)),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: PageTokens.spaceLg),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
                if (snap.hasError) return ErrorRetryState(title: 'Something went wrong', message: '${snap.error}', onRetry: _reload);
                final items = snap.data ?? const [];
                if (items.isEmpty) {
                  return const EmptyState(icon: Icons.storefront_outlined, title: 'No pages found', message: 'Try a different search term, category, or filter.');
                }
                return Column(
                  children: [
                    for (final p in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: PageTokens.spaceMd),
                        child: _PageResultCard(
                          page: p,
                          following: _following[p['id']] ?? false,
                          onToggleFollow: () => _toggleFollow(p['id'] as String),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _sortChip(String label, _DiscoverySort value, IconData icon) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          avatar: Icon(icon, size: 16),
          selected: _sort == value,
          onSelected: (_) {
            setState(() => _sort = value);
            _reload();
          },
        ),
      );

  Widget _categoryChip(String? id, String label) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: _selectedCategoryId == id,
          onSelected: (_) {
            setState(() => _selectedCategoryId = id);
            _reload();
          },
        ),
      );
}

class _PageResultCard extends StatelessWidget {
  const _PageResultCard({required this.page, this.following = false, this.onToggleFollow, this.compact = false});
  final Map<String, dynamic> page;
  final bool following;
  final VoidCallback? onToggleFollow;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final logoUrl = page['logo_url'] as String?;
    final verified = page['verification_status'] == 'verified';
    final rating = (page['rating_avg'] as num?)?.toDouble();
    final followers = page['follower_count'] as int? ?? 0;

    return InkWell(
      onTap: () => context.push('/page-profile?id=${page['id']}'),
      borderRadius: BorderRadius.circular(PageTokens.radiusMd),
      child: Container(
        padding: const EdgeInsets.all(PageTokens.spaceMd),
        decoration: BoxDecoration(
          color: PageColors.surfaceCard(context),
          borderRadius: BorderRadius.circular(PageTokens.radiusMd),
          border: Border.all(color: PageColors.border(context)),
          boxShadow: PageTokens.subtleShadow(context),
        ),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _logo(context, logoUrl, size: 44),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: Text(page['name'] as String? ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
                      if (verified) const Icon(Icons.verified, size: 14, color: AppColors.brandTeal),
                    ],
                  ),
                  Text('$followers followers', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              )
            : Row(
                children: [
                  _logo(context, logoUrl, size: 52),
                  const SizedBox(width: PageTokens.spaceMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(child: Text(page['name'] as String? ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
                            if (verified) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.verified, size: 15, color: AppColors.brandTeal)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            PageStatChip(icon: Icons.people_alt_outlined, label: '$followers'),
                            if (rating != null && rating > 0) PageStatChip(icon: Icons.star_rounded, label: rating.toStringAsFixed(1), color: Colors.amber.shade700),
                            if (page['distance_km'] != null) PageStatChip(icon: Icons.place_outlined, label: '${(page['distance_km'] as num).toStringAsFixed(1)} km'),
                            if (page['growth'] != null && (page['growth'] as num) > 0) PageStatChip(icon: Icons.trending_up, label: '+${page['growth']}', color: AppColors.brandTeal),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (onToggleFollow != null)
                    OutlinedButton(
                      onPressed: onToggleFollow,
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 34), padding: const EdgeInsets.symmetric(horizontal: 12)),
                      child: Text(following ? 'Following' : 'Follow'),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _logo(BuildContext context, String? url, {required double size}) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: PageColors.surfaceMuted(context),
          image: url != null ? DecorationImage(image: NetworkImage(url), fit: BoxFit.cover) : null,
        ),
        child: url == null ? const Icon(Icons.storefront, size: 20) : null,
      );
}
