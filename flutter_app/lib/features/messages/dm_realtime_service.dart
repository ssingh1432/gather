import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';

/// Realtime for one open DM: Postgres Changes for messages, read/delivered
/// cursors and reactions, plus a Broadcast channel for typing indicators
/// (ephemeral, never written to the database).
class DmRealtimeService {
  DmRealtimeService(this.conversationId);

  final String conversationId;

  final _messages = StreamController<Map<String, dynamic>>.broadcast();
  final _memberState = StreamController<Map<String, dynamic>>.broadcast();
  final _reactions = StreamController<void>.broadcast();
  final _typing = StreamController<({String userId, bool isTyping})>.broadcast();
  RealtimeChannel? _channel;

  /// Inserts and updates (edits/tombstones) on dm_messages for this chat.
  Stream<Map<String, dynamic>> get messages => _messages.stream;

  /// Updates to dm_conversation_members (the other side's read/delivered).
  Stream<Map<String, dynamic>> get memberState => _memberState.stream;
  Stream<void> get reactions => _reactions.stream;
  Stream<({String userId, bool isTyping})> get typing => _typing.stream;

  void subscribe() {
    final client = SupabaseConfig.maybeClient;
    if (client == null) return;
    final filter = PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'conversation_id', value: conversationId);

    _channel = client
        .channel('dm:$conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'dm_messages',
          filter: filter,
          callback: (p) {
            if (p.eventType == PostgresChangeEvent.delete) return;
            _messages.add(p.newRecord);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'dm_conversation_members',
          filter: filter,
          callback: (p) => _memberState.add(p.newRecord),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'dm_message_reactions',
          callback: (_) => _reactions.add(null),
        )
        .onBroadcast(
          event: 'typing',
          callback: (payload) {
            final userId = payload['user_id'] as String?;
            if (userId == null) return;
            _typing.add((userId: userId, isTyping: payload['is_typing'] == true));
          },
        )
        .subscribe();
  }

  void sendTyping({required String userId, required bool isTyping}) {
    _channel?.sendBroadcastMessage(event: 'typing', payload: {'user_id': userId, 'is_typing': isTyping});
  }

  void dispose() {
    final channel = _channel;
    if (channel != null) SupabaseConfig.maybeClient?.removeChannel(channel);
    _messages.close();
    _memberState.close();
    _reactions.close();
    _typing.close();
  }
}

/// Inbox-level realtime: fires whenever any message visible to me is
/// inserted/updated (RLS limits events to my conversations).
class DmInboxRealtime {
  DmInboxRealtime(this.userId);
  final String userId;

  final _events = StreamController<Map<String, dynamic>>.broadcast();
  RealtimeChannel? _channel;

  Stream<Map<String, dynamic>> get events => _events.stream;

  void subscribe() {
    final client = SupabaseConfig.maybeClient;
    if (client == null) return;
    _channel = client
        .channel('dm-inbox:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'dm_messages',
          callback: (p) {
            if (p.eventType == PostgresChangeEvent.delete) return;
            _events.add(p.newRecord);
          },
        )
        .subscribe();
  }

  void dispose() {
    final channel = _channel;
    if (channel != null) SupabaseConfig.maybeClient?.removeChannel(channel);
    _events.close();
  }
}
