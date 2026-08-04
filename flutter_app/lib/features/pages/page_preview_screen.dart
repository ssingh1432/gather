import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../data/repositories.dart';
import 'pages_theme.dart';

/// Shows the page exactly as the public will see it once published — this
/// *is* the "Preview Before Publishing" requirement from Step 3, reusing
/// the page's real draft/published lifecycle rather than a separate preview
/// data path. Reached right after creation, or by revisiting a draft page
/// from "My Pages".
class PagePreviewScreen extends StatefulWidget {
  const PagePreviewScreen({super.key, required this.pageId});
  final String pageId;

  @override
  State<PagePreviewScreen> createState() => _PagePreviewScreenState();
}

class _PagePreviewScreenState extends State<PagePreviewScreen> {
  final _repo = PageRepository();
  Map<String, dynamic>? page;
  bool loading = true;
  bool publishing = false;
  String? err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await _repo.getPage(widget.pageId);
      if (mounted) setState(() {
        page = p;
        loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        err = 'Could not load page. $e';
        loading = false;
      });
    }
  }

  Future<void> _publish() async {
    setState(() => publishing = true);
    try {
      await _repo.updatePage(widget.pageId, {'status': 'published'});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Page published!')));
      context.pushReplacement('/my-pages');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not publish. $e')));
      }
    } finally {
      if (mounted) setState(() => publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Preview', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          TextButton(
            onPressed: () => context.go('/my-pages'),
            child: const Text('Save as draft'),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : err != null
              ? Center(child: Text(err!, style: const TextStyle(color: Colors.red)))
              : page == null
                  ? const Center(child: Text('Page not found'))
                  : ListView(
                      padding: const EdgeInsets.only(bottom: PageTokens.spaceXxl),
                      children: [
                        Container(
                          margin: const EdgeInsets.all(PageTokens.spaceLg),
                          padding: const EdgeInsets.symmetric(horizontal: PageTokens.spaceMd, vertical: PageTokens.spaceSm),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(PageTokens.radiusMd),
                            border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            children: const [
                              Icon(Icons.visibility_outlined, size: 18, color: Colors.amber),
                              SizedBox(width: 8),
                              Expanded(child: Text('This is a preview. Only you and your team can see this page until you publish it.')),
                            ],
                          ),
                        ),
                        _CoverAndLogo(page: page!),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: PageTokens.spaceLg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 40), // clears the logo that overlaps from _CoverAndLogo
                              Text(page!['name'] as String, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                              Text('@${page!['username']}', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                              const SizedBox(height: PageTokens.spaceSm),
                              Wrap(
                                spacing: 8,
                                children: [
                                  PageStatChip(icon: Icons.category_outlined, label: kPageTypes[page!['page_type']] ?? page!['page_type'] as String),
                                  if (page!['location'] != null) PageStatChip(icon: Icons.place_outlined, label: page!['location'] as String),
                                ],
                              ),
                              if ((page!['description'] as String?)?.isNotEmpty ?? false) ...[
                                const SizedBox(height: PageTokens.spaceMd),
                                Text(page!['description'] as String),
                              ],
                              const SizedBox(height: PageTokens.spaceLg),
                              const Divider(),
                              const SizedBox(height: PageTokens.spaceSm),
                              if (page!['website'] != null) _InfoRow(icon: Icons.link, text: page!['website'] as String),
                              if (page!['phone'] != null) _InfoRow(icon: Icons.phone_outlined, text: page!['phone'] as String),
                              if (page!['email'] != null) _InfoRow(icon: Icons.email_outlined, text: page!['email'] as String),
                              if (page!['country'] != null) _InfoRow(icon: Icons.public, text: page!['country'] as String),
                              if ((page!['business_hours'] as Map?)?['note'] != null)
                                _InfoRow(icon: Icons.schedule_outlined, text: (page!['business_hours'] as Map)['note'] as String),
                            ],
                          ),
                        ),
                        const SizedBox(height: PageTokens.spaceXl),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: PageTokens.spaceLg),
                          child: SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: publishing ? null : _publish,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.brandTeal,
                                foregroundColor: AppColors.onBrandTeal,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PageTokens.radiusPill)),
                              ),
                              child: publishing
                                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onBrandTeal))
                                  : const Text('Publish page', style: TextStyle(fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ),
                      ],
                    ),
    );
  }
}

class _CoverAndLogo extends StatelessWidget {
  const _CoverAndLogo({required this.page});
  final Map<String, dynamic> page;

  @override
  Widget build(BuildContext context) {
    final coverUrl = page['cover_url'] as String?;
    final logoUrl = page['logo_url'] as String?;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        AspectRatio(
          aspectRatio: 3,
          child: coverUrl != null
              ? Image.network(coverUrl, fit: BoxFit.cover)
              : Container(decoration: BoxDecoration(gradient: PageColors.coverFallbackGradient(context))),
        ),
        Positioned(
          left: PageTokens.spaceLg,
          bottom: -32,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: PageColors.surfaceCard(context), width: 3),
              color: PageColors.surfaceMuted(context),
              image: logoUrl != null ? DecorationImage(image: NetworkImage(logoUrl), fit: BoxFit.cover) : null,
            ),
            child: logoUrl == null ? const Icon(Icons.storefront, size: 28) : null,
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      );
}
