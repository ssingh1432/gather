import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
  bool canManageTeam = false;
  String? err;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await _repo.getPage(widget.pageId);
      final role = await _repo.currentUserPageRole(widget.pageId);
      final canManage = role == 'owner' || await _repo.hasPagePermission(widget.pageId, 'manage_roles');
      if (mounted) {
        setState(() {
          page = p;
          canManageTeam = canManage;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          err = 'Could not load this Page. Please try again.';
          loading = false;
        });
      }
    }
  }

  Future<void> _confirmPublish() async {
    if (publishing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Publish this Page?'),
        content: const Text(
          'Your Page will become visible to the public. You can still manage and update it after publishing.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep draft'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Publish Page'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _publish();
  }

  Future<void> _publish() async {
    setState(() => publishing = true);
    try {
      await _repo.updatePage(widget.pageId, {'status': 'published'});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Page published!')));
      context.pushReplacement('/my-pages');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not publish the Page. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => publishing = false);
    }
  }

  String get pageTypeLabel {
    final type = page?['page_type'] as String?;
    return kPageTypes[type] ?? type ?? 'Other';
  }

  String? get businessHoursNote {
    final hours = page?['business_hours'];
    if (hours is Map) {
      final note = hours['note'];
      if (note is String && note.isNotEmpty) return note;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Preview', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          if (canManageTeam)
            IconButton(
              icon: const Icon(Icons.group_outlined),
              tooltip: 'Team',
              onPressed: () => context.push('/page-team?id=${widget.pageId}'),
            ),
          TextButton(
            onPressed: () => context.go('/my-pages'),
            child: const Text('Back to My Pages'),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : err != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(PageTokens.spaceLg),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 40),
                        const SizedBox(height: PageTokens.spaceSm),
                        Text(err!, textAlign: TextAlign.center),
                        const SizedBox(height: PageTokens.spaceMd),
                        OutlinedButton(onPressed: _load, child: const Text('Try again')),
                      ],
                    ),
                  ),
                )
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
                        PageCoverAndLogo(page: page!),
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
                                  PageStatChip(icon: Icons.category_outlined, label: pageTypeLabel),
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
                              if (page!['website'] != null) PageInfoRow(icon: Icons.link, text: page!['website'] as String),
                              if (page!['phone'] != null) PageInfoRow(icon: Icons.phone_outlined, text: page!['phone'] as String),
                              if (page!['email'] != null) PageInfoRow(icon: Icons.email_outlined, text: page!['email'] as String),
                              if (page!['country'] != null) PageInfoRow(icon: Icons.public, text: page!['country'] as String),
                              if (businessHoursNote != null) PageInfoRow(icon: Icons.schedule_outlined, text: businessHoursNote!),
                            ],
                          ),
                        ),
                        const SizedBox(height: PageTokens.spaceXl),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: PageTokens.spaceLg),
                          child: SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: publishing ? null : _confirmPublish,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.brandTeal,
                                foregroundColor: AppColors.onBrandTeal,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PageTokens.radiusPill)),
                              ),
                              child: publishing
                                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onBrandTeal))
                                  : const Text('Publish Page', style: TextStyle(fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ),
                      ],
                    ),
    );
  }
}

class PageInfoRow extends StatelessWidget {
  const PageInfoRow({super.key, required this.icon, required this.text});
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
