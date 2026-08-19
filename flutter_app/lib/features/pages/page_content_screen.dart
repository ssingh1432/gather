import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../data/repositories.dart';
import '../../shared/widgets/reusables.dart';
import '../../shared/utils/time_ago.dart';
import 'page_content_composer_screen.dart';
import 'page_media_gallery.dart';
import 'pages_theme.dart';

/// Content management for a Page's team (Step 7): every `page_posts`
/// status (draft/scheduled/published/archived) in one place with
/// pin/edit/archive actions, plus a lightweight Events tab backed by
/// `page_events`. Reachable only by whoever has `manage_content`; RLS
/// (migration 073) independently enforces that on every read/write this
/// screen makes regardless of what got it here.
class PageContentScreen extends StatefulWidget {
  const PageContentScreen({super.key, required this.pageId});
  final String pageId;

  @override
  State<PageContentScreen> createState() => _PageContentScreenState();
}

class _PageContentScreenState extends State<PageContentScreen> with SingleTickerProviderStateMixin {
  final _repo = PageRepository();
  late final TabController _tabs = TabController(length: 2, vsync: this);
  bool _loadingPosts = true;
  bool _loadingEvents = true;
  String? _postsError;
  String? _eventsError;
  List<Map<String, dynamic>> _posts = const [];
  List<Map<String, dynamic>> _events = const [];

  @override
  void initState() {
    super.initState();
    _loadPosts();
    _loadEvents();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadPosts() async {
    setState(() {
      _loadingPosts = true;
      _postsError = null;
    });
    try {
      final posts = await _repo.listPagePosts(widget.pageId);
      if (mounted) setState(() => _posts = posts);
    } catch (e) {
      if (mounted) _postsError = 'Could not load posts. $e';
    } finally {
      if (mounted) setState(() => _loadingPosts = false);
    }
  }

  Future<void> _loadEvents() async {
    setState(() {
      _loadingEvents = true;
      _eventsError = null;
    });
    try {
      final events = await _repo.listPageEvents(widget.pageId);
      if (mounted) setState(() => _events = events);
    } catch (e) {
      if (mounted) _eventsError = 'Could not load events. $e';
    } finally {
      if (mounted) setState(() => _loadingEvents = false);
    }
  }

  Future<void> _openComposer({Map<String, dynamic>? existingPost}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PageContentComposerScreen(pageId: widget.pageId, existingPost: existingPost)),
    );
    if (saved == true) _loadPosts();
  }

  Future<void> _togglePin(Map<String, dynamic> post) async {
    try {
      await _repo.setPagePostPinned(widget.pageId, post['id'] as String, !(post['pinned'] as bool));
      await _loadPosts();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not update pin: $e')));
    }
  }

  Future<void> _archive(Map<String, dynamic> post) async {
    try {
      await _repo.updatePagePost(post['id'] as String, {'status': 'archived', 'pinned': false});
      await _loadPosts();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not archive: $e')));
    }
  }

  Future<void> _delete(Map<String, dynamic> post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Page post'),
        content: const Text('This removes the post from the page. This cannot be undone from here.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Delete', style: TextStyle(color: Theme.of(ctx).colorScheme.error))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repo.deletePagePost(post['id'] as String);
      await _loadPosts();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not delete: $e')));
    }
  }

  Future<void> _openCreateEvent() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _CreateEventSheet(pageId: widget.pageId, repo: _repo),
    );
    if (created == true) _loadEvents();
  }

  Future<void> _deleteEvent(Map<String, dynamic> event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete event'),
        content: Text('Delete "${event['title']}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Delete', style: TextStyle(color: Theme.of(ctx).colorScheme.error))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repo.deletePageEvent(event['id'] as String);
      await _loadEvents();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not delete event: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Content', style: TextStyle(fontWeight: FontWeight.w700)),
        bottom: TabBar(controller: _tabs, tabs: const [Tab(text: 'Posts'), Tab(text: 'Events')]),
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _tabs,
        builder: (_, __) => FloatingActionButton.extended(
          onPressed: _tabs.index == 0 ? () => _openComposer() : _openCreateEvent,
          backgroundColor: AppColors.brandTeal,
          foregroundColor: AppColors.onBrandTeal,
          icon: const Icon(Icons.add),
          label: Text(_tabs.index == 0 ? 'New Page post' : 'New event'),
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _loadingPosts
              ? const FeedSkeletonList()
              : _postsError != null
                  ? ErrorRetryState(title: 'Unable to load posts', message: _postsError!, onRetry: _loadPosts)
                  : _posts.isEmpty
                      ? const _EmptyTab(icon: Icons.article_outlined, message: 'No Page posts yet. Create your first Page post.')
                      : RefreshIndicator(
                          onRefresh: _loadPosts,
                          child: ListView.separated(
                            padding: const EdgeInsets.all(PageTokens.spaceLg),
                            itemCount: _posts.length,
                            separatorBuilder: (_, __) => const SizedBox(height: PageTokens.spaceSm),
                            itemBuilder: (_, i) => _PostRow(
                              post: _posts[i],
                              onEdit: () => _openComposer(existingPost: _posts[i]),
                              onTogglePin: () => _togglePin(_posts[i]),
                              onArchive: () => _archive(_posts[i]),
                              onDelete: () => _delete(_posts[i]),
                            ),
                          ),
                        ),
          _loadingEvents
              ? const FeedSkeletonList()
              : _eventsError != null
                  ? ErrorRetryState(title: 'Unable to load events', message: _eventsError!, onRetry: _loadEvents)
                  : _events.isEmpty
                      ? const _EmptyTab(icon: Icons.event_outlined, message: 'No events yet. Create your first event.')
                      : RefreshIndicator(
                          onRefresh: _loadEvents,
                          child: ListView.separated(
                            padding: const EdgeInsets.all(PageTokens.spaceLg),
                            itemCount: _events.length,
                            separatorBuilder: (_, __) => const SizedBox(height: PageTokens.spaceSm),
                            itemBuilder: (_, i) => _EventRow(event: _events[i], onDelete: () => _deleteEvent(_events[i])),
                          ),
                        ),
        ],
      ),
    );
  }
}

const _statusColors = <String, Color>{
  'draft': Colors.grey,
  'scheduled': Colors.amber,
  'published': Colors.green,
  'archived': Colors.blueGrey,
};

class _PostRow extends StatelessWidget {
  const _PostRow({required this.post, required this.onEdit, required this.onTogglePin, required this.onArchive, required this.onDelete});
  final Map<String, dynamic> post;
  final VoidCallback onEdit;
  final VoidCallback onTogglePin;
  final VoidCallback onArchive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final status = post['status'] as String;
    final type = post['post_type'] as String;
    final pinned = post['pinned'] as bool;
    final content = post['content'] as String? ?? '';
    final media = post['media'];
    final imageUrl = media is List && media.isNotEmpty && media.first is Map ? (media.first as Map)['url'] as String? : null;

    return Container(
      padding: const EdgeInsets.all(PageTokens.spaceMd),
      decoration: BoxDecoration(
        color: PageColors.surfaceCard(context),
        borderRadius: BorderRadius.circular(PageTokens.radiusMd),
        border: Border.all(color: PageColors.border(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (imageUrl != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(PageTokens.radiusSm),
              child: PageNetworkImage(url: imageUrl, width: 56, height: 56),
            ),
            const SizedBox(width: PageTokens.spaceMd),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (pinned) const Icon(Icons.push_pin, size: 14, color: AppColors.brandTeal),
                    PageStatChip(icon: kPagePostTypeIcons[type] ?? Icons.article_outlined, label: kPagePostTypes[type] ?? type),
                    PageStatChip(icon: Icons.circle, label: status, color: _statusColors[status]),
                  ],
                ),
                if (content.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(content, maxLines: 3, overflow: TextOverflow.ellipsis),
                ],
                const SizedBox(height: 4),
                Text(timeAgo(DateTime.parse(post['created_at'] as String)), style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'edit':
                  onEdit();
                  break;
                case 'pin':
                  onTogglePin();
                  break;
                case 'archive':
                  onArchive();
                  break;
                case 'delete':
                  onDelete();
                  break;
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              if (status == 'published') PopupMenuItem(value: 'pin', child: Text(pinned ? 'Unpin' : 'Pin to top')),
              if (status != 'archived') const PopupMenuItem(value: 'archive', child: Text('Archive')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event, required this.onDelete});
  final Map<String, dynamic> event;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final start = DateTime.parse(event['start_time'] as String).toLocal();
    return Container(
      padding: const EdgeInsets.all(PageTokens.spaceMd),
      decoration: BoxDecoration(
        color: PageColors.surfaceCard(context),
        borderRadius: BorderRadius.circular(PageTokens.radiusMd),
        border: Border.all(color: PageColors.border(context)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppColors.brandTeal.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(PageTokens.radiusSm)),
            child: const Icon(Icons.event, color: AppColors.brandTeal, size: 20),
          ),
          const SizedBox(width: PageTokens.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event['title'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  '${start.day}/${start.month}/${start.year} · ${TimeOfDay.fromDateTime(start).format(context)}${event['location'] != null ? ' · ${event['location']}' : ''}',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: onDelete),
        ],
      ),
    );
  }
}

class _EmptyTab extends StatelessWidget {
  const _EmptyTab({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(PageTokens.spaceXl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: PageTokens.spaceMd),
              Text(message, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      );
}

class _CreateEventSheet extends StatefulWidget {
  const _CreateEventSheet({required this.pageId, required this.repo});
  final String pageId;
  final PageRepository repo;

  @override
  State<_CreateEventSheet> createState() => _CreateEventSheetState();
}

class _CreateEventSheetState extends State<_CreateEventSheet> {
  final _titleController = TextEditingController();
  final _locationController = TextEditingController();
  DateTime? _start;
  bool _saving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final now = DateTime.now();
    final date = await showDatePicker(context: context, initialDate: now.add(const Duration(days: 1)), firstDate: now, lastDate: now.add(const Duration(days: 730)));
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (time == null) return;
    setState(() => _start = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _create() async {
    if (_titleController.text.trim().isEmpty || _start == null || _saving) {
      if (_start == null) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Choose a date and time.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.repo.createPageEvent({
        'page_id': widget.pageId,
        'title': _titleController.text.trim(),
        'location': _locationController.text.trim().isEmpty ? null : _locationController.text.trim(),
        'start_time': _start!.toIso8601String(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not create event: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('New event', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(controller: _titleController, decoration: pageFieldDecoration(context, labelText: 'Event title')),
          const SizedBox(height: 12),
          TextField(controller: _locationController, decoration: pageFieldDecoration(context, labelText: 'Location (optional)')),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule_outlined),
            title: Text(_start == null ? 'Choose date & time' : _formatEventStart(_start!)),
            onTap: _pickStart,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _create,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brandTeal,
                foregroundColor: AppColors.onBrandTeal,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(PageTokens.radiusPill)),
              ),
              child: _saving
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onBrandTeal))
                  : const Text('Create event'),
            ),
          ),
        ],
      ),
    );
  }
}

const _eventMonths = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Mirrors the composer's own `_formatScheduled` (page_content_composer_screen.dart)
/// so a chosen event date/time reads the same way scheduled posts do,
/// instead of the raw `DateTime.toString()` this replaced (e.g.
/// "2026-08-20 14:30:00.000").
String _formatEventStart(DateTime dateTime) {
  final local = dateTime.toLocal();
  final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final ampm = local.hour < 12 ? 'AM' : 'PM';
  final minute = local.minute.toString().padLeft(2, '0');
  return '${_eventMonths[local.month - 1]} ${local.day}, ${local.year} · $hour12:$minute $ampm';
}
