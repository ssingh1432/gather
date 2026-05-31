import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';

/// Lightweight Supabase-native analytics.
///
/// Calls are intentionally fire-and-forget so product flows never block on
/// analytics writes. Server-side RPCs stamp UTC timestamps and authenticated
/// user IDs, preventing clients from spoofing ownership.
class AnalyticsService {
  AnalyticsService._();

  static final AnalyticsService instance = AnalyticsService._();

  SupabaseClient? get _client => SupabaseConfig.maybeClient;

  void userSignedUp() => _track('user_signed_up');
  void userLoggedIn() => _track('user_logged_in');
  void postCreated({required String postId, String? communityId}) =>
      _track('post_created', postId: postId, communityId: communityId);
  void commentCreated({required String postId}) => _track('comment_created', postId: postId);
  void communityJoined({required String communityId}) => _track('community_joined', communityId: communityId);

  void dailyActiveUser() {
    final client = _client;
    if (client?.auth.currentUser == null) return;
    unawaited(_safeRpc(() => client!.rpc('track_daily_active_user')));
  }

  void _track(String eventName, {String? postId, String? communityId}) {
    final client = _client;
    if (client?.auth.currentUser == null) return;
    unawaited(_safeRpc(() => client!.rpc('track_analytics_event', params: {
          'event_name': eventName,
          'post_id': postId,
          'community_id': communityId,
          'metadata': <String, dynamic>{},
        })));
  }

  Future<void> _safeRpc(Future<dynamic> Function() request) async {
    try {
      await request();
    } catch (error, stackTrace) {
      debugPrint('Analytics event dropped: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
