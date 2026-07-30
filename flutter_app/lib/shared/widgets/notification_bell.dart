import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase_client.dart';
import '../providers/app_providers.dart';

/// Bell icon for the top bar: filled + numbered badge while there are
/// unread notifications, plain outline with no badge once everything's
/// been seen. The count comes from [unreadNotificationCountProvider],
/// which stays live via Realtime, so this updates the moment a new
/// notification arrives or the person reads one — no manual refresh.
/// Hidden entirely for signed-out visitors, who have nothing to see here.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (SupabaseConfig.currentUserId == null) return const SizedBox.shrink();

    final unread = ref.watch(unreadNotificationCountProvider).asData?.value ?? 0;
    final hasUnread = unread > 0;

    return IconButton(
      tooltip: hasUnread ? '$unread unread notification${unread == 1 ? '' : 's'}' : 'Notifications',
      onPressed: () => context.push('/notifications'),
      icon: Badge(
        isLabelVisible: hasUnread,
        label: Text(unread > 99 ? '99+' : '$unread'),
        child: Icon(hasUnread ? Icons.notifications : Icons.notifications_none),
      ),
    );
  }
}
