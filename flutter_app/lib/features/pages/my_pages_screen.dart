import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase_client.dart';
import '../../core/theme/app_theme.dart';
import '../data/repositories.dart';
import 'pages_theme.dart';

/// Entry point for the Page System: pages the current user owns or is on
/// the team of, plus the "Create Page" action. Tapping a draft page reopens
/// the preview screen (Step 3); a published page opens the full public
/// Page Profile (Step 6).
class MyPagesScreen extends StatefulWidget {
  const MyPagesScreen({super.key});
  @override
  State<MyPagesScreen> createState() => _MyPagesScreenState();
}

class _MyPagesScreenState extends State<MyPagesScreen> {
  final _repo = PageRepository();
  List<Map<String, dynamic>> pages = [];
  bool loading = true;
  String? err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) {
      setState(() => loading = false);
      return;
    }
    try {
      final rows = await _repo.listMyPages(uid);
      if (mounted) {
        setState(() {
          pages = rows;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          err = 'Could not load your pages. $e';
          loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Pages', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.explore_outlined),
            tooltip: 'Discover pages',
            onPressed: () => context.push('/discover-pages'),
          ),
          IconButton(
            icon: const Icon(Icons.storefront_outlined),
            tooltip: 'Pages you follow',
            onPressed: () => context.push('/followed-pages'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/create-page'),
        backgroundColor: AppColors.brandTeal,
        foregroundColor: AppColors.onBrandTeal,
        icon: const Icon(Icons.add),
        label: const Text('Create Page'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : err != null
              ? Center(child: Text(err!, style: const TextStyle(color: Colors.red)))
              : pages.isEmpty
                  ? _EmptyState(onCreate: () => context.push('/create-page'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(PageTokens.spaceLg),
                        itemCount: pages.length,
                        separatorBuilder: (_, __) => const SizedBox(height: PageTokens.spaceSm),
                        itemBuilder: (_, i) => _PageRow(page: pages[i]),
                      ),
                    ),
    );
  }
}

class _PageRow extends StatelessWidget {
  const _PageRow({required this.page});
  final Map<String, dynamic> page;

  @override
  Widget build(BuildContext context) {
    final status = page['status'] as String;
    final logoUrl = page['logo_url'] as String?;
    return Material(
      color: PageColors.surfaceCard(context),
      borderRadius: BorderRadius.circular(PageTokens.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(PageTokens.radiusMd),
        onTap: () => context.push(status == 'published' ? '/page-profile?id=${page['id']}' : '/page-preview?id=${page['id']}'),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PageTokens.radiusMd),
            border: Border.all(color: PageColors.border(context)),
          ),
          padding: const EdgeInsets.all(PageTokens.spaceMd),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (status == 'published' ? Colors.green : (status == 'suspended' ? Colors.red : Colors.amber)).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(PageTokens.radiusPill),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: status == 'published' ? Colors.green : (status == 'suspended' ? Colors.red : Colors.amber[800]),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(PageTokens.spaceXl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.storefront_outlined, size: 56, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: PageTokens.spaceMd),
              const Text('No pages yet', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: PageTokens.spaceSm),
              Text(
                'Create a Page for your business, organization, or brand.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: PageTokens.spaceLg),
              FilledButton(
                onPressed: onCreate,
                style: FilledButton.styleFrom(backgroundColor: AppColors.brandTeal, foregroundColor: AppColors.onBrandTeal),
                child: const Text('Create Page'),
              ),
            ],
          ),
        ),
      );
}
