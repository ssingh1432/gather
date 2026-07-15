import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase_client.dart';
import '../../shared/widgets/reusables.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late Future<List<dynamic>> _future = _load();

  Future<List<dynamic>> _load() async {
    final uid = SupabaseConfig.maybeClient?.auth.currentUser?.id;
    if (uid == null) return const [];
    final data = await SupabaseConfig.client
        .from('notifications')
        .select('*, actor:users!notifications_actor_id_fkey(id, username, profile_photo_url), '
            'post:posts!notifications_post_id_fkey(id, text_content)')
        .eq('recipient_id', uid)
        .order('created_at', ascending: false)
        .limit(100);
    return data as List<dynamic>;
  }

  void _retry() => setState(() => _future = _load());

  String _messageFor(Map<String, dynamic> n, String actorName) {
    switch (n['type']) {
      case 'new_follower':
        return '$actorName started following you';
      case 'post_like':
        return '$actorName liked your post';
      case 'post_comment':
        return '$actorName commented on your post';
      case 'post_reply':
        return '$actorName replied to your post';
      case 'mention':
        return '$actorName tagged you in a post';
      case 'community_post':
        return '$actorName posted in a community you\'re in';
      default:
        return '$actorName interacted with your post';
    }
  }

  IconData _iconFor(String? type) {
    switch (type) {
      case 'new_follower':
        return Icons.person_add_alt_1_outlined;
      case 'post_like':
        return Icons.favorite_outline;
      case 'post_comment':
        return Icons.mode_comment_outlined;
      case 'post_reply':
        return Icons.repeat;
      case 'mention':
        return Icons.alternate_email;
      case 'community_post':
        return Icons.groups_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  Future<void> _markReadAndOpen(Map<String, dynamic> n) async {
    if (n['is_read'] != true) {
      unawaited(SupabaseConfig.client.from('notifications').update({'is_read': true}).eq('id', n['id']));
    }
    final postId = n['post']?['id'] ?? n['post_id'];
    final actorId = n['actor']?['id'] ?? n['actor_id'];
    if (postId != null) {
      context.push('/post?id=$postId');
    } else if (n['type'] == 'new_follower' && actorId != null) {
      context.push('/user?id=$actorId');
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = SupabaseConfig.maybeClient?.auth.currentUser?.id;
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: uid == null
          ? const EmptyState(icon: Icons.login, title: 'Login required', message: 'Log in to view notifications.')
          : FutureBuilder<List<dynamic>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) return const FeedSkeletonList(itemCount: 4);
                if (snapshot.hasError) {
                  return ErrorRetryState(title: 'Unable to load notifications', message: 'Network failure. Check your connection and try again.', onRetry: _retry);
                }
                final notifications = snapshot.data ?? const [];
                if (notifications.isEmpty) {
                  return const EmptyState(icon: Icons.notifications_none, title: 'No notifications', message: 'You are all caught up.');
                }
                return RefreshIndicator(
                  onRefresh: () async => _retry(),
                  child: ListView.separated(
                    itemCount: notifications.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final n = notifications[i] as Map<String, dynamic>;
                      final actor = n['actor'] as Map<String, dynamic>?;
                      final actorName = actor?['username'] ?? 'Someone';
                      final avatarUrl = actor?['profile_photo_url'] as String?;
                      final post = n['post'] as Map<String, dynamic>?;
                      final preview = (post?['text_content'] as String?)?.trim();
                      final isRead = n['is_read'] == true;

                      return ListTile(
                        tileColor: isRead ? null : Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.25),
                        leading: CircleAvatar(
                          backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                          child: avatarUrl == null || avatarUrl.isEmpty ? Icon(_iconFor(n['type'] as String?)) : null,
                        ),
                        title: Text(_messageFor(n, actorName)),
                        subtitle: preview != null && preview.isNotEmpty
                            ? Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis)
                            : null,
                        trailing: Icon(_iconFor(n['type'] as String?), size: 18, color: Colors.grey),
                        onTap: () => _markReadAndOpen(n),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}
