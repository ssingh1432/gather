import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/supabase_client.dart';
import '../../shared/services/media_upload_service.dart';
import '../data/repositories.dart';

/// Suggested interest tags for discovery. Kept short and Nepal-relevant;
/// users can still type free-form ones via the "Add" field.
const _suggestedInterests = [
  'Music', 'Movies', 'Sports', 'Cricket', 'Football', 'Trekking',
  'Photography', 'Cooking', 'Gaming', 'Tech', 'Art', 'Fashion',
  'Travel', 'Books', 'Business', 'Startups', 'Comedy', 'Politics',
];

/// Curated list of major Nepali cities/districts, plus a free-text fallback
/// so nobody is blocked from setting a location that isn't on the list.
const _nepalLocations = [
  'Kathmandu', 'Pokhara', 'Lalitpur', 'Bhaktapur', 'Biratnagar',
  'Birgunj', 'Dharan', 'Bharatpur', 'Butwal', 'Nepalgunj',
  'Hetauda', 'Janakpur', 'Itahari', 'Dhangadhi', 'Other / Abroad',
];

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _displayName = TextEditingController();
  final _bio = TextEditingController();
  final _website = TextEditingController();
  final _customInterest = TextEditingController();

  String? _location;
  String _language = 'ne';
  final Set<String> _interests = {};

  XFile? _avatarPick;
  XFile? _coverPick;
  String? _existingAvatarUrl;
  String? _existingCoverUrl;

  bool _loading = true;
  bool _saving = false;
  String? _error;

  String? get _uid => SupabaseConfig.currentUserId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _displayName.dispose();
    _bio.dispose();
    _website.dispose();
    _customInterest.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final profile = await ProfileRepository().loadProfile(uid);
      if (profile != null && mounted) {
        setState(() {
          _displayName.text = (profile['display_name'] as String?) ?? '';
          _bio.text = (profile['bio'] as String?) ?? '';
          _website.text = (profile['website_url'] as String?) ?? '';
          _location = profile['location'] as String?;
          _language = (profile['language_preference'] as String?) ?? 'ne';
          _interests.addAll(((profile['interests'] as List?) ?? []).cast<String>());
          _existingAvatarUrl = profile['profile_photo_url'] as String?;
          _existingCoverUrl = profile['cover_photo_url'] as String?;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load profile: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickImage(ProfileImageKind kind) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    setState(() {
      if (kind == ProfileImageKind.avatar) {
        _avatarPick = picked;
      } else {
        _coverPick = picked;
      }
    });
  }

  void _toggleInterest(String tag) {
    setState(() {
      if (_interests.contains(tag)) {
        _interests.remove(tag);
      } else {
        _interests.add(tag);
      }
    });
  }

  void _addCustomInterest() {
    final value = _customInterest.text.trim();
    if (value.isEmpty) return;
    setState(() {
      _interests.add(value);
      _customInterest.clear();
    });
  }

  Future<void> _save() async {
    final uid = _uid;
    if (uid == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final repo = ProfileRepository();
      String? avatarUrl = _existingAvatarUrl;
      String? coverUrl = _existingCoverUrl;

      if (_avatarPick != null) {
        avatarUrl = await repo.uploadProfileImage(uid, _avatarPick!, ProfileImageKind.avatar);
      }
      if (_coverPick != null) {
        coverUrl = await repo.uploadProfileImage(uid, _coverPick!, ProfileImageKind.cover);
      }

      await repo.updateProfile(uid, {
        'display_name': _displayName.text.trim().isEmpty ? null : _displayName.text.trim(),
        'bio': _bio.text.trim(),
        'website_url': _website.text.trim().isEmpty ? null : _website.text.trim(),
        'location': _location,
        'language_preference': _language,
        'interests': _interests.toList(),
        if (avatarUrl != null) 'profile_photo_url': avatarUrl,
        if (coverUrl != null) 'cover_photo_url': coverUrl,
      });

      if (!mounted) return;
      context.pop();
    } catch (e) {
      setState(() => _error = 'Could not save profile. $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null) ...[
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
          ],
          _CoverAndAvatarPicker(
            coverPick: _coverPick,
            avatarPick: _avatarPick,
            existingCoverUrl: _existingCoverUrl,
            existingAvatarUrl: _existingAvatarUrl,
            onPickCover: () => _pickImage(ProfileImageKind.cover),
            onPickAvatar: () => _pickImage(ProfileImageKind.avatar),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _displayName,
            decoration: const InputDecoration(labelText: 'Display name', hintText: 'Shown instead of your username'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _bio,
            maxLength: 160,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Bio', alignLabelWithHint: true),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _location,
            decoration: const InputDecoration(labelText: 'Location'),
            items: _nepalLocations
                .map((loc) => DropdownMenuItem(value: loc, child: Text(loc)))
                .toList(),
            onChanged: (v) => setState(() => _location = v),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _website,
            decoration: const InputDecoration(labelText: 'Website / link', hintText: 'https://...'),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 24),
          const Text('App language', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'ne', label: Text('नेपाली')),
              ButtonSegment(value: 'en', label: Text('English')),
            ],
            selected: {_language},
            onSelectionChanged: (v) => setState(() => _language = v.first),
          ),
          const SizedBox(height: 24),
          const Text('Interests', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in {..._suggestedInterests, ..._interests})
                FilterChip(
                  label: Text(tag),
                  selected: _interests.contains(tag),
                  onSelected: (_) => _toggleInterest(tag),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _customInterest,
                  decoration: const InputDecoration(labelText: 'Add your own', isDense: true),
                  onSubmitted: (_) => _addCustomInterest(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(icon: const Icon(Icons.add_circle), onPressed: _addCustomInterest),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _CoverAndAvatarPicker extends StatelessWidget {
  const _CoverAndAvatarPicker({
    required this.coverPick,
    required this.avatarPick,
    required this.existingCoverUrl,
    required this.existingAvatarUrl,
    required this.onPickCover,
    required this.onPickAvatar,
  });

  final XFile? coverPick;
  final XFile? avatarPick;
  final String? existingCoverUrl;
  final String? existingAvatarUrl;
  final VoidCallback onPickCover;
  final VoidCallback onPickAvatar;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 160,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            onTap: onPickCover,
            child: Container(
              height: 120,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF1D9E75).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                image: existingCoverUrl != null
                    ? DecorationImage(image: NetworkImage(existingCoverUrl!), fit: BoxFit.cover)
                    : null,
              ),
              child: existingCoverUrl == null
                  ? const Center(child: Icon(Icons.add_photo_alternate_outlined, size: 32, color: Color(0xFF1D9E75)))
                  : (coverPick != null
                      ? const Align(
                          alignment: Alignment.topRight,
                          child: Padding(
                            padding: EdgeInsets.all(6),
                            child: Chip(label: Text('New photo selected'), visualDensity: VisualDensity.compact),
                          ),
                        )
                      : null),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 16,
            child: GestureDetector(
              onTap: onPickAvatar,
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.white,
                    child: CircleAvatar(
                      radius: 37,
                      backgroundColor: const Color(0xFF1D9E75).withValues(alpha: 0.15),
                      backgroundImage: existingAvatarUrl != null ? NetworkImage(existingAvatarUrl!) : null,
                      child: existingAvatarUrl == null
                          ? const Icon(Icons.person, size: 36, color: Color(0xFF1D9E75))
                          : null,
                    ),
                  ),
                  if (avatarPick != null)
                    const Positioned(
                      right: 0,
                      bottom: 0,
                      child: CircleAvatar(
                        radius: 10,
                        backgroundColor: Color(0xFF1D9E75),
                        child: Icon(Icons.check, size: 14, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
