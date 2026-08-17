import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase_client.dart';
import '../data/repositories.dart';
import 'page_manage_screen.dart';
import 'pages_theme.dart';

/// Page hub for the current user: owned/team Pages, discovery, followed
/// Pages, and creation. Published Pages expose explicit View and Manage
/// actions so owners do not have to infer that tapping the Page identity
/// opens the public profile.
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
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(PageTokens.spaceLg),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => context.push('/discover-pages'),
                              icon: const Icon(Icons.explore_outlined),
                              label: const Text('Discover Pages'),
                            ),
                          ),
                          const SizedBox(width: PageTokens.spaceSm),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => context.push('/followed-pages'),
                              icon: const Icon(Icons.bookmark_outline),
                              label: const Text('Following'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: PageTokens.spaceLg),
                      if (pages.isEmpty)
                        _EmptyState(onCreate: () => context.push('/create-page'))
                      else
                        ...pages.map(
                          (page) => Padding(
                            padding: const EdgeInsets.only(bottom: PageTokens.spaceSm),
                            child: _PageRow(page: page),
                          ),
                        ),
                      const SizedBox(height: PageTokens.spaceXxl),
                    ],
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
    final published = status == 'published';

    return Material(
      color: PageColors.surfaceCard(context),
      borderRadius: BorderRadius.circular(PageTokens.radiusMd),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(PageTokens.radiusMd),
          border: Border.all(color: PageColors.border(context)),
        ),
        padding: const EdgeInsets.all(PageTokens.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(PageTokens.radiusSm),
              onTap: () => context.push(
                published
                    ? '/page-profile?id=${page['id']}'
                    : '/page-preview?id=${page['id']}',
              ),
              child: Padding(
                padding: const EdgeInsets.all(2),
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
                          Text(
                            page['name'] as String,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            '@${page['username']}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: (published
                                ? Colors.green
                                : (status == 'suspended' ? Colors.red : Colors.amber))
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(PageTokens.radiusPill),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: published
                              ? Colors.green
                              : (status == 'suspended' ? Colors.red : Colors.amber[800]),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: PageTokens.spaceMd),
            if (published)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => context.push('/page-profile?id=${page['id']}'),
                      icon: const Icon(Icons.visibility_outlined),
                      label: const Text('View Page'),
                    ),
                  ),
                  const SizedBox(width: PageTokens.spaceSm),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PageManageScreen(pageId: page['id'] as String),
                        ),
                      ),
                      icon: const Icon(Icons.dashboard_customize_outlined),
                      label: const Text('Manage Page'),
                    ),
                  ),
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/page-preview?id=${page['id']}'),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Continue setup'),
                ),
              ),
          ],
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
              Icon(
                Icons.storefront_outlined,
                size: 56,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: PageTokens.spaceMd),
              const Text(
                'No pages yet',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: PageTokens.spaceSm),
              Text(
                'Create a Page for your business, organization, or brand.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: PageTokens.spaceLg),
              FilledButton(
                onPressed: onCreate,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brandTeal,
                  foregroundColor: AppColors.onBrandTeal,
                ),
                child: const Text('Create Page'),
              ),
            ],
          ),
        ),
      );
}
