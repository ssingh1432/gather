import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n/app_l10n.dart';
import '../../core/supabase_client.dart';
import '../../core/responsive.dart';
import '../../shared/utils/external_link.dart';
import '../data/repositories.dart';
import '../legal/my_legal_screen.dart';
import '../moderation/my_moderation_screen.dart';
import '../privacy/data_privacy_screen.dart';
import '../privacy/mute_list_screen.dart';
import '../privacy/restricted_accounts_screen.dart';
import '../beta/beta_feedback_button.dart';
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
  bool _safeSearchEnabled = true;
  bool _childSafetyMode = false;
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
          _safeSearchEnabled = (profile['safe_search_enabled'] as bool?) ?? true;
          _childSafetyMode = (profile['child_safety_mode'] as bool?) ?? false;
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
        title: Text(AppL10n.of(context).setDeactivateQ),
        content: Text(AppL10n.of(context).setDeactivateBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(AppL10n.of(context).commonCancel)),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(AppL10n.of(context).setDeactivateBtn),
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
        title: Text(AppL10n.of(context).settingsTitle),
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
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ListTile(
              leading: const Icon(Icons.accessibility_new),
              title: Text(AppL10n.of(context).settingsAccessibility),
              subtitle: Text(AppL10n.of(context).settingsAccessibilitySub),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/accessibility'),
            ),
            _SectionHeader(AppL10n.of(context).setPrivacy),
            SwitchListTile(
              title: Text(AppL10n.of(context).setPrivateAccount),
              subtitle: Text(AppL10n.of(context).setPrivateAccountSub),
              value: _isPrivate,
              onChanged: (v) {
                setState(() => _isPrivate = v);
                _patch({'is_private': v});
              },
            ),
            _OptionTile(
              title: AppL10n.of(context).setWhoPosts,
              value: _defaultPostVisibility,
              options: const {'public': 'Public', 'followers': 'Followers', 'friends': 'Close friends', 'private': 'Only me'},
              onChanged: (v) {
                setState(() => _defaultPostVisibility = v);
                _patch({'default_post_visibility': v});
              },
            ),
            _OptionTile(
              title: AppL10n.of(context).setWhoFriends,
              value: _friendsListVisibility,
              options: const {'everyone': 'Everyone', 'friends': 'Friends', 'only_me': 'Only me'},
              onChanged: (v) {
                setState(() => _friendsListVisibility = v);
                _patch({'friends_list_visibility': v});
              },
            ),
            _OptionTile(
              title: AppL10n.of(context).setWhoMessage,
              value: _messagePrivacy,
              options: const {'everyone': 'Everyone', 'friends': 'Friends', 'no_one': 'No one'},
              onChanged: (v) {
                setState(() => _messagePrivacy = v);
                _patch({'message_privacy': v});
              },
            ),
            _OptionTile(
              title: AppL10n.of(context).setWhoMention,
              value: _tagPrivacy,
              options: const {'everyone': 'Everyone', 'friends': 'Friends', 'no_one': 'No one'},
              onChanged: (v) {
                setState(() => _tagPrivacy = v);
                _patch({'tag_privacy': v});
              },
            ),
            SwitchListTile(
              title: Text(AppL10n.of(context).setActivityStatus),
              subtitle: Text(AppL10n.of(context).setActivityStatusSub),
              value: _showActivityStatus,
              onChanged: (v) {
                setState(() => _showActivityStatus = v);
                _patch({'show_activity_status': v});
              },
            ),
            SwitchListTile(
              title: Text(AppL10n.of(context).setReadReceipts),
              subtitle: Text(AppL10n.of(context).setReadReceiptsSub),
              value: _showReadReceipts,
              onChanged: (v) {
                setState(() => _showReadReceipts = v);
                _patch({'show_read_receipts': v});
              },
            ),
            _OptionTile(
              title: AppL10n.of(context).setWhoSearch,
              value: _searchVisibility,
              options: const {'everyone': 'Everyone', 'friends': 'Friends', 'no_one': 'No one'},
              onChanged: (v) {
                setState(() => _searchVisibility = v);
                _patch({'search_visibility': v});
              },
            ),
            SwitchListTile(
              title: Text(AppL10n.of(context).setLastSeen),
              subtitle: Text(AppL10n.of(context).setLastSeenSub),
              value: _showLastSeen,
              onChanged: (v) {
                setState(() => _showLastSeen = v);
                _patch({'show_last_seen': v});
              },
            ),
            ListTile(
              leading: const Icon(Icons.schedule_outlined),
              title: Text(AppL10n.of(context).setScheduledPosts),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/scheduled-posts'),
            ),
            ListTile(
              leading: const Icon(Icons.block_outlined),
              title: Text(AppL10n.of(context).setBlocked),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BlockedAccountsScreen())),
            ),
            ListTile(
              leading: const Icon(Icons.volume_off_outlined),
              title: Text(AppL10n.of(context).setMuted),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MuteListScreen())),
            ),
            ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: Text(AppL10n.of(context).setRestricted),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RestrictedAccountsScreen())),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.visibility_off_outlined),
              title: Text(AppL10n.of(context).setSafeSearch),
              subtitle: Text(AppL10n.of(context).setSafeSearchSub),
              value: _safeSearchEnabled,
              onChanged: _childSafetyMode
                  ? null
                  : (v) {
                      setState(() => _safeSearchEnabled = v);
                      _patch({'safe_search_enabled': v});
                    },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.family_restroom),
              title: Text(AppL10n.of(context).setChildSafety),
              subtitle: Text(AppL10n.of(context).setChildSafetySub),
              value: _childSafetyMode,
              onChanged: (v) async {
                await _patch({'child_safety_mode': v});
                // The server trigger may also flip safe_search_enabled and
                // message_privacy when turning this on — resync from truth
                // rather than guessing what it did client-side.
                await _load();
              },
            ),

            _SectionHeader(AppL10n.of(context).setDataPrivacyHeader),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: Text(AppL10n.of(context).setDataConsent),
              subtitle: Text(AppL10n.of(context).setDataConsentSub),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DataPrivacyScreen())),
            ),
            ListTile(
              leading: const Icon(Icons.gavel_outlined),
              title: Text(AppL10n.of(context).setGrievances),
              subtitle: Text(AppL10n.of(context).setGrievancesSub),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyLegalScreen())),
            ),
            ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: Text(AppL10n.of(context).setModerationHistory),
              subtitle: Text(AppL10n.of(context).setModerationHistorySub),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyModerationScreen())),
            ),

            _SectionHeader(AppL10n.of(context).setHelp),
            const BetaFeedbackButton(),

            _SectionHeader(AppL10n.of(context).setLegal),
            _LegalLinkTile(
              icon: Icons.description_outlined,
              title: AppL10n.of(context).setPrivacyPolicy,
              url: 'https://eiquoab.xyz/privacy-policy/',
            ),
            _LegalLinkTile(
              icon: Icons.rule_outlined,
              title: AppL10n.of(context).setTerms,
              url: 'https://eiquoab.xyz/terms/',
            ),
            _LegalLinkTile(
              icon: Icons.diversity_3_outlined,
              title: AppL10n.of(context).setGuidelines,
              url: 'https://eiquoab.xyz/community-guidelines/',
            ),
            _LegalLinkTile(
              icon: Icons.cookie_outlined,
              title: AppL10n.of(context).setCookie,
              url: 'https://eiquoab.xyz/cookie-policy/',
            ),
            _LegalLinkTile(
              icon: Icons.copyright_outlined,
              title: AppL10n.of(context).setCopyright,
              url: 'https://eiquoab.xyz/copyright-policy/',
            ),
            _LegalLinkTile(
              icon: Icons.local_police_outlined,
              title: AppL10n.of(context).setLawEnforcement,
              url: 'https://eiquoab.xyz/law-enforcement-requests/',
            ),

            _SectionHeader(AppL10n.of(context).setNotifications),
            SwitchListTile(
              title: Text(AppL10n.of(context).setNotifLikes),
              value: _notif('likes'),
              onChanged: (v) => _setNotif('likes', v),
            ),
            SwitchListTile(
              title: Text(AppL10n.of(context).setNotifComments),
              value: _notif('comments'),
              onChanged: (v) => _setNotif('comments', v),
            ),
            SwitchListTile(
              title: Text(AppL10n.of(context).setNotifFriendRequests),
              value: _notif('friend_requests'),
              onChanged: (v) => _setNotif('friend_requests', v),
            ),
            SwitchListTile(
              title: Text(AppL10n.of(context).setNotifMentions),
              value: _notif('mentions'),
              onChanged: (v) => _setNotif('mentions', v),
            ),
            SwitchListTile(
              title: Text(AppL10n.of(context).setNotifMessages),
              value: _notif('messages'),
              onChanged: (v) => _setNotif('messages', v),
            ),
            SwitchListTile(
              title: Text(AppL10n.of(context).setNotifCommunity),
              value: _notif('community_activity'),
              onChanged: (v) => _setNotif('community_activity', v),
            ),
            SwitchListTile(
              title: Text(AppL10n.of(context).setNotifModeration),
              subtitle: Text(AppL10n.of(context).setNotifModerationSub),
              value: _notif('moderation_alerts'),
              onChanged: (v) => _setNotif('moderation_alerts', v),
            ),
            SwitchListTile(
              title: Text(AppL10n.of(context).setNotifAnnouncements),
              subtitle: Text(AppL10n.of(context).setNotifAnnouncementsSub),
              value: _notif('admin_broadcasts'),
              onChanged: (v) => _setNotif('admin_broadcasts', v),
            ),
            ListTile(
              leading: Icon(Icons.shield_outlined),
              title: Text(AppL10n.of(context).setNotifSecurity),
              subtitle: Text(AppL10n.of(context).setNotifSecuritySub),
              enabled: false,
            ),

            _SectionHeader(AppL10n.of(context).setAccount),
            ListTile(
              leading: const Icon(Icons.alternate_email),
              title: Text(AppL10n.of(context).setChangeUsername),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/change-username'),
            ),
            ListTile(
              leading: const Icon(Icons.verified_outlined),
              title: Text(AppL10n.of(context).setGetVerified),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/request-verification'),
            ),
            ListTile(
              leading: const Icon(Icons.verified_user_outlined),
              title: Text(AppL10n.of(context).setSecurityDevices),
              subtitle: Text(AppL10n.of(context).setSecurityDevicesSub),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/security'),
            ),
            ListTile(
              leading: const Icon(Icons.lock_reset_outlined),
              title: Text(AppL10n.of(context).setChangePassword),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/forgot'),
            ),
            ListTile(
              leading: const Icon(Icons.phone_android_outlined),
              title: Text(AppL10n.of(context).setVerifyPhone),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/verify-phone'),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: Icon(Icons.person_off_outlined, color: Theme.of(context).colorScheme.error),
              title: Text(AppL10n.of(context).setDeactivate, style: TextStyle(color: Theme.of(context).colorScheme.error)),
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