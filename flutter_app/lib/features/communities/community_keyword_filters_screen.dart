import 'package:flutter/material.dart';

import '../data/repositories.dart';

/// Community-scoped keyword filters (migration 057) — layered on top of
/// the site-wide filters set by global admins. A match here only affects
/// this community; global filters still apply everywhere regardless.
class CommunityKeywordFiltersScreen extends StatefulWidget {
  const CommunityKeywordFiltersScreen({super.key, required this.communityId});
  final String communityId;

  @override
  State<CommunityKeywordFiltersScreen> createState() => _CommunityKeywordFiltersScreenState();
}

class _CommunityKeywordFiltersScreenState extends State<CommunityKeywordFiltersScreen> {
  final repo = CommunityRepository();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _filters = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _filters = await repo.listCommunityKeywordFilters(widget.communityId);
    } catch (e) {
      _error = 'Could not load keyword filters. $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addFilter() async {
    final result = await showDialog<_NewFilter>(context: context, builder: (ctx) => const _AddFilterDialog());
    if (result == null) return;
    try {
      await repo.addCommunityKeywordFilter(widget.communityId, result.keyword, category: result.category, severity: result.severity);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not add filter: $e')));
    }
  }

  Future<void> _deleteFilter(String id) async {
    try {
      await repo.deleteCommunityKeywordFilter(id);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not remove filter: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Keyword filters')),
      floatingActionButton: FloatingActionButton(onPressed: _addFilter, child: const Icon(Icons.add)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'These apply only within this community, on top of any site-wide filters. '
                        '"Block" prevents the post outright; "Flag" lets it through but files an automatic report for review.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    Expanded(
                      child: _filters.isEmpty
                          ? const Center(child: Text('No community-specific filters yet.'))
                          : ListView.separated(
                              itemCount: _filters.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, i) {
                                final f = _filters[i];
                                final severity = f['severity'] as String? ?? 'flag';
                                return ListTile(
                                  leading: Icon(severity == 'block' ? Icons.block : Icons.flag_outlined, color: severity == 'block' ? Colors.red : Colors.orange),
                                  title: Text(f['keyword'] as String? ?? ''),
                                  subtitle: Text('${f['category']} · $severity'),
                                  trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _deleteFilter(f['id'] as String)),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }
}

class _NewFilter {
  const _NewFilter(this.keyword, this.category, this.severity);
  final String keyword;
  final String category;
  final String severity;
}

const _reportCategories = [
  'spam', 'fake_account', 'harassment', 'hate_speech', 'violence', 'terrorism',
  'child_abuse', 'adult_content', 'copyright', 'scam', 'impersonation',
  'self_harm', 'drugs', 'other',
];

class _AddFilterDialog extends StatefulWidget {
  const _AddFilterDialog();
  @override
  State<_AddFilterDialog> createState() => _AddFilterDialogState();
}

class _AddFilterDialogState extends State<_AddFilterDialog> {
  final _controller = TextEditingController();
  String _category = 'other';
  String _severity = 'flag';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add keyword filter'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: _controller, autofocus: true, decoration: const InputDecoration(labelText: 'Keyword or phrase', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [for (final c in _reportCategories) DropdownMenuItem(value: c, child: Text(c.replaceAll('_', ' ')))],
            onChanged: (v) => setState(() => _category = v ?? 'other'),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'flag', label: Text('Flag')),
              ButtonSegment(value: 'block', label: Text('Block')),
            ],
            selected: {_severity},
            onSelectionChanged: (s) => setState(() => _severity = s.first),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (_controller.text.trim().isEmpty) return;
            Navigator.pop(context, _NewFilter(_controller.text.trim(), _category, _severity));
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}
