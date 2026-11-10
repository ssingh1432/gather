import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/supabase_client.dart';
import '../utils/profile_themes.dart';

const _badgeIcons = <String, IconData>{
  'favorite': Icons.favorite,
  'auto_awesome': Icons.auto_awesome,
  'volunteer_activism': Icons.volunteer_activism,
  'workspace_premium': Icons.workspace_premium,
};

/// Badges + links shown under a profile header. Fails quietly: a load error
/// just hides the section rather than breaking the profile.
class ProfileExtras extends StatefulWidget {
  const ProfileExtras({super.key, required this.userId, this.profileTheme});
  final String userId;
  final String? profileTheme;

  @override
  State<ProfileExtras> createState() => _ProfileExtrasState();
}

class _ProfileExtrasState extends State<ProfileExtras> {
  List<Map<String, dynamic>> _badges = const [];
  List<Map<String, dynamic>> _links = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ProfileExtras old) {
    super.didUpdateWidget(old);
    if (old.userId != widget.userId) _load();
  }

  Future<void> _load() async {
    try {
      final c = SupabaseConfig.client;
      final results = await Future.wait([
        c.from('user_badges').select('badge_slug, badges(name, description, icon)').eq('user_id', widget.userId),
        c.from('user_links').select('id, label, url').eq('user_id', widget.userId).order('position').order('created_at'),
      ]);
      if (!mounted) return;
      setState(() {
        _badges = (results[0] as List).cast<Map<String, dynamic>>();
        _links = (results[1] as List).cast<Map<String, dynamic>>();
      });
    } catch (_) {
      // Optional decoration; never break the profile.
    }
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    if (_badges.isEmpty && _links.isEmpty) return const SizedBox.shrink();
    final accent = ProfileThemes.accentFor(widget.profileTheme) ?? Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final b in _badges)
            Tooltip(
              message: (b['badges'] as Map?)?['description'] as String? ?? '',
              child: Chip(
                visualDensity: VisualDensity.compact,
                avatar: Icon(_badgeIcons[(b['badges'] as Map?)?['icon']] ?? Icons.workspace_premium, size: 16, color: accent),
                label: Text((b['badges'] as Map?)?['name'] as String? ?? ''),
              ),
            ),
          for (final l in _links)
            ActionChip(
              visualDensity: VisualDensity.compact,
              avatar: Icon(Icons.link, size: 16, color: accent),
              label: Text(l['label'] as String? ?? ''),
              onPressed: () => _open(l['url'] as String? ?? ''),
            ),
        ],
      ),
    );
  }
}
