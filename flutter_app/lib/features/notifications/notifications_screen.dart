import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';
import '../../shared/widgets/reusables.dart';
import '../data/repositories.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late Future<List<dynamic>> _future = _load();
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    final channel = _channel;
    if (channel != null) SupabaseConfig.maybeClient?.removeChannel(channel);
    super.dispose();
  }

  /// Phase 9: notifications is now realtime-enabled (migration 044b), so a
  /// new row lands here the instant it's inserted instead of waiting for a
  /// manual pull-to-refresh. We just re-run the same load on any insert for
  /// this recipient rather than hand-patching the list — the table is
  /// capped to a `limit(100)` fetch, so a full refetch is cheap.
  void _subscribeRealtime() {
    final client = SupabaseConfig.maybeClient;
    final uid = client?.auth.currentUser?.id;
    if (client == null || uid == null) return;

    _channel = client
        .channel('public:notifications-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'recipient_id', value: uid),
          callback: (payload) {
            if (mounted) _retry();
          },
        )
        .subscribe();
  }

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
        final pageName = (n['metadata'] as Map?)?['page_name']?.toString();
        return pageName != null ? '$actorName tagged you in a post on $pageName' : '$actorName tagged you in a post';
      case 'community_post':
        return '$actorName posted in a community you\'re in';
      case 'community_invite':
        final communityName = (n['metadata'] as Map?)?['community_name']?.toString() ?? 'a community';
        return '$actorName invited you to join $communityName';
      case 'community_join_request':
        final requester = (n['metadata'] as Map?)?['requester_username']?.toString() ?? 'Someone';
        final communityName = (n['metadata'] as Map?)?['community_name']?.toString() ?? 'your community';
        return '@$requester wants to join $communityName';
      case 'community_join_update':
        final status = (n['metadata'] as Map?)?['status']?.toString() ?? 'updated';
        final communityName = (n['metadata'] as Map?)?['community_name']?.toString() ?? 'the community';
        return status == 'approved' ? 'Your request to join $communityName was approved' : 'Your request to join $communityName was declined';
      case 'community_role_changed':
        final newRole = (n['metadata'] as Map?)?['new_role']?.toString() ?? 'member';
        final communityName = (n['metadata'] as Map?)?['community_name']?.toString() ?? 'a community';
        return 'You are now $newRole in $communityName';
      case 'community_warning':
        final communityName = (n['metadata'] as Map?)?['community_name']?.toString() ?? 'a community';
        return 'You received a warning in $communityName';
      case 'community_ban':
        final communityName = (n['metadata'] as Map?)?['community_name']?.toString() ?? 'a community';
        return 'You were banned from $communityName';
      case 'community_announcement':
        final communityName = (n['metadata'] as Map?)?['community_name']?.toString() ?? 'a community';
        return 'Announcement in $communityName';
      case 'community_event_created':
        final title = (n['metadata'] as Map?)?['title']?.toString() ?? 'a new event';
        final communityName = (n['metadata'] as Map?)?['community_name']?.toString() ?? 'a community';
        return '"$title" was scheduled in $communityName';
      case 'page_new_follower':
        final pageName = (n['metadata'] as Map?)?['page_name']?.toString() ?? 'your page';
        final follower = (n['metadata'] as Map?)?['follower_username']?.toString();
        return follower != null ? '@$follower started following $pageName' : 'Someone started following $pageName';
      case 'page_new_post':
        final pageName = (n['metadata'] as Map?)?['page_name']?.toString() ?? 'A page you follow';
        return '$pageName shared a new post';
      case 'page_follow_invite':
        final pageName = (n['metadata'] as Map?)?['page_name']?.toString() ?? 'a page';
        return '$actorName invited you to follow $pageName';
      case 'page_message_received':
        final pageName = (n['metadata'] as Map?)?['page_name']?.toString() ?? 'your page';
        return 'New message for $pageName';
      case 'page_message_reply':
        final pageName = (n['metadata'] as Map?)?['page_name']?.toString() ?? 'A page';
        return '$pageName replied to your message';
      case 'page_review_received':
        final pageName = (n['metadata'] as Map?)?['page_name']?.toString() ?? 'your page';
        final rating = (n['metadata'] as Map?)?['rating'];
        final reviewer = (n['metadata'] as Map?)?['reviewer_username']?.toString();
        final who = reviewer != null ? '@$reviewer' : 'Someone';
        return '$who left a $rating-star review on $pageName';
      case 'page_review_response':
        final pageName = (n['metadata'] as Map?)?['page_name']?.toString() ?? 'A page';
        return '$pageName responded to your review';
      case 'page_new_event':
        final pageName = (n['metadata'] as Map?)?['page_name']?.toString() ?? 'A page you follow';
        final title = (n['metadata'] as Map?)?['title']?.toString() ?? 'a new event';
        return '$pageName scheduled "$title"';
      case 'page_event_reminder':
        final title = (n['metadata'] as Map?)?['title']?.toString() ?? 'An event';
        final pageName = (n['metadata'] as Map?)?['page_name']?.toString();
        return pageName != null ? '"$title" on $pageName starts soon' : '"$title" starts soon';
      case 'page_verification_updated':
        final pageName = (n['metadata'] as Map?)?['page_name']?.toString() ?? 'Your page';
        final status = (n['metadata'] as Map?)?['verification_status']?.toString() ?? 'updated';
        return status == 'verified' ? '$pageName is now verified ✓' : '$pageName\'s verification status is now "$status"';
      case 'post_repost':
        return '$actorName reposted your post';
      case 'poll_vote':
        return '$actorName voted in your poll';
      case 'event_reminder':
        return 'Your event is starting soon';
      case 'scheduled_post_published':
        return 'Your scheduled post was published';
      case 'security_alert':
        final eventType = (n['metadata'] as Map?)?['event_type']?.toString().replaceAll('_', ' ');
        return 'Security alert${eventType != null ? ': $eventType' : ''} on your account';
      case 'login_alert':
        final device = (n['metadata'] as Map?)?['device_label']?.toString() ?? 'a device';
        return 'New sign-in from $device you haven\'t used before';
      case 'moderation_alert':
        final action = (n['metadata'] as Map?)?['action']?.toString().replaceAll('_', ' ');
        return 'Moderation action on your account${action != null ? ': $action' : ''}';
      case 'appeal_update':
        final status = (n['metadata'] as Map?)?['status']?.toString() ?? 'updated';
        return 'Your appeal status changed to "$status"';
      case 'report_update':
        return 'A report you filed has been reviewed';
      case 'admin_broadcast':
        return (n['metadata'] as Map?)?['title']?.toString() ?? 'Announcement from Gather';
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
      case 'community_invite':
        return Icons.mail_outline;
      case 'community_join_request':
        return Icons.person_add_outlined;
      case 'community_join_update':
        return Icons.how_to_reg_outlined;
      case 'community_role_changed':
        return Icons.badge_outlined;
      case 'community_warning':
        return Icons.warning_amber_outlined;
      case 'community_ban':
        return Icons.block_outlined;
      case 'community_announcement':
        return Icons.campaign_outlined;
      case 'community_event_created':
        return Icons.event_outlined;
      case 'page_new_follower':
        return Icons.person_add_alt_1_outlined;
      case 'page_new_post':
        return Icons.storefront_outlined;
      case 'page_follow_invite':
        return Icons.mail_outline;
      case 'page_message_received':
      case 'page_message_reply':
        return Icons.chat_bubble_outline;
      case 'page_review_received':
      case 'page_review_response':
        return Icons.star_outline;
      case 'page_new_event':
        return Icons.event_outlined;
      case 'page_event_reminder':
        return Icons.event_available_outlined;
      case 'page_verification_updated':
        return Icons.verified_outlined;
      case 'post_repost':
        return Icons.repeat_outlined;
      case 'poll_vote':
        return Icons.poll_outlined;
      case 'event_reminder':
        return Icons.event_available_outlined;
      case 'scheduled_post_published':
        return Icons.schedule_send_outlined;
      case 'security_alert':
        return Icons.shield_outlined;
      case 'login_alert':
        return Icons.devices_outlined;
      case 'moderation_alert':
        return Icons.gavel_outlined;
      case 'appeal_update':
        return Icons.rule_outlined;
      case 'report_update':
        return Icons.flag_outlined;
      case 'admin_broadcast':
        return Icons.campaign_outlined;
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
    final type = n['type'] as String?;
    if (postId != null) {
      context.push('/post?id=$postId');
    } else if (type == 'mention' && (n['metadata'] as Map?)?['page_id'] != null) {
      context.push('/page-profile?id=${(n['metadata'] as Map)['page_id']}');
    } else if (type == 'new_follower' && actorId != null) {
      context.push('/user?id=$actorId');
    } else if (type == 'moderation_alert' || type == 'appeal_update') {
      context.push('/my-moderation');
    } else if (type == 'report_update') {
      context.push('/my-legal');
    } else if (type == 'community_post') {
      final communityId = (n['metadata'] as Map?)?['community_id']?.toString();
      if (communityId != null) context.push('/community?id=$communityId');
    } else if (type == 'community_role_changed' ||
        type == 'community_join_update' ||
        type == 'community_warning' ||
        type == 'community_ban' ||
        type == 'community_announcement') {
      final communityId = (n['metadata'] as Map?)?['community_id']?.toString();
      if (communityId != null) context.push('/community?id=$communityId');
    } else if (type == 'community_event_created') {
      final communityId = (n['metadata'] as Map?)?['community_id']?.toString();
      final communityName = (n['metadata'] as Map?)?['community_name']?.toString();
      if (communityId != null) {
        context.push('/community-events?id=$communityId${communityName != null ? '&name=${Uri.encodeComponent(communityName)}' : ''}');
      }
    } else if (type == 'page_new_follower' || type == 'page_new_post' || type == 'page_follow_invite') {
      final pageId = (n['metadata'] as Map?)?['page_id']?.toString();
      if (pageId != null) context.push('/page-profile?id=$pageId');
    } else if (type == 'page_message_received') {
      final pageId = (n['metadata'] as Map?)?['page_id']?.toString();
      if (pageId != null) context.push('/page-inbox?id=$pageId');
    } else if (type == 'page_message_reply') {
      final pageId = (n['metadata'] as Map?)?['page_id']?.toString();
      if (pageId != null) context.push('/page-chat?id=$pageId');
    } else if (type == 'page_review_received' || type == 'page_review_response') {
      final pageId = (n['metadata'] as Map?)?['page_id']?.toString();
      if (pageId != null) context.push('/page-reviews?id=$pageId');
    } else if (type == 'page_new_event' || type == 'page_event_reminder' || type == 'page_verification_updated') {
      final pageId = (n['metadata'] as Map?)?['page_id']?.toString();
      if (pageId != null) context.push('/page-profile?id=$pageId');
    } else if (type == 'scheduled_post_published' && (n['metadata'] as Map?)?['page_id'] != null) {
      context.push('/page-profile?id=${(n['metadata'] as Map)['page_id']}');
    }
    // community_invite, community_join_request: handled entirely by the
    // inline Accept/Decline or Approve/Reject buttons on their own tile —
    // tapping the row elsewhere just marks it read.
    // security_alert, login_alert, admin_broadcast: mark-as-read is enough,
    // there's no dedicated detail screen for these yet.
  }

  @override
  Widget build(BuildContext context) {
    final uid = SupabaseConfig.maybeClient?.auth.currentUser?.id;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (uid != null)
            TextButton(
              onPressed: () async {
                await SupabaseConfig.client.from('notifications').update({'is_read': true}).eq('recipient_id', uid).eq('is_read', false);
                if (mounted) _retry();
              },
              child: const Text('Mark all read'),
            ),
        ],
      ),
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

                      if (n['type'] == 'community_invite') {
                        return _InviteNotificationTile(notification: n, actorName: actorName, avatarUrl: avatarUrl, isRead: isRead);
                      }
                      if (n['type'] == 'community_join_request') {
                        return _JoinRequestNotificationTile(notification: n, isRead: isRead);
                      }

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

/// A community_invite notification row with inline Accept/Decline instead
/// of the plain tap-through the other notification types get — accepting
/// or declining is the entire point of this notification, so it shouldn't
/// require a second screen.
class _InviteNotificationTile extends StatefulWidget {
  const _InviteNotificationTile({
    required this.notification,
    required this.actorName,
    required this.avatarUrl,
    required this.isRead,
  });
  final Map<String, dynamic> notification;
  final String actorName;
  final String? avatarUrl;
  final bool isRead;

  @override
  State<_InviteNotificationTile> createState() => _InviteNotificationTileState();
}

class _InviteNotificationTileState extends State<_InviteNotificationTile> {
  final repo = CommunityRepository();
  bool _busy = false;
  String? _resolution; // 'accepted' | 'declined' | 'error', so the tile updates in place without a full reload

  Future<void> _respond(bool accept) async {
    final metadata = widget.notification['metadata'] as Map? ?? const {};
    final inviteId = metadata['invite_id']?.toString();
    if (inviteId == null || _busy) return;
    setState(() => _busy = true);
    try {
      if (accept) {
        await repo.acceptInvite(inviteId);
      } else {
        await repo.revokeInvite(inviteId);
      }
      await SupabaseConfig.client.from('notifications').update({'is_read': true}).eq('id', widget.notification['id']);
      if (mounted) setState(() => _resolution = accept ? 'accepted' : 'declined');
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not respond to invite: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final metadata = widget.notification['metadata'] as Map? ?? const {};
    final communityName = metadata['community_name']?.toString() ?? 'a community';
    final communityId = metadata['community_id']?.toString();

    return ListTile(
      tileColor: widget.isRead ? null : Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.25),
      leading: CircleAvatar(
        backgroundImage: widget.avatarUrl != null && widget.avatarUrl!.isNotEmpty ? NetworkImage(widget.avatarUrl!) : null,
        child: widget.avatarUrl == null || widget.avatarUrl!.isEmpty ? const Icon(Icons.mail_outline) : null,
      ),
      title: Text('${widget.actorName} invited you to join $communityName'),
      subtitle: _busy
          ? const LinearProgressIndicator()
          : switch (_resolution) {
              'accepted' => TextButton(
                  onPressed: communityId == null ? null : () => GoRouter.of(context).push('/community?id=$communityId'),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
                  child: const Text('Joined — view community'),
                ),
              'declined' => const Text('Invite declined'),
              _ => Row(
                  children: [
                    TextButton(onPressed: () => _respond(true), child: const Text('Accept')),
                    TextButton(onPressed: () => _respond(false), child: const Text('Decline')),
                  ],
                ),
            },
    );
  }
}

/// A community_join_request notification row with inline Approve/Reject —
/// same rationale as [_InviteNotificationTile]: responding IS the point of
/// this notification, so it shouldn't need a second screen.
class _JoinRequestNotificationTile extends StatefulWidget {
  const _JoinRequestNotificationTile({required this.notification, required this.isRead});
  final Map<String, dynamic> notification;
  final bool isRead;

  @override
  State<_JoinRequestNotificationTile> createState() => _JoinRequestNotificationTileState();
}

class _JoinRequestNotificationTileState extends State<_JoinRequestNotificationTile> {
  final repo = CommunityRepository();
  bool _busy = false;
  String? _resolution; // 'approved' | 'rejected'

  Future<void> _decide(bool approve) async {
    final metadata = widget.notification['metadata'] as Map? ?? const {};
    final requestId = metadata['request_id']?.toString();
    if (requestId == null || _busy) return;
    setState(() => _busy = true);
    try {
      await repo.decideJoinRequest(requestId, approve);
      await SupabaseConfig.client.from('notifications').update({'is_read': true}).eq('id', widget.notification['id']);
      if (mounted) setState(() => _resolution = approve ? 'approved' : 'rejected');
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not respond to request: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final metadata = widget.notification['metadata'] as Map? ?? const {};
    final requester = metadata['requester_username']?.toString() ?? 'Someone';
    final communityName = metadata['community_name']?.toString() ?? 'your community';

    return ListTile(
      tileColor: widget.isRead ? null : Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.25),
      leading: const CircleAvatar(child: Icon(Icons.person_add_outlined)),
      title: Text('@$requester wants to join $communityName'),
      subtitle: _busy
          ? const LinearProgressIndicator()
          : switch (_resolution) {
              'approved' => const Text('Approved'),
              'rejected' => const Text('Rejected'),
              _ => Row(
                  children: [
                    TextButton(onPressed: () => _decide(true), child: const Text('Approve')),
                    TextButton(onPressed: () => _decide(false), child: const Text('Reject')),
                  ],
                ),
            },
    );
  }
}
