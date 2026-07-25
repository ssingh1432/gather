import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase_client.dart';
import '../../shared/models/models.dart';
import '../data/repositories.dart';

/// Step 10 — Scheduled Posts. Lists everything still 'pending' for the
/// current user, with reschedule/cancel actions. Publishing itself happens
/// server-side (pg_cron, see migration 035); this screen never publishes
/// anything directly, it only manages the not-yet-fired queue.
class ScheduledPostsScreen extends StatefulWidget {
  const ScheduledPostsScreen({super.key});

  @override
  State<ScheduledPostsScreen> createState() => _ScheduledPostsScreenState();
}

class _ScheduledPostsScreenState extends State<ScheduledPostsScreen> {
  final _repo = ScheduledPostRepository();
  late Future<List<ScheduledPostModel>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<ScheduledPostModel>> _load() {
    final uid = SupabaseConfig.currentUserId;
    if (uid == null) return Future.value(const []);
    return _repo.listUpcoming(uid);
  }

  void _refresh() => setState(() => _future = _load());

  Future<void> _reschedule(ScheduledPostModel post) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: post.scheduledAt.isAfter(now) ? post.scheduledAt : now.add(const Duration(minutes: 5)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(post.scheduledAt));
    if (time == null) return;
    final newTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    try {
      await _repo.reschedule(post.id, newTime, clientTimezone: DateTime.now().timeZoneName);
      _refresh();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rescheduled')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not reschedule: $e')));
    }
  }

  Future<void> _cancel(ScheduledPostModel post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel scheduled post?'),
        content: const Text('This post will not be published. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancel post')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repo.cancel(post.id);
      _refresh();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Scheduled post cancelled')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not cancel: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scheduled Posts')),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<List<ScheduledPostModel>>(
          future: _future,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final posts = snapshot.data!;
            if (posts.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(child: Text('No scheduled posts.')),
                  SizedBox(height: 8),
                  Center(child: Text('Compose a post and tap the clock icon to schedule it.', textAlign: TextAlign.center)),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: posts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final p = posts[index];
                return Card(
                  child: ListTile(
                    leading: p.imageUrl != null
                        ? CircleAvatar(backgroundImage: NetworkImage(p.imageUrl!))
                        : const CircleAvatar(child: Icon(Icons.schedule_outlined)),
                    title: Text(
                      p.textContent.isEmpty ? '(media only)' : p.textContent,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text('Scheduled for ${_formatLocal(p.scheduledAt)} · ${p.visibility}'),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'reschedule') _reschedule(p);
                        if (v == 'cancel') _cancel(p);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'reschedule', child: Text('Reschedule')),
                        PopupMenuItem(value: 'cancel', child: Text('Cancel')),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/create-post'),
        child: const Icon(Icons.add),
      ),
    );
  }

  String _formatLocal(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.month)}/${two(d.day)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }
}
