import 'dart:async';

import 'package:flutter/material.dart';

import '../data/repositories.dart';
import '../../core/theme/app_theme.dart';
import 'community_theme.dart';

/// Chip-based tag input: type + submit to add, tap the x to remove.
/// Suggests existing tags from the catalog as you type (debounced) so
/// people converge on shared tags ("food" vs "Food" vs "foods") instead
/// of fragmenting the catalog — actual dedup still happens server-side
/// in get_or_create_community_tag() regardless of what's picked here.
class TagInput extends StatefulWidget {
  const TagInput({super.key, required this.tags, required this.onChanged, this.maxTags = 10});
  final List<String> tags;
  final ValueChanged<List<String>> onChanged;
  final int maxTags;

  @override
  State<TagInput> createState() => _TagInputState();
}

class _TagInputState extends State<TagInput> {
  final _controller = TextEditingController();
  final _repo = CommunityRepository();
  Timer? _debounce;
  List<String> _suggestions = const [];

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() => _suggestions = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      final options = await _repo.searchTagOptions(query);
      if (mounted) {
        setState(() => _suggestions = options.map((o) => o['name'] as String).where((n) => !widget.tags.contains(n)).toList());
      }
    });
  }

  void _add(String raw) {
    final tag = raw.trim();
    if (tag.isEmpty || widget.tags.length >= widget.maxTags || widget.tags.any((t) => t.toLowerCase() == tag.toLowerCase())) {
      return;
    }
    widget.onChanged([...widget.tags, tag]);
    _controller.clear();
    setState(() => _suggestions = const []);
  }

  void _remove(String tag) => widget.onChanged(widget.tags.where((t) => t != tag).toList());

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.tags.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tag in widget.tags)
                Chip(
                  label: Text('#$tag'),
                  onDeleted: () => _remove(tag),
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CommunityTokens.radiusPill)),
                  backgroundColor: AppColors.brandTealLight.withValues(alpha: 0.35),
                  labelStyle: const TextStyle(fontWeight: FontWeight.w600),
                  side: BorderSide.none,
                ),
            ],
          ),
          const SizedBox(height: CommunityTokens.spaceSm),
        ],
        if (widget.tags.length < widget.maxTags)
          TextField(
            controller: _controller,
            decoration: communityFieldDecoration(
              context,
              labelText: 'Tags',
              hintText: 'e.g. hiking, weekend, kathmandu',
              helperText: '${widget.tags.length}/${widget.maxTags} — press enter to add',
              suffixIcon: IconButton(icon: const Icon(Icons.add), onPressed: () => _add(_controller.text)),
            ),
            onChanged: _onQueryChanged,
            onSubmitted: _add,
          ),
        if (_suggestions.isNotEmpty) ...[
          const SizedBox(height: CommunityTokens.spaceSm),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in _suggestions.take(8))
                ActionChip(
                  label: Text(s),
                  onPressed: () => _add(s),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CommunityTokens.radiusPill)),
                  side: BorderSide(color: CommunityColors.border(context)),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
