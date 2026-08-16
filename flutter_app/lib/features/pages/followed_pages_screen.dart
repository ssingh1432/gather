import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/repositories.dart';
import '../../shared/widgets/reusables.dart';
import 'pages_theme.dart';

/// Pages the current user follows (Step 8 of the brief: Favorite +
/// per-follow notification preference). Favorites are pinned to the top.
class FollowedPagesScreen extends StatefulWidget {
  const FollowedPagesScreen({super.key});

  @override
  State<FollowedPagesScreen> createState() => _FollowedPagesScreenState();
}

class _FollowedPagesScreenState extends State<FollowedPagesScreen> {
  final _repo = PageRepository();
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
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
      final rows = await _repo.listFollowedPages();
      if (mounted) setState(() { _rows = rows; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = 'Could not load followed pages. $e'; _loading = false; });
    }
  }

  Future<void> _toggleFavorite(Map<String, dynamic> row) async {
    final page = row['pages'] as Map<String, dynamic>;
    final wasFavorite = row['favorite'] as bool? ?? false;
    setState(() => row['favorite'] = !wasFavorite);
    try {
      await _repo.setPageFavorite(page['id'] as String, !wasFavorite);
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() => row['favorite'] = wasFavorite);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update favorite: $e')));
      }
    }
  }

  Future<void> _toggleNotify(Map<String, dynamic> row) async {
    final page = row['pages'] as Map<String, dynamic>;
    final wasNotify = row['notify'] as bool? ?? true;
    setState(() => row['notify'] = !wasNotify);
    try {
      await _repo.setPageFollowNotify(page['id'] as String, !wasNotify);
    } catch (e) {
      if (mounted) {
        setState(() => row['notify'] = wasNotify);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update notifications: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Followed Pages', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.explore_outlined),
            tooltip: 'Discover pages',
            onPressed: () => context.push('/discover-pages'),
          ),
        ],
      ),
      body: _loading
          ? const FeedSkeletonList()
          : _error != null
              ? ErrorRetryState(title: 'Unable to load', message: _error!, onRetry: _load)
              : _rows.isEmpty
                  ? const EmptyState(
                      icon: Icons.storefront_outlined,
                      title: 'Not following any pages yet',
                      message: 'Pages you follow will show up here.',
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(PageTokens.spaceLg),
                        itemCount: _rows.length,
                        separatorBuilder: (_, __) => const SizedBox(height: PageTokens.spaceSm),
                        itemBuilder: (_, i) => _FollowedPageRow(
                          row: _rows[i],
                          onToggleFavorite: () => _toggleFavorite(_rows[i]),
                          onToggleNotify: () => _toggleNotify(_rows[i]),
                        ),
                      ),
                    ),
    );
  }
}

class _FollowedPageRow extends StatelessWidget {
  const _FollowedPageRow({required this.row, required this.onToggleFavorite, required this.onToggleNotify});
  final Map<String, dynamic> row;
  final VoidCallback onToggleFavorite;
  final VoidCallback onToggleNotify;

  @override
  Widget build(BuildContext context) {
    final page = row['pages'] as Map<String, dynamic>;
    final favorite = row['favorite'] as bool? ?? false;
    final notify = row['notify'] as bool? ?? true;
    final logoUrl = page['logo_url'] as String?;
    return Material(
      color: PageColors.surfaceCard(context),
      borderRadius: BorderRadius.circular(PageTokens.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(PageTokens.radiusMd),
        onTap: () => context.push('/page-profile?id=${page['id']}'),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PageTokens.radiusMd),
            border: Border.all(color: PageColors.border(context)),
          ),
          padding: const EdgeInsets.all(PageTokens.spaceMd),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: PageColors.surfaceMuted(context),
                backgroundImage: logoUrl != null ? NetworkImage(logoUrl) : null,
                child: logoUrl == null ? const Icon(Icons.storefront) : null,
              ),
              const SizedBox(width: PageTokens.spaceMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(page['name'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('@${page['username']}', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(notify ? Icons.notifications_active_outlined : Icons.notifications_off_outlined),
                color: notify ? AppColors.brandTeal : Theme.of(context).colorScheme.onSurfaceVariant,
                tooltip: notify ? 'Notifications on' : 'Notifications off',
                onPressed: onToggleNotify,
              ),
              IconButton(
                icon: Icon(favorite ? Icons.star : Icons.star_border),
                color: favorite ? Colors.amber[700] : Theme.of(context).colorScheme.onSurfaceVariant,
                tooltip: favorite ? 'Unfavorite' : 'Favorite',
                onPressed: onToggleFavorite,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
