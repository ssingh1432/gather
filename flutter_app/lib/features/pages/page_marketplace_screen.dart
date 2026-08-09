import 'package:flutter/material.dart';

import '../../core/supabase_client.dart';
import '../data/repositories.dart';
import '../../shared/widgets/reusables.dart';
import 'pages_theme.dart';
import 'marketplace_checkout_sheet.dart';

/// Marketplace (Step 15/15b): lists a page's products/services. Anyone
/// signed in sees active/sold-out listings and can buy (real eSewa
/// payment via [showMarketplaceCheckoutSheet]); managers with
/// `manage_monetization` additionally get create/edit/delete/status
/// controls, including drafts nobody else can see (RLS scopes this — see
/// page_marketplace_items_select in migration 089).
class PageMarketplaceScreen extends StatefulWidget {
  const PageMarketplaceScreen({super.key, required this.pageId, this.pageName});
  final String pageId;
  final String? pageName;

  @override
  State<PageMarketplaceScreen> createState() => _PageMarketplaceScreenState();
}

class _PageMarketplaceScreenState extends State<PageMarketplaceScreen> {
  final _repo = PageRepository();
  bool _loading = true;
  bool _canManage = false;
  List<Map<String, dynamic>> _items = const [];

  static const _statusOptions = ['draft', 'active', 'archived', 'sold_out'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final canManage = await _repo.hasPagePermission(widget.pageId, 'manage_monetization');
      final items = await _repo.listMarketplaceItems(widget.pageId);
      if (!mounted) return;
      setState(() {
        _canManage = canManage;
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not load listings: $e')));
      }
    }
  }

  Future<void> _editItem([Map<String, dynamic>? existing]) async {
    final titleController = TextEditingController(text: existing?['title'] as String? ?? '');
    final descController = TextEditingController(text: existing?['description'] as String? ?? '');
    final priceController = TextEditingController(text: existing != null ? ((existing['price_cents'] as int) / 100).toStringAsFixed(0) : '');
    var status = existing?['status'] as String? ?? 'draft';

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'New listing' : 'Edit listing'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: titleController, decoration: pageFieldDecoration(context, labelText: 'Title')),
                const SizedBox(height: 12),
                TextField(controller: descController, decoration: pageFieldDecoration(context, labelText: 'Description'), maxLines: 3),
                const SizedBox(height: 12),
                TextField(controller: priceController, keyboardType: TextInputType.number, decoration: pageFieldDecoration(context, labelText: 'Price (NPR)')),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: status,
                  decoration: pageFieldDecoration(context, labelText: 'Status'),
                  items: _statusOptions.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                  onChanged: (v) => setDialogState(() => status = v ?? status),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Save')),
          ],
        ),
      ),
    );

    if (saved != true) return;
    final price = int.tryParse(priceController.text.trim());
    if (titleController.text.trim().isEmpty || price == null || price < 0) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a title and valid price')));
      return;
    }
    try {
      await _repo.upsertMarketplaceItem(widget.pageId, {
        if (existing != null) 'id': existing['id'],
        'title': titleController.text.trim(),
        'description': descController.text.trim(),
        'price_cents': price * 100,
        'status': status,
      });
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save listing: $e')));
    }
  }

  Future<void> _deleteItem(String itemId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete listing?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repo.deleteMarketplaceItem(itemId);
      _load();
    } catch (e) {
      if (mounted) {
        // Orders referencing this item block a hard delete (ON DELETE
        // RESTRICT) — surface that plainly instead of a raw FK error.
        final msg = e.toString().contains('foreign key') ? 'Cannot delete — this item has existing orders. Archive it instead.' : 'Could not delete listing: $e';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pageName?.isNotEmpty == true ? '${widget.pageName} · Shop' : 'Shop', style: const TextStyle(fontWeight: FontWeight.w700)),
        bottom: appBarBottomBorder(context),
      ),
      floatingActionButton: _canManage ? FloatingActionButton.extended(onPressed: () => _editItem(), icon: const Icon(Icons.add), label: const Text('New listing')) : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? EmptyState(
                  icon: Icons.storefront_outlined,
                  title: 'No listings yet',
                  message: _canManage ? 'Add a product or service for followers to buy.' : 'This page hasn\'t listed anything yet.',
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(PageTokens.spaceLg),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: PageTokens.spaceMd),
                    itemBuilder: (context, i) {
                      final item = _items[i];
                      final status = item['status'] as String? ?? 'draft';
                      if (status != 'active' && status != 'sold_out' && !_canManage) return const SizedBox.shrink();
                      final canBuy = status == 'active' && !_canManage && SupabaseConfig.currentUserId != null;

                      return Container(
                        padding: const EdgeInsets.all(PageTokens.spaceMd),
                        decoration: BoxDecoration(
                          color: PageColors.surfaceCard(context),
                          borderRadius: BorderRadius.circular(PageTokens.radiusMd),
                          border: Border.all(color: PageColors.border(context)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(child: Text(item['title'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                                if (status != 'active') PageStatChip(icon: _statusIcon(status), label: status.replaceAll('_', ' ')),
                              ],
                            ),
                            if ((item['description'] as String?)?.isNotEmpty ?? false) ...[
                              const SizedBox(height: 4),
                              Text(item['description'] as String, style: Theme.of(context).textTheme.bodySmall),
                            ],
                            const SizedBox(height: PageTokens.spaceMd),
                            Row(
                              children: [
                                Text('Rs. ${((item['price_cents'] as int) / 100).toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                                const Spacer(),
                                if (_canManage) ...[
                                  IconButton(icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _editItem(item)),
                                  IconButton(icon: const Icon(Icons.delete_outline, size: 18), onPressed: () => _deleteItem(item['id'] as String)),
                                ] else if (canBuy)
                                  FilledButton(
                                    onPressed: () => showMarketplaceCheckoutSheet(context, pageId: widget.pageId, pageName: widget.pageName ?? 'this page', item: item),
                                    child: const Text('Buy'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  IconData _statusIcon(String status) => switch (status) {
        'draft' => Icons.visibility_off_outlined,
        'archived' => Icons.archive_outlined,
        'sold_out' => Icons.block,
        _ => Icons.circle_outlined,
      };
}
