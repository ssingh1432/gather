import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase_client.dart';
import '../../core/responsive.dart';
import '../../shared/utils/external_link.dart';
import '../data/repositories.dart';
import '../legal/my_legal_screen.dart';
import '../privacy/data_privacy_screen.dart';
import '../privacy/mute_list_screen.dart';
import 'blocked_accounts_screen.dart';

/// Full settings screen: privacy/audience controls, notification
/// preferences, and account-level actions. Modeled on the settings people
/// expect from other social apps that require an account (Instagram,
/// Facebook, X) — granular "who can see/contact me" controls, per-category
/// notification toggles, and account management at the bottom.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _repo = ProfileRepository();

  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool _isPrivate = false;
  String _defaultPostVisibility = 'public';
  String _friendsListVisibility = 'everyone';
  String _messagePrivacy = 'everyone';
  String _tagPrivacy = 'everyone';
  bool _showActivityStatus = true;
  bool _showReadReceipts = true;
  String _searchVisibility = 'everyone';
  bool _showLastSeen = true;
  Map<String, dynamic> _notifications = const {};

  String? get _uid => SupabaseConfig.currentUserId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final profile = await _repo.loadProfile(uid);
      if (profile != null && mounted) {
        setState(() {
          _isPrivate = (profile['is_private'] as bool?) ?? false;
          _defaultPostVisibility = (profile['default_post_visibility'] as String?) ?? 'public';
          _friendsListVisibility = (profile['friends_list_visibility'] as String?) ?? 'everyone';
          _messagePrivacy = (profile['message_privacy'] as String?) ?? 'everyone';
          _tagPrivacy = (profile['tag_privacy'] as String?) ?? 'everyone';
          _showActivityStatus = (profile['show_activity_status'] as bool?) ?? true;
          _showReadReceipts = (profile['show_read_receipts'] as bool?) ?? true;
          _searchVisibility = (profile['search_visibility'] as String?) ?? 'everyone';
          _showLastSeen = (profile['show_last_seen'] as bool?) ?? true;
          _notifications = Map<String, dynamic>.from((profile['notification_settings'] as Map?) ?? {});
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load settings: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _notif(String key) => (_notifications[key] as bool?) ?? true;

  /// Every toggle/segment saves immediately (no separate Save button) —
  /// settings screens read as live switches in the apps this is modeled
  /// on, and it avoids losing changes if someone navigates away.
  Future<void> _patch(Map<String, dynamic> payload) async {
    final uid = _uid;
    if (uid == null) return;
    setState(() => _saving = true);
    try {
      await _repo.updateProfile(uid, payload);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save that change. $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setNotif(String key, bool value) async {
    setState(() => _notifications = {..._notifications, key: value});
    await _patch({'notification_settings': _notifications});
  }

  Future<void> _confirmDeactivate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Deactivate account?'),
        content: const Text(
          'Your profile and posts will be hidden from other people on Gather. '
          "Contact support to reactivate. This won't delete your data.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final uid = _uid;
    if (uid == null) return;
    try {
      await SupabaseConfig.client.from('users').update({'status': 'deactivated'}).eq('id', uid);
      await SupabaseConfig.client.auth.signOut();
      if (mounted) context.go('/login');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not deactivate account. $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
            ),
        ],
      ),
      body: ResponsiveCenter(
        child: ListView(
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            const _SectionHeader('Privacy'),
            SwitchListTile(
              title: const Text('Private account'),
              subtitle: const Text('Only approved followers can see your posts'),
              value: _isPrivate,
              onChanged: (v) {
                setState(() => _isPrivate = v);
                _patch({'is_private': v});
              },
            ),
            _OptionTile(
              title: 'Who can see your posts by default',
              value: _defaultPostVisibility,
              options: const {'public': 'Public', 'friends': 'Friends', 'only_me': 'Only me'},
              onChanged: (v) {
                setState(() => _defaultPostVisibility = v);
                _patch({'default_post_visibility': v});
              },
            ),
            _OptionTile(
              title: 'Who can see your friends list',
              value: _friendsListVisibility,
              options: const {'everyone': 'Everyone', 'friends': 'Friends', 'only_me': 'Only me'},
              onChanged: (v) {
                setState(() => _friendsListVisibility = v);
                _patch({'friends_list_visibility': v});
              },
            ),
            _OptionTile(
              title: 'Who can message you',
              value: _messagePrivacy,
              options: const {'everyone': 'Everyone', 'friends': 'Friends', 'no_one': 'No one'},
              onChanged: (v) {
                setState(() => _messagePrivacy = v);
                _patch({'message_privacy': v});
              },
            ),
            _OptionTile(
              title: 'Who can @mention or tag you',
              value: _tagPrivacy,
              options: const {'everyone': 'Everyone', 'friends': 'Friends', 'no_one': 'No one'},
              onChanged: (v) {
                setState(() => _tagPrivacy = v);
                _patch({'tag_privacy': v});
              },
            ),
            SwitchListTile(
              title: const Text('Show activity status'),
              subtitle: const Text('Let friends see when you\u2019re active on Gather'),
              value: _showActivityStatus,
              onChanged: (v) {
                setState(() => _showActivityStatus = v);
                _patch({'show_activity_status': v});
              },
            ),
            SwitchListTile(
              title: const Text('Read receipts'),
              subtitle: const Text('Let others see when you\u2019ve read their messages'),
              value: _showReadReceipts,
              onChanged: (v) {
                setState(() => _showReadReceipts = v);
                _patch({'show_read_receipts': v});
              },
            ),
            _OptionTile(
              title: 'Who can find you in search',
              value: _searchVisibility,
              options: const {'everyone': 'Everyone', 'friends': 'Friends', 'no_one': 'No one'},
              onChanged: (v) {
                setState(() => _searchVisibility = v);
                _patch({'search_visibility': v});
              },
            ),
            SwitchListTile(
              title: const Text('Show last seen'),
              subtitle: const Text('Let friends see when you were last active'),
              value: _showLastSeen,
              onChanged: (v) {
                setState(() => _showLastSeen = v);
                _patch({'show_last_seen': v});
              },
            ),
            ListTile(
              leading: const Icon(Icons.block_outlined),
              title: const Text('Blocked accounts'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BlockedAccountsScreen())),
            ),
            ListTile(
              leading: const Icon(Icons.volume_off_outlined),
              title: const Text('Muted accounts'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MuteListScreen())),
            ),

            const _SectionHeader('Data & Privacy'),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Data, consent & account deletion'),
              subtitle: const Text('Download your data, review consent history, or delete your account'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DataPrivacyScreen())),
            ),
            ListTile(
              leading: const Icon(Icons.gavel_outlined),
              title: const Text('Grievances & legal requests'),
              subtitle: const Text('File or track a complaint, illegal content report, or appeal'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyLegalScreen())),
            ),

            const _SectionHeader('Legal & Policies'),
            const _LegalLinkTile(
              icon: Icons.description_outlined,
              title: 'Privacy Policy',
              url: 'https://eiquoab.xyz/privacy-policy/',
            ),
            const _LegalLinkTile(
              icon: Icons.rule_outlined,
              title: 'Terms of Service',
              url: 'https://eiquoab.xyz/terms/',
            ),
            const _LegalLinkTile(
              icon: Icons.diversity_3_outlined,
              title: 'Community Guidelines',
              url: 'https://eiquoab.xyz/community-guidelines/',
            ),
            const _LegalLinkTile(
              icon: Icons.cookie_outlined,
              title: 'Cookie Policy',
              url: 'https://eiquoab.xyz/cookie-policy/',
            ),
            const _LegalLinkTile(
              icon: Icons.copyright_outlined,
              title: 'Copyright & IP Policy',
              url: 'https://eiquoab.xyz/copyright-policy/',
            ),
            const _LegalLinkTile(
              icon: Icons.local_police_outlined,
              title: 'Law Enforcement Requests',
              url: 'https://eiquoab.xyz/law-enforcement-requests/',
            ),

            const _SectionHeader('Notifications'),
            SwitchListTile(
              title: const Text('Likes'),
              value: _notif('likes'),
              onChanged: (v) => _setNotif('likes', v),
            ),
            SwitchListTile(
              title: const Text('Comments'),
              value: _notif('comments'),
              onChanged: (v) => _setNotif('comments', v),
            ),
            SwitchListTile(
              title: const Text('Friend requests'),
              value: _notif('friend_requests'),
              onChanged: (v) => _setNotif('friend_requests', v),
            ),
            SwitchListTile(
              title: const Text('Mentions'),
              value: _notif('mentions'),
              onChanged: (v) => _setNotif('mentions', v),
            ),
            SwitchListTile(
              title: const Text('Messages'),
              value: _notif('messages'),
              onChanged: (v) => _setNotif('messages', v),
            ),
            SwitchListTile(
              title: const Text('Community activity'),
              value: _notif('community_activity'),
              onChanged: (v) => _setNotif('community_activity', v),
            ),

            const _SectionHeader('Account'),
            ListTile(
              leading: const Icon(Icons.lock_reset_outlined),
              title: const Text('Change password'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/forgot'),
            ),
            ListTile(
              leading: const Icon(Icons.phone_android_outlined),
              title: const Text('Verify phone number'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/verify-phone'),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.person_off_outlined, color: Colors.red),
              title: const Text('Deactivate account', style: TextStyle(color: Colors.red)),
              onTap: _confirmDeactivate,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// A settings row that opens a published legal/policy page in an external
/// browser tab, via the shared openExternalLink helper (consistent
/// no-crash-if-nothing-can-open-it behavior used elsewhere in the app).
class _LegalLinkTile extends StatelessWidget {
  const _LegalLinkTile({required this.icon, required this.title, required this.url});
  final IconData icon;
  final String title;
  final String url;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon),
        title: Text(title),
        trailing: const Icon(Icons.open_in_new, size: 18),
        onTap: () => openExternalLink(context, url),
      );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary),
        ),
      );
}

/// A tappable row that opens a bottom sheet of radio options — used for
/// every "who can..." audience-picker setting.
class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String title;
  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;

  Future<void> _open(BuildContext context) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(title, style: Theme.of(sheetContext).textTheme.titleMedium),
            ),
            for (final entry in options.entries)
              ListTile(
                title: Text(entry.value),
                trailing: entry.key == value ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(sheetContext, entry.key),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (selected != null && selected != value) onChanged(selected);
  }

  @override
  Widget build(BuildContext context) => ListTile(
        title: Text(title),
        subtitle: Text(options[value] ?? value),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _open(context),
      );
}
