import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';
import 'beta_context_service.dart';

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
  void postCreated({required String postId, String? communityId}) {
    _track('post_created', postId: postId, communityId: communityId);
    firstActionCompleted(action: 'post_created');
  }

  void commentCreated({required String postId}) {
    _track('comment_created', postId: postId);
    firstActionCompleted(action: 'comment_created');
  }

  void communityJoined({required String communityId}) {
    _track('community_joined', communityId: communityId);
    firstActionCompleted(action: 'community_joined');
  }

  // Phase 4 beta-only validation funnel signals.
  void signupStarted() => _track('signup_started');
  void firstActionCompleted({required String action}) => _track('first_action_completed', metadata: {'action': action});
  void feedViewed({required int visiblePostCount}) => _track('feed_viewed', metadata: {'visible_post_count': visiblePostCount});
  void feedNoInteraction({required int visiblePostCount}) => _track('feed_no_interaction', metadata: {'visible_post_count': visiblePostCount});
  void postCreationStarted({String? communityId}) => _track('post_creation_started', communityId: communityId);
  void postCreationAbandoned({String? communityId, required bool hadText, required bool hadImage}) => _track(
        'post_creation_abandoned',
        communityId: communityId,
        metadata: {'had_text': hadText, 'had_image': hadImage},
      );

  void dailyActiveUser() {
    final client = _client;
    if (client?.auth.currentUser == null) return;
    unawaited(_safeRpc(() => client!.rpc('track_daily_active_user')));
  }

  void _track(String eventName, {String? postId, String? communityId, Map<String, dynamic>? metadata}) {
    final client = _client;
    if (client?.auth.currentUser == null) return;
    final betaMetadata = <String, dynamic>{
      if (metadata != null) ...metadata,
      'session_id': BetaContextService.instance.sessionId,
      'platform': BetaContextService.instance.platform,
    };
    unawaited(_safeRpc(() => client!.rpc('track_analytics_event', params: {
          'event_name': eventName,
          'post_id': postId,
          'community_id': communityId,
          'metadata': betaMetadata,
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
