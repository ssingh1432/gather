import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase_client.dart';
import '../../core/theme/app_theme.dart';
import '../../features/data/repositories.dart';
import '../../shared/widgets/auth_redirects.dart';
import '../../shared/widgets/reusables.dart';
import 'community_theme.dart';
import 'widgets/community_card.dart';

class CommunitiesScreen extends StatefulWidget {
  const CommunitiesScreen({super.key});
  @override
  State<CommunitiesScreen> createState() => _C();
}

enum _DiscoverySort { popular, trending, recentlyActive }

class _C extends State<CommunitiesScreen> {
  final repo = CommunityRepository();
  final q = TextEditingController();
  late Future<List<Map<String, dynamic>>> f = _load();
  Future<List<Map<String, dynamic>>>? _suggestedFuture;
  Map<String, bool> joined = {};
  List<Map<String, dynamic>> _categoryOptions = const [];
  String? _selectedCategoryId;
  String? _selectedTagId;
  String? _selectedTagName;
  _DiscoverySort _sort = _DiscoverySort.popular;
  bool _verifiedOnly = false;

  @override
  void initState() {
    super.initState();
    repo.listCategoryOptions().then((options) {
      if (mounted) setState(() => _categoryOptions = options);
    });
    final uid = SupabaseConfig.currentUserId;
    if (uid != null) {
      _suggestedFuture = repo.suggestedCommunities(uid).catchError((_) => <Map<String, dynamic>>[]);
    }
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final query = q.text.trim();
    List<Map<String, dynamic>> data;

    if (_sort == _DiscoverySort.trending) {
      data = await repo.trendingCommunities();
    } else if (_sort == _DiscoverySort.recentlyActive) {
      data = await repo.recentlyActiveCommunities();
    } else if (query.isNotEmpty && _selectedCategoryId == null && _selectedTagId == null) {
      // Typo-tolerant search (pg_trgm) only applies cleanly with no other
      // filters active — category/tag filtering still goes through the
      // plain substring path below, which supports combining filters.
      data = await repo.searchCommunities(query);
    } else {
      data = await repo.listCommunitiesFiltered(query: query, categoryId: _selectedCategoryId, tagId: _selectedTagId, verifiedOnly: _verifiedOnly);
    }

    // Trending/recently-active/search results don't accept every filter as
    // a server-side param, so apply the remaining ones client-side — these
    // lists are small enough that this is cheap and keeps the UI consistent
    // no matter which sort mode is active.
    if (_sort != _DiscoverySort.popular || (query.isNotEmpty && _selectedCategoryId == null && _selectedTagId == null)) {
      if (_selectedCategoryId != null) data = data.where((c) => c['category_id'] == _selectedCategoryId).toList();
      if (_verifiedOnly) data = data.where((c) => c['is_verified'] == true).toList();
    }

    final uid = SupabaseConfig.currentUserId;
    if (uid != null && data.isNotEmpty) {
      joined = await repo.joinedStates(data.map((e) => e['id'].toString()).toList(), uid);
    } else {
      joined = {};
    }
    return data;
  }

  void _selectCategory(String? categoryId) {
    setState(() {
      _selectedCategoryId = categoryId;
      f = _load();
    });
  }

  void _selectSort(_DiscoverySort sort) {
    setState(() {
      _sort = sort;
      f = _load();
    });
  }

  void _toggleVerifiedOnly() {
    setState(() {
      _verifiedOnly = !_verifiedOnly;
      f = _load();
    });
  }

  void _clearTagFilter() => setState(() {
        _selectedTagId = null;
        _selectedTagName = null;
        f = _load();
      });

  Future<void> _openTagFilterDialog() async {
    final controller = TextEditingController();
    List<Map<String, dynamic>> results = const [];
    final picked = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Filter by tag'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(hintText: 'Search tags', border: OutlineInputBorder()),
                  onChanged: (query) async {
                    final r = await repo.searchTagOptions(query);
                    setDialogState(() => results = r);
                  },
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: ListView(
                    shrinkWrap: true,
                    children: [for (final t in results) ListTile(title: Text(t['name'] as String), onTap: () => Navigator.pop(ctx, t))],
                  ),
                ),
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel'))],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedTagId = picked['id'] as String;
      _selectedTagName = picked['name'] as String;
      f = _load();
    });
  }

  void _retry() => setState(() => f = _load());

  Future<void> _handleJoinLeave(Map<String, dynamic> community) async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) {
      redirectToLogin(context, redirect: '/communities', message: 'Please log in or create an account to join a community.');
      return;
    }
    final id = community['id'].toString();
    final isMember = joined[id] ?? false;
    try {
      if (isMember) {
        await repo.leaveCommunity(id, uid);
      } else {
        final result = await repo.requestJoin(id);
        if (result == 'requested' && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Join request sent. An owner or admin will review it.')),
          );
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update membership: $e')));
      return;
    }
    _retry();
  }

  Future<void> _redeemCodeDialog() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter invite code'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: 'e.g. 73SX83G2', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Join')),
        ],
      ),
    );
    if (code == null || code.trim().isEmpty || !mounted) return;

    try {
      final result = await repo.redeemInviteCode(code.trim());
      final communityId = result['community_id']?.toString();
      if (!mounted) return;
      final joined = result['result'] == 'joined';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(joined ? 'Joined!' : 'You\'re already a member of that community.')),
      );
      if (communityId != null) context.push('/community?id=$communityId');
      _retry();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not redeem that code: $e')));
    }
  }

  @override
  void dispose() {
    q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Communities', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.key_outlined),
            tooltip: 'Have an invite code?',
            onPressed: () {
              if (SupabaseConfig.currentUserId == null) {
                redirectToLogin(context, redirect: '/communities', message: 'Please log in or create an account to redeem an invite.');
                return;
              }
              _redeemCodeDialog();
            },
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Create community',
            onPressed: () {
              if (SupabaseConfig.currentUserId == null) {
                redirectToLogin(context, redirect: '/create-community', message: 'Please log in or create an account to create a community.');
                return;
              }
              context.push('/create-community');
            },
          ),
        ],
      ),
      body: Column(children: [
        if (_suggestedFuture != null)
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _suggestedFuture,
            builder: (context, snapshot) {
              final suggestions = snapshot.data ?? const [];
              if (suggestions.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CommunitySectionHeader(title: 'Suggested for you'),
                  SizedBox(
                    height: 106,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: CommunityTokens.spaceMd),
                      itemCount: suggestions.length,
                      itemBuilder: (_, i) {
                        final c = suggestions[i];
                        final iconUrl = c['image_url'] as String?;
                        final hasImage = iconUrl != null && iconUrl.isNotEmpty;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(CommunityTokens.radiusMd),
                            onTap: () => context.push('/community?id=${c['id']}'),
                            child: SizedBox(
                              width: 76,
                              child: Column(
                                children: [
                                  Container(
                                    width: 60,
                                    height: 60,
                                    padding: const EdgeInsets.all(2.5),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: LinearGradient(
                                        colors: [AppColors.brandTeal, AppColors.brandTealLight],
                                      ),
                                    ),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: CommunityColors.surfaceCard(context),
                                      ),
                                      padding: const EdgeInsets.all(2),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: hasImage ? null : CommunityColors.bannerFallbackGradient(context),
                                          image: hasImage ? DecorationImage(image: NetworkImage(iconUrl), fit: BoxFit.cover) : null,
                                        ),
                                        child: hasImage ? null : const Icon(Icons.groups, color: Colors.white, size: 20),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    c['name'] as String? ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            CommunityTokens.spaceLg,
            CommunityTokens.spaceMd,
            CommunityTokens.spaceLg,
            CommunityTokens.spaceSm,
          ),
          child: TextField(
            controller: q,
            decoration: InputDecoration(
              hintText: 'Search communities',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward, size: 18), onPressed: _retry),
              filled: true,
              fillColor: CommunityColors.surfaceMuted(context),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(CommunityTokens.radiusPill),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(CommunityTokens.radiusPill),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(CommunityTokens.radiusPill),
                borderSide: const BorderSide(color: AppColors.brandTeal, width: 1.5),
              ),
            ),
            onSubmitted: (_) => _retry(),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: CommunityTokens.spaceMd),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: const Text('Popular'),
                  selected: _sort == _DiscoverySort.popular,
                  onSelected: (_) => _selectSort(_DiscoverySort.popular),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CommunityTokens.radiusPill)),
                  selectedColor: AppColors.brandTealLight,
                  labelStyle: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _sort == _DiscoverySort.popular ? AppColors.onBrandTeal : null,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  avatar: const Icon(Icons.local_fire_department_outlined, size: 16),
                  label: const Text('Trending'),
                  selected: _sort == _DiscoverySort.trending,
                  onSelected: (_) => _selectSort(_DiscoverySort.trending),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CommunityTokens.radiusPill)),
                  selectedColor: AppColors.brandTealLight,
                  labelStyle: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _sort == _DiscoverySort.trending ? AppColors.onBrandTeal : null,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  avatar: const Icon(Icons.bolt_outlined, size: 16),
                  label: const Text('Recently active'),
                  selected: _sort == _DiscoverySort.recentlyActive,
                  onSelected: (_) => _selectSort(_DiscoverySort.recentlyActive),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CommunityTokens.radiusPill)),
                  selectedColor: AppColors.brandTealLight,
                  labelStyle: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _sort == _DiscoverySort.recentlyActive ? AppColors.onBrandTeal : null,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: FilterChip(
                  avatar: const Icon(Icons.verified, size: 16),
                  label: const Text('Verified only'),
                  selected: _verifiedOnly,
                  onSelected: (_) => _toggleVerifiedOnly(),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CommunityTokens.radiusPill)),
                  selectedColor: AppColors.brandTealLight,
                  labelStyle: TextStyle(fontWeight: FontWeight.w600, color: _verifiedOnly ? AppColors.onBrandTeal : null),
                ),
              ),
            ],
          ),
        ),
        if (_categoryOptions.isNotEmpty)
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: CommunityTokens.spaceMd),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: const Text('All'),
                    selected: _selectedCategoryId == null,
                    onSelected: (_) => _selectCategory(null),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CommunityTokens.radiusPill)),
                  ),
                ),
                for (final cat in _categoryOptions)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(cat['name'] as String),
                      selected: _selectedCategoryId == cat['id'],
                      onSelected: (_) => _selectCategory(cat['id'] as String),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CommunityTokens.radiusPill)),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: CommunityTokens.spaceXs),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: CommunityTokens.spaceMd),
          child: Row(
            children: [
              if (_selectedTagId == null)
                TextButton.icon(
                  onPressed: _openTagFilterDialog,
                  icon: const Icon(Icons.sell_outlined, size: 18),
                  label: const Text('Filter by tag'),
                  style: TextButton.styleFrom(foregroundColor: AppColors.brandTeal),
                )
              else
                Chip(
                  label: Text('#$_selectedTagName'),
                  onDeleted: _clearTagFilter,
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CommunityTokens.radiusPill)),
                  backgroundColor: AppColors.brandTealLight.withValues(alpha: 0.4),
                ),
            ],
          ),
        ),
        const Divider(height: CommunityTokens.spaceLg),
        Expanded(
          child: FutureBuilder(
            future: f,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const FeedSkeletonList(itemCount: 4);
              }
              if (snapshot.hasError) {
                return ErrorRetryState(title: 'Unable to load communities', message: 'Network failure. Check your connection and try again.', onRetry: _retry);
              }
              final data = snapshot.data ?? const <Map<String, dynamic>>[];
              if (data.isEmpty) {
                return EmptyState(
                  icon: Icons.groups_outlined,
                  title: 'No communities',
                  message: q.text.trim().isEmpty ? 'Be the first to create a community.' : 'Try a different search or create it yourself.',
                  action: ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Create community'),
                    onPressed: () {
                      if (SupabaseConfig.currentUserId == null) {
                        redirectToLogin(context, redirect: '/create-community', message: 'Please log in or create an account to create a community.');
                        return;
                      }
                      context.push('/create-community');
                    },
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: () async => _retry(),
                child: ListView(
                  padding: const EdgeInsets.only(top: CommunityTokens.spaceXs, bottom: CommunityTokens.spaceXl),
                  children: data
                      .map((e) => CommunityCard(
                            community: e,
                            joined: joined[e['id'].toString()] ?? false,
                            onOpen: () => context.push('/community?id=${e['id']}'),
                            onJoinLeave: () => _handleJoinLeave(e),
                          ))
                      .toList(),
                ),
              );
            },
          ),
        )
      ]),
    );
  }
}
