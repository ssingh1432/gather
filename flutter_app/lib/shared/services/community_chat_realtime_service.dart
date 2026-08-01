import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';

enum CommunityChatEventType { messageInsert, messageUpdate, mediaInsert }

class CommunityChatRealtimeEvent {
  const CommunityChatRealtimeEvent(this.type, {this.messageId, this.record});

  final CommunityChatEventType type;
  final String? messageId;
  final Map<String, dynamic>? record;
}

/// Who is currently typing, from the ephemeral typing-indicator broadcast.
class TypingSignal {
  const TypingSignal({required this.userId, required this.username, required this.isTyping});

  final String userId;
  final String username;
  final bool isTyping;
}

/// Realtime for a single community's chat: Postgres Changes on
/// `community_chat_messages` / `community_chat_message_media` (migration
/// 059, both enabled for Realtime + `REPLICA IDENTITY FULL`) for actual
/// message data, plus a Broadcast channel for typing indicators.
///
/// Typing indicators are intentionally NOT written to the database — they
/// are high-frequency, disposable UI signals, and persisting them would
/// mean a write on every keystroke pause for something nobody needs to
/// query later. Supabase Realtime Broadcast delivers them client-to-client
/// through the same channel without touching Postgres at all.
///
/// One instance per open chat screen — call [dispose] when the screen is
/// torn down.
class CommunityChatRealtimeService {
  CommunityChatRealtimeService(this.communityId);

  final String communityId;

  final _messagesController = StreamController<CommunityChatRealtimeEvent>.broadcast();
  final _typingController = StreamController<TypingSignal>.broadcast();
  RealtimeChannel? _channel;

  Stream<CommunityChatRealtimeEvent> get messages => _messagesController.stream;
  Stream<TypingSignal> get typing => _typingController.stream;

  void subscribe() {
    final client = SupabaseConfig.maybeClient;
    if (client == null) return;

    _channel = client
        .channel('public:community-chat:$communityId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'community_chat_messages',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'community_id', value: communityId),
          callback: (payload) {
            _messagesController.add(CommunityChatRealtimeEvent(
              CommunityChatEventType.messageInsert,
              messageId: payload.newRecord['id'] as String?,
              record: payload.newRecord,
            ));
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'community_chat_messages',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'community_id', value: communityId),
          callback: (payload) {
            _messagesController.add(CommunityChatRealtimeEvent(
              CommunityChatEventType.messageUpdate,
              messageId: payload.newRecord['id'] as String?,
              record: payload.newRecord,
            ));
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'community_chat_message_media',
          callback: (payload) {
            _messagesController.add(CommunityChatRealtimeEvent(
              CommunityChatEventType.mediaInsert,
              messageId: payload.newRecord['message_id'] as String?,
              record: payload.newRecord,
            ));
          },
        )
        .onBroadcast(
          event: 'typing',
          callback: (payload) {
            final userId = payload['user_id'] as String?;
            final username = payload['username'] as String?;
            final isTyping = payload['is_typing'] as bool? ?? false;
            if (userId == null || username == null) return;
            _typingController.add(TypingSignal(userId: userId, username: username, isTyping: isTyping));
          },
        )
        .subscribe();
  }

  /// Fires a one-off typing/stopped-typing broadcast. Callers should debounce
  /// this themselves (e.g. on text-field change, then a "stopped" after a
  /// couple seconds of no input) rather than firing on every keystroke.
  void sendTyping({required String userId, required String username, required bool isTyping}) {
    _channel?.sendBroadcastMessage(
      event: 'typing',
      payload: {'user_id': userId, 'username': username, 'is_typing': isTyping},
    );
  }

  void dispose() {
    final channel = _channel;
    if (channel != null) SupabaseConfig.maybeClient?.removeChannel(channel);
    _messagesController.close();
    _typingController.close();
  }
}
