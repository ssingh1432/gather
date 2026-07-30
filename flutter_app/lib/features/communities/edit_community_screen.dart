import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/supabase_client.dart';
import '../../shared/services/media/web_safe_pick.dart';
import '../../shared/widgets/profile_view.dart' show PickedImagePreview;
import '../data/repositories.dart';

const _categories = [
  'General', 'Local / City', 'Sports', 'Music', 'Movies & TV', 'Gaming',
  'Tech', 'Business', 'Education', 'Food', 'Travel', 'News & Politics',
  'Art & Design', 'Fitness & Health', 'Fashion', 'Other',
];

/// Edit-info + delete for a community/page. Reachable only from the detail
/// screen's settings action, which already gates on `myRole` — but every
/// mutation here also goes through server-side RLS/RPC checks (owner or
/// admin for updates, owner or site admin for delete), so this screen isn't
/// itself the security boundary.
class EditCommunityScreen extends StatefulWidget {
  const EditCommunityScreen({super.key, required this.communityId});
  final String communityId;

  @override
  State<EditCommunityScreen> createState() => _EditCommunityScreenState();
}

class _EditCommunityScreenState extends State<EditCommunityScreen> {
  final repo = CommunityRepository();
  final _formKey = GlobalKey<FormState>();
  final name = TextEditingController();
  final desc = TextEditingController();
  final rules = TextEditingController();
  final customCategory = TextEditingController();

  String category = 'General';
  String visibility = 'public';
  String? _existingIconUrl;
  String? _existingBannerUrl;
  XFile? iconPick;
  XFile? bannerPick;
  bool _isOwner = false;

  bool _loading = true;
  bool _saving = false;
  bool _deleting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    name.dispose();
    desc.dispose();
    rules.dispose();
    customCategory.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final community = await repo.getCommunity(widget.communityId);
      if (community == null) throw Exception('Community not found');
      final uid = SupabaseConfig.currentUserId;
      final role = uid == null ? null : await repo.myRole(widget.communityId, uid);
      name.text = community['name'] as String? ?? '';
      desc.text = community['description'] as String? ?? '';
      rules.text = community['rules'] as String? ?? '';
      final cat = community['category'] as String?;
      category = (cat != null && _categories.contains(cat)) ? cat : (cat == null ? 'General' : 'Other');
      if (category == 'Other') customCategory.text = cat ?? '';
      visibility = community['visibility'] as String? ?? 'public';
      _existingIconUrl = community['image_url'] as String?;
      _existingBannerUrl = community['banner_url'] as String?;
      _isOwner = role == 'owner';
    } catch (e) {
      _error = 'Could not load community. $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickImage({required bool banner}) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final safe = await materializeIfWeb(picked);
    setState(() {
      if (banner) {
        bannerPick = safe;
      } else {
        iconPick = safe;
      }
    });
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final resolvedCategory = category == 'Other' && customCategory.text.trim().isNotEmpty ? customCategory.text.trim() : category;
      String? iconUrl = _existingIconUrl;
      String? bannerUrl = _existingBannerUrl;
      if (iconPick != null) iconUrl = await repo.uploadIcon(widget.communityId, iconPick!);
      if (bannerPick != null) bannerUrl = await repo.uploadBanner(widget.communityId, bannerPick!);

      await repo.updateCommunity(widget.communityId, {
        'name': name.text.trim(),
        'description': desc.text.trim(),
        'category': resolvedCategory,
        'rules': rules.text.trim().isEmpty ? null : rules.text.trim(),
        'visibility': visibility,
        if (iconUrl != null) 'image_url': iconUrl,
        if (bannerUrl != null) 'banner_url': bannerUrl,
      });

      if (!mounted) return;
      context.pop(true);
    } catch (e) {
      final message = e.toString().contains('duplicate key') || e.toString().contains('communities_name_key')
          ? 'That community name is already taken. Try another.'
          : 'Could not save changes. $e';
      setState(() => _error = message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete community'),
        content: Text('This permanently deletes "${name.text}" and removes all its members. Posts already made in it will remain but lose their community link. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _deleting = true);
    try {
      await repo.deleteCommunity(widget.communityId);
      if (!mounted) return;
      context.go('/communities');
    } catch (e) {
      if (mounted) {
        setState(() => _deleting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not delete community: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Community'),
        actions: [
          if (_isOwner)
            IconButton(
              icon: _deleting ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.delete_outline),
              onPressed: _deleting ? null : _confirmDelete,
              tooltip: 'Delete community',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _ImageEditTile(label: 'Banner', existingUrl: _existingBannerUrl, pick: bannerPick, onTap: () => _pickImage(banner: true)),
                  const SizedBox(height: 12),
                  _ImageEditTile(label: 'Icon', existingUrl: _existingIconUrl, pick: iconPick, onTap: () => _pickImage(banner: false), circular: true),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: name,
                    maxLength: 60,
                    decoration: const InputDecoration(labelText: 'Name'),
                    validator: (v) => (v == null || v.trim().length < 3) ? 'Name must be at least 3 characters' : null,
                  ),
                  TextFormField(
                    controller: desc,
                    maxLength: 300,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Description'),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                    onChanged: (v) => setState(() => category = v ?? 'General'),
                  ),
                  if (category == 'Other')
                    TextFormField(controller: customCategory, decoration: const InputDecoration(labelText: 'Custom category')),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: rules,
                    maxLength: 1000,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Community rules (optional)'),
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: Column(children: [
                      RadioListTile<String>(
                        value: 'public',
                        groupValue: visibility,
                        title: const Text('Public'),
                        subtitle: const Text('Anyone can find and join instantly'),
                        onChanged: (v) => setState(() => visibility = v ?? 'public'),
                      ),
                      RadioListTile<String>(
                        value: 'private',
                        groupValue: visibility,
                        title: const Text('Private'),
                        subtitle: const Text('Joining requires owner/admin approval'),
                        onChanged: (v) => setState(() => visibility = v ?? 'public'),
                      ),
                    ]),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Save changes'),
                  ),
                ],
              ),
            ),
    );
  }
}

class _ImageEditTile extends StatelessWidget {
  const _ImageEditTile({required this.label, required this.existingUrl, required this.pick, required this.onTap, this.circular = false});

  final String label;
  final String? existingUrl;
  final XFile? pick;
  final VoidCallback onTap;
  final bool circular;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(circular ? Icons.groups : Icons.image_outlined, color: Theme.of(context).colorScheme.outline),
    );
    Widget preview = placeholder;
    if (pick != null) {
      preview = PickedImagePreview(bytesFuture: pick!.readAsBytes());
    } else if (existingUrl != null && existingUrl!.isNotEmpty) {
      preview = Image.network(existingUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => placeholder);
    }
    return InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(circular ? 999 : 8),
            child: AspectRatio(
              aspectRatio: circular ? 1 : 3,
              child: SizedBox(width: circular ? 88 : double.infinity, child: preview),
            ),
          ),
        ],
      ),
    );
  }
}
