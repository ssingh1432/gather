import 'package:flutter/material.dart';

import '../../core/supabase_client.dart';
import '../../core/theme/app_theme.dart';
import '../data/repositories.dart';
import '../../shared/widgets/reusables.dart';
import 'pages_theme.dart';
import 'subscribe_sheet.dart';

/// Subscriptions / Paid Followers (Step 15/15b): lists a page's tiers.
/// Anyone signed in sees active tiers and can subscribe (real eSewa
/// payment via [showSubscribeSheet]); managers with `manage_monetization`
/// additionally get create/edit/delete/activate controls for tiers,
/// including inactive drafts nobody else can see (RLS already scopes
/// this — see page_subscription_tiers_select in migration 089).
class PageSubscriptionsScreen extends StatefulWidget {
  const PageSubscriptionsScreen({super.key, required this.pageId, this.pageName});
  final String pageId;
  final String? pageName;

  @override
  State<PageSubscriptionsScreen> createState() => _PageSubscriptionsScreenState();
}

class _PageSubscriptionsScreenState extends State<PageSubscriptionsScreen> {
  final _repo = PageRepository();
  bool _loading = true;
  bool _canManage = false;
  List<Map<String, dynamic>> _tiers = const [];
  Map<String, dynamic>? _mySubscription;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final canManage = await _repo.hasPagePermission(widget.pageId, 'manage_monetization');
      final tiers = await _repo.listSubscriptionTiers(widget.pageId);
      final mySub = await _repo.mySubscription(widget.pageId);
      if (!mounted) return;
      setState(() {
        _canManage = canManage;
        _tiers = tiers;
        _mySubscription = mySub;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not load tiers: $e')));
      }
    }
  }

  Future<void> _editTier([Map<String, dynamic>? existing]) async {
    final nameController = TextEditingController(text: existing?['name'] as String? ?? '');
    final descController = TextEditingController(text: existing?['description'] as String? ?? '');
    final priceController = TextEditingController(text: existing != null ? ((existing['price_cents'] as int) / 100).toStringAsFixed(0) : '');
    var active = existing?['active'] as bool? ?? false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'New tier' : 'Edit tier'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameController, decoration: pageFieldDecoration(context, labelText: 'Tier name')),
                const SizedBox(height: 12),
                TextField(controller: descController, decoration: pageFieldDecoration(context, labelText: 'Benefits / description'), maxLines: 3),
                const SizedBox(height: 12),
                TextField(controller: priceController, keyboardType: TextInputType.number, decoration: pageFieldDecoration(context, labelText: 'Price per month (NPR)')),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active (visible to followers)'),
                  value: active,
                  onChanged: (v) => setDialogState(() => active = v),
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
    if (nameController.text.trim().isEmpty || price == null || price <= 0) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a name and valid price')));
      return;
    }
    try {
      await _repo.upsertSubscriptionTier(widget.pageId, {
        if (existing != null) 'id': existing['id'],
        'name': nameController.text.trim(),
        'description': descController.text.trim(),
        'price_cents': price * 100,
        'active': active,
      });
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save tier: $e')));
    }
  }

  Future<void> _deleteTier(String tierId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete tier?'),
        content: const Text('Existing subscribers on this tier will keep their subscription but lose the tier reference.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repo.deleteSubscriptionTier(tierId);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not delete tier: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final myTierId = _mySubscription != null && _mySubscription!['status'] == 'active' ? _mySubscription!['tier_id'] as String? : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pageName?.isNotEmpty == true ? '${widget.pageName} · Subscriptions' : 'Subscriptions', style: const TextStyle(fontWeight: FontWeight.w700)),
        bottom: appBarBottomBorder(context),
      ),
      floatingActionButton: _canManage ? FloatingActionButton.extended(onPressed: () => _editTier(), icon: const Icon(Icons.add), label: const Text('New tier')) : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _tiers.isEmpty
              ? EmptyState(
                  icon: Icons.workspace_premium_outlined,
                  title: 'No subscription tiers yet',
                  message: _canManage ? 'Create a tier to let followers support this page monthly.' : 'This page hasn\'t set up subscriptions yet.',
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(PageTokens.spaceLg),
                    itemCount: _tiers.length,
                    separatorBuilder: (_, __) => const SizedBox(height: PageTokens.spaceMd),
                    itemBuilder: (context, i) {
                      final tier = _tiers[i];
                      final isMine = tier['id'] == myTierId;
                      final isActive = tier['active'] as bool? ?? false;
                      if (!isActive && !_canManage) return const SizedBox.shrink();

                      return Container(
                        padding: const EdgeInsets.all(PageTokens.spaceMd),
                        decoration: BoxDecoration(
                          color: PageColors.surfaceCard(context),
                          borderRadius: BorderRadius.circular(PageTokens.radiusMd),
                          border: Border.all(color: isMine ? AppColors.brandTeal : PageColors.border(context), width: isMine ? 2 : 1),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(child: Text(tier['name'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                                if (!isActive) const PageStatChip(icon: Icons.visibility_off_outlined, label: 'Draft'),
                                if (isMine) const Padding(padding: EdgeInsets.only(left: 6), child: PageStatChip(icon: Icons.check_circle, label: 'Your plan')),
                              ],
                            ),
                            if ((tier['description'] as String?)?.isNotEmpty ?? false) ...[
                              const SizedBox(height: 4),
                              Text(tier['description'] as String, style: Theme.of(context).textTheme.bodySmall),
                            ],
                            const SizedBox(height: PageTokens.spaceMd),
                            Row(
                              children: [
                                Text('Rs. ${((tier['price_cents'] as int) / 100).toStringAsFixed(0)}/mo', style: const TextStyle(fontWeight: FontWeight.w700)),
                                const Spacer(),
                                if (_canManage) ...[
                                  IconButton(icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _editTier(tier)),
                                  IconButton(icon: const Icon(Icons.delete_outline, size: 18), onPressed: () => _deleteTier(tier['id'] as String)),
                                ] else if (isActive && !isMine && SupabaseConfig.currentUserId != null)
                                  FilledButton(
                                    onPressed: () => showSubscribeSheet(context, pageId: widget.pageId, pageName: widget.pageName ?? 'this page', tier: tier),
                                    child: const Text('Subscribe'),
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
}
