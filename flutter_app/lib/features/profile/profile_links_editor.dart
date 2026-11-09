import 'package:flutter/material.dart';

import '../../core/supabase_client.dart';
import '../../shared/utils/profile_themes.dart';

class _LinkDraft {
  _LinkDraft({String label = '', String url = ''})
      : label = TextEditingController(text: label),
        url = TextEditingController(text: url);
  final TextEditingController label;
  final TextEditingController url;
  void dispose() {
    label.dispose();
    url.dispose();
  }
}

/// Holds the editable set of profile links (max 5) and persists them.
class ProfileLinksController extends ChangeNotifier {
  static const maxLinks = 5;
  final List<_LinkDraft> _drafts = [];
  bool loaded = false;

  Future<void> load(String userId) async {
    try {
      final rows = await SupabaseConfig.client
          .from('user_links')
          .select('label, url')
          .eq('user_id', userId)
          .order('position')
          .order('created_at') as List;
      for (final r in rows) {
        _drafts.add(_LinkDraft(label: r['label'] as String, url: r['url'] as String));
      }
    } catch (_) {}
    loaded = true;
    notifyListeners();
  }

  void add() {
    if (_drafts.length >= maxLinks) return;
    _drafts.add(_LinkDraft());
    notifyListeners();
  }

  void removeAt(int i) {
    _drafts.removeAt(i).dispose();
    notifyListeners();
  }

  /// Returns an error message or null. Blank rows are ignored.
  String? validate() {
    for (final d in _drafts) {
      final label = d.label.text.trim();
      final url = d.url.text.trim();
      if (label.isEmpty && url.isEmpty) continue;
      if (label.isEmpty || label.length > 40) return 'Each link needs a title (max 40 characters).';
      final uri = Uri.tryParse(url);
      if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty || url.length > 300) {
        return 'Links must start with http:// or https://';
      }
    }
    return null;
  }

  /// Inserts the new set first, then removes the previous rows, so a failed
  /// insert never leaves the user with no links.
  Future<void> save(String userId) async {
    // Never save before the existing links have loaded: that would wipe them.
    if (!loaded) return;
    final c = SupabaseConfig.client;
    final old = (await c.from('user_links').select('id').eq('user_id', userId) as List).map((r) => r['id'] as String).toList();
    final fresh = <Map<String, dynamic>>[];
    var pos = 0;
    for (final d in _drafts) {
      final label = d.label.text.trim();
      final url = d.url.text.trim();
      if (label.isEmpty && url.isEmpty) continue;
      fresh.add({'user_id': userId, 'label': label, 'url': url, 'position': pos++});
    }
    if (old.isNotEmpty) {
      // The 5-link trigger counts existing rows, so clear first only when
      // inserting would exceed the cap.
      if (old.length + fresh.length > maxLinks) {
        await c.from('user_links').delete().eq('user_id', userId);
        if (fresh.isNotEmpty) await c.from('user_links').insert(fresh);
        return;
      }
    }
    if (fresh.isNotEmpty) await c.from('user_links').insert(fresh);
    if (old.isNotEmpty) await c.from('user_links').delete().inFilter('id', old);
  }

  @override
  void dispose() {
    for (final d in _drafts) {
      d.dispose();
    }
    super.dispose();
  }
}

class ProfileLinksEditor extends StatelessWidget {
  const ProfileLinksEditor({super.key, required this.controller});
  final ProfileLinksController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Links', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            for (var i = 0; i < controller._drafts.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: controller._drafts[i].label,
                        maxLength: 40,
                        decoration: const InputDecoration(labelText: 'Title', counterText: ''),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: controller._drafts[i].url,
                        keyboardType: TextInputType.url,
                        decoration: const InputDecoration(labelText: 'URL', hintText: 'https://...'),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove link',
                      icon: const Icon(Icons.close),
                      onPressed: () => controller.removeAt(i),
                    ),
                  ],
                ),
              ),
            if (controller._drafts.length < ProfileLinksController.maxLinks)
              TextButton.icon(onPressed: controller.add, icon: const Icon(Icons.add), label: const Text('Add link')),
          ],
        );
      },
    );
  }
}

class ProfileThemePicker extends StatelessWidget {
  const ProfileThemePicker({super.key, required this.selected, required this.onChanged});
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Profile theme', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            for (final entry in ProfileThemes.accents.entries)
              Semantics(
                button: true,
                selected: selected == entry.key,
                label: '${ProfileThemes.labels[entry.key]} theme',
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => onChanged(entry.key),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: entry.value,
                      shape: BoxShape.circle,
                      border: Border.all(
                        width: selected == entry.key ? 3 : 1,
                        color: selected == entry.key ? Theme.of(context).colorScheme.onSurface : Theme.of(context).dividerColor,
                      ),
                    ),
                    child: selected == entry.key ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
