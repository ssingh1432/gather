import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/supabase_client.dart';
import '../../core/responsive.dart';
import '../../shared/providers/app_providers.dart';
import '../../shared/services/media/web_safe_pick.dart';
import '../../shared/services/media_upload_service.dart';
import '../../shared/widgets/profile_view.dart';
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

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _displayName = TextEditingController();
  final _bio = TextEditingController();
  final _website = TextEditingController();
  final _customInterest = TextEditingController();
  final _pronouns = TextEditingController();

  String? _location;
  String _language = 'ne';
  bool _isPrivate = false;
  String _accountMode = 'personal';
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
    _pronouns.dispose();
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
          _pronouns.text = (profile['pronouns'] as String?) ?? '';
          _isPrivate = (profile['is_private'] as bool?) ?? false;
          _accountMode = (profile['account_mode'] as String?) ?? 'personal';
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
    final safe = await materializeIfWeb(picked);
    setState(() {
      if (kind == ProfileImageKind.avatar) {
        _avatarPick = safe;
      } else {
        _coverPick = safe;
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
        'pronouns': _pronouns.text.trim().isEmpty ? null : _pronouns.text.trim(),
        'is_private': _isPrivate,
        'account_mode': _accountMode,
        if (avatarUrl != null) 'profile_photo_url': avatarUrl,
        if (coverUrl != null) 'cover_photo_url': coverUrl,
      });

      if (!mounted) return;
      ref.invalidate(currentUserProfileProvider);
      context.pop();
    } catch (e) {
      final message = 'Could not save profile. $e';
      setState(() => _error = message);
      // Same reasoning as create_post_screen: a form-embedded error Text can
      // be scrolled past on mobile and read as the save silently doing
      // nothing. A SnackBar makes the failure unmissable.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.red, duration: const Duration(seconds: 6)),
        );
      }
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
      body: ResponsiveCenter(
        child: ListView(
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
          const SizedBox(height: 16),
          TextField(
            controller: _pronouns,
            maxLength: 20,
            decoration: const InputDecoration(labelText: 'Pronouns', hintText: 'e.g. she/her', counterText: ''),
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
          const Text('Account type', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text(
            'Creator accounts unlock monetization tools once eligible. Anyone can switch back anytime.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'personal', label: Text('Personal')),
              ButtonSegment(value: 'creator', label: Text('Creator')),
            ],
            selected: {_accountMode},
            onSelectionChanged: (v) => setState(() => _accountMode = v.first),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Private account'),
            subtitle: const Text('Only your followers can see your posts'),
            value: _isPrivate,
            onChanged: (v) => setState(() => _isPrivate = v),
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
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: const Color(0xFF1D9E75).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                image: (coverPick == null && existingCoverUrl != null)
                    ? DecorationImage(image: NetworkImage(existingCoverUrl!), fit: BoxFit.cover)
                    : null,
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (coverPick != null) PickedImagePreview(bytesFuture: coverPick!.readAsBytes()),
                  if (coverPick == null && existingCoverUrl == null)
                    const Center(child: Icon(Icons.add_photo_alternate_outlined, size: 32, color: Color(0xFF1D9E75))),
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), shape: BoxShape.circle),
                      child: const Icon(Icons.camera_alt_outlined, size: 16, color: Colors.white),
                    ),
                  ),
                ],
              ),
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
                    child: ClipOval(
                      child: SizedBox(
                        width: 74,
                        height: 74,
                        child: avatarPick != null
                            ? PickedImagePreview(bytesFuture: avatarPick!.readAsBytes())
                            : Container(
                                color: const Color(0xFF1D9E75).withValues(alpha: 0.15),
                                child: existingAvatarUrl != null
                                    ? Image(image: NetworkImage(existingAvatarUrl!), fit: BoxFit.cover)
                                    : const Icon(Icons.person, size: 36, color: Color(0xFF1D9E75)),
                              ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(color: Color(0xFF1D9E75), shape: BoxShape.circle),
                      child: const Icon(Icons.camera_alt_outlined, size: 14, color: Colors.white),
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
