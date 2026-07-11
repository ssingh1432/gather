import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';

enum FeedRealtimeEventType { newPost, likeCountDelta, commentCountDelta, shareCountDelta }

/// A single realtime change relevant to the home feed. For the count-delta
/// event types, [postId] + [delta] tell the listener exactly how to patch
/// its in-memory post without doing a full refetch.
class FeedRealtimeEvent {
  const FeedRealtimeEvent(this.type, {this.postId, this.delta = 0, this.authorId});

  final FeedRealtimeEventType type;
  final String? postId;
  final int delta;
  final String? authorId;
}

/// Subscribes to Postgres Changes on `posts`, `post_likes`, `post_comments`,
/// and `post_shares` (all enabled for Realtime + `REPLICA IDENTITY FULL` in
/// migration 008) and turns them into a single stream of [FeedRealtimeEvent]s
/// the home feed can react to instantly, with no polling or manual
/// pull-to-refresh required.
///
/// One instance per screen that needs it — call [dispose] when the screen
/// is torn down so the channel is unsubscribed and the stream closed.
class FeedRealtimeService {
  final _controller = StreamController<FeedRealtimeEvent>.broadcast();
  RealtimeChannel? _channel;

  Stream<FeedRealtimeEvent> subscribe() {
    final client = SupabaseConfig.maybeClient;
    if (client == null) return _controller.stream;

    _channel = client
        .channel('public:home-feed-realtime')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'posts',
          callback: (payload) {
            final authorId = payload.newRecord['author_id'] as String?;
            _controller.add(FeedRealtimeEvent(FeedRealtimeEventType.newPost, authorId: authorId));
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'post_likes',
          callback: (payload) => _emitCountDelta(payload, FeedRealtimeEventType.likeCountDelta),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'post_comments',
          callback: (payload) => _emitCountDelta(payload, FeedRealtimeEventType.commentCountDelta),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'post_shares',
          callback: (payload) {
            final postId = payload.newRecord['post_id'] as String?;
            if (postId != null) _controller.add(FeedRealtimeEvent(FeedRealtimeEventType.shareCountDelta, postId: postId, delta: 1));
          },
        )
        .subscribe();

    return _controller.stream;
  }

  void _emitCountDelta(PostgresChangePayload payload, FeedRealtimeEventType type) {
    final isInsert = payload.eventType == PostgresChangeEvent.insert;
    final isDelete = payload.eventType == PostgresChangeEvent.delete;
    if (!isInsert && !isDelete) return;

    final record = isInsert ? payload.newRecord : payload.oldRecord;
    final postId = record['post_id'] as String?;
    if (postId == null) return;

    _controller.add(FeedRealtimeEvent(type, postId: postId, delta: isInsert ? 1 : -1));
  }

  void dispose() {
    final channel = _channel;
    if (channel != null) SupabaseConfig.maybeClient?.removeChannel(channel);
    _controller.close();
  }
}
