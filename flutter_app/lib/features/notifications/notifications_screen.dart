import 'package:flutter/material.dart';

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
    final data = await SupabaseConfig.client.from('notifications').select().eq('recipient_id', uid).order('created_at', ascending: false);
    return data as List<dynamic>;
  }

  void _retry() => setState(() => _future = _load());

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
                return ListView(
                  children: notifications
                      .map(
                        (e) => ListTile(
                          title: Text(e['type'].toString()),
                          trailing: TextButton(
                            onPressed: () async {
                              await SupabaseConfig.client.from('notifications').update({'is_read': true}).eq('id', e['id']);
                              _retry();
                            },
                            child: const Text('Mark read'),
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
    );
  }
}
