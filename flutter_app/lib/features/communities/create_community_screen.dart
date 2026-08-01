import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/supabase_client.dart';
import '../../shared/services/media/web_safe_pick.dart';
import '../../shared/widgets/profile_view.dart' show PickedImagePreview;
import '../data/repositories.dart';
import 'tag_input.dart';

/// Suggested categories — free-text is still allowed via the "Other" field
/// so nobody is blocked by an incomplete list.
const _categories = [
  'General', 'Local / City', 'Sports', 'Music', 'Movies & TV', 'Gaming',
  'Tech', 'Business', 'Education', 'Food', 'Travel', 'News & Politics',
  'Art & Design', 'Fitness & Health', 'Fashion', 'Other',
];

class CreateCommunityScreen extends StatefulWidget {
  const CreateCommunityScreen({super.key});
  @override
  State<CreateCommunityScreen> createState() => _CC();
}

class _CC extends State<CreateCommunityScreen> {
  final _formKey = GlobalKey<FormState>();
  final name = TextEditingController();
  final desc = TextEditingController();
  final rules = TextEditingController();
  final customCategory = TextEditingController();
  final location = TextEditingController();
  final website = TextEditingController();

  String category = 'General';
  String visibility = 'public';
  String language = 'en';
  int? minAge;
  List<String> tags = [];
  XFile? iconPick;
  XFile? bannerPick;

  Timer? _nameDebounce;
  bool? _nameAvailable;
  bool _checkingName = false;

  final repo = CommunityRepository();

  String? err;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    if (SupabaseConfig.currentUserId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.go('/login?redirect=${Uri.encodeComponent('/create-community')}');
        }
      });
    }
    name.addListener(_onNameChanged);
  }

  void _onNameChanged() {
    _nameDebounce?.cancel();
    final value = name.text.trim();
    if (value.length < 3) {
      setState(() {
        _nameAvailable = null;
        _checkingName = false;
      });
      return;
    }
    setState(() => _checkingName = true);
    _nameDebounce = Timer(const Duration(milliseconds: 400), () async {
      final available = await repo.isCommunityNameAvailable(value);
      if (mounted && name.text.trim() == value) {
        setState(() {
          _nameAvailable = available;
          _checkingName = false;
        });
      }
    });
  }

  @override
  void dispose() {
    name.removeListener(_onNameChanged);
    _nameDebounce?.cancel();
    name.dispose();
    desc.dispose();
    rules.dispose();
    customCategory.dispose();
    location.dispose();
    website.dispose();
    super.dispose();
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

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_nameAvailable == false) {
      setState(() => err = 'That community name is already taken. Try another.');
      return;
    }
    final uid = SupabaseConfig.client.auth.currentUser?.id;
    if (uid == null) {
      context.go('/login?redirect=${Uri.encodeComponent('/create-community')}');
      return;
    }

    setState(() {
      loading = true;
      err = null;
    });

    try {
      final resolvedCategory = category == 'Other' && customCategory.text.trim().isNotEmpty ? customCategory.text.trim() : category;

      final community = await repo.createCommunity({
        'name': name.text.trim(),
        'description': desc.text.trim(),
        'created_by': uid,
        'category': resolvedCategory,
        'visibility': visibility,
        'rules': rules.text.trim().isEmpty ? null : rules.text.trim(),
        'location': location.text.trim().isEmpty ? null : location.text.trim(),
        'website': website.text.trim().isEmpty ? null : website.text.trim(),
        'language': language,
        'min_age': minAge,
      });
      final communityId = community['id'].toString();

      if (tags.isNotEmpty) await repo.setCommunityTags(communityId, tags);

      String? iconUrl;
      String? bannerUrl;
      if (iconPick != null) iconUrl = await repo.uploadIcon(communityId, iconPick!);
      if (bannerPick != null) bannerUrl = await repo.uploadBanner(communityId, bannerPick!);
      if (iconUrl != null || bannerUrl != null) {
        await repo.updateCommunity(communityId, {
          if (iconUrl != null) 'image_url': iconUrl,
          if (bannerUrl != null) 'banner_url': bannerUrl,
        });
      }

      if (!mounted) return;
      context.pushReplacement('/community?id=$communityId');
    } catch (e) {
      final message = e.toString().contains('duplicate key') || e.toString().contains('communities_name_key')
          ? 'That community name is already taken. Try another.'
          : 'Could not create community. $e';
      setState(() => err = message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Community')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _ImagePickerTile(
              label: 'Banner (optional)',
              aspect: 3,
              image: bannerPick,
              onTap: () => _pickImage(banner: true),
            ),
            const SizedBox(height: 12),
            _ImagePickerTile(
              label: 'Icon (optional)',
              aspect: 1,
              image: iconPick,
              circular: true,
              onTap: () => _pickImage(banner: false),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: name,
              maxLength: 60,
              decoration: InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Kathmandu Photographers',
                suffixIcon: _checkingName
                    ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                    : _nameAvailable == true
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : _nameAvailable == false
                            ? const Icon(Icons.cancel, color: Colors.red)
                            : null,
                helperText: _nameAvailable == false ? 'That name is already taken' : _nameAvailable == true ? 'Available' : null,
                helperStyle: TextStyle(color: _nameAvailable == false ? Colors.red : Colors.green),
              ),
              validator: (v) => (v == null || v.trim().length < 3) ? 'Name must be at least 3 characters' : null,
            ),
            TextFormField(
              controller: desc,
              maxLength: 300,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Description', hintText: 'What is this community about?'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setState(() => category = v ?? 'General'),
            ),
            if (category == 'Other')
              TextFormField(
                controller: customCategory,
                decoration: const InputDecoration(labelText: 'Custom category'),
              ),
            const SizedBox(height: 12),
            TagInput(tags: tags, onChanged: (t) => setState(() => tags = t)),
            const SizedBox(height: 8),
            TextFormField(
              controller: rules,
              maxLength: 1000,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Community rules (optional)', hintText: 'Shown to members before they post'),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: location,
              decoration: const InputDecoration(labelText: 'Location (optional)', hintText: 'e.g. Kathmandu, Nepal'),
            ),
            TextFormField(
              controller: website,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'Website (optional)', hintText: 'https://...'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: language,
                    decoration: const InputDecoration(labelText: 'Language'),
                    items: const [
                      DropdownMenuItem(value: 'en', child: Text('English')),
                      DropdownMenuItem(value: 'ne', child: Text('नेपाली')),
                    ],
                    onChanged: (v) => setState(() => language = v ?? 'en'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int?>(
                    initialValue: minAge,
                    decoration: const InputDecoration(labelText: 'Age restriction'),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('None')),
                      DropdownMenuItem(value: 13, child: Text('13+')),
                      DropdownMenuItem(value: 16, child: Text('16+')),
                      DropdownMenuItem(value: 18, child: Text('18+')),
                      DropdownMenuItem(value: 21, child: Text('21+')),
                    ],
                    onChanged: (v) => setState(() => minAge = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Card(
              child: RadioGroup<String>(
                groupValue: visibility,
                onChanged: (v) => setState(() => visibility = v ?? 'public'),
                child: const Column(children: [
                  RadioListTile<String>(
                    value: 'public',
                    title: Text('Public'),
                    subtitle: Text('Anyone can find and join instantly'),
                  ),
                  RadioListTile<String>(
                    value: 'private',
                    title: Text('Private'),
                    subtitle: Text('Visible in search, but joining requires owner/admin approval'),
                  ),
                  RadioListTile<String>(
                    value: 'invite_only',
                    title: Text('Invite only'),
                    subtitle: Text('Visible in search, but only joinable via a direct invite or invite link'),
                  ),
                  RadioListTile<String>(
                    value: 'secret',
                    title: Text('Secret'),
                    subtitle: Text('Hidden from search entirely — only members and people you invite can find it'),
                  ),
                ]),
              ),
            ),
            if (err != null) ...[
              const SizedBox(height: 12),
              Text(err!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: loading ? null : _submit,
              child: loading
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImagePickerTile extends StatelessWidget {
  const _ImagePickerTile({required this.label, required this.aspect, required this.image, required this.onTap, this.circular = false});

  final String label;
  final double aspect;
  final XFile? image;
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
    if (image != null) {
      preview = PickedImagePreview(bytesFuture: image!.readAsBytes());
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
              aspectRatio: circular ? 1 : aspect,
              child: SizedBox(width: circular ? 88 : double.infinity, child: preview),
            ),
          ),
        ],
      ),
    );
  }
}
