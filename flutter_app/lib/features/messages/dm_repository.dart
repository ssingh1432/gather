import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';
import 'dm_models.dart';

/// Data access for 1:1 DMs. All writes go through SECURITY DEFINER RPCs
/// (migration 124); the tables themselves are read-only for clients.
class DmRepository {
  static const String bucket = 'dm-media';
  static const int maxMediaBytes = 25 * 1024 * 1024; // matches bucket limit

  SupabaseClient get _c => SupabaseConfig.client;

  Future<String> getOrCreateConversation(String otherUserId) async {
    final id = await _c.rpc('get_or_create_dm_conversation', params: {'p_other': otherUserId});
    return id.toString();
  }

  Future<List<DmConversation>> listConversations({bool archived = false}) async {
    final rows = await _c.rpc('list_dm_conversations', params: {'p_archived': archived}) as List;
    return rows.map((r) => DmConversation.fromMap(Map<String, dynamic>.from(r as Map))).toList();
  }

  Future<List<DmMessage>> fetchMessages(String conversationId, {DateTime? before, int limit = 40}) async {
    final rows = await _c.rpc('get_dm_messages', params: {
      'p_conversation': conversationId,
      'p_before': before?.toUtc().toIso8601String(),
      'p_limit': limit,
    }) as List;
    return rows.map((r) => DmMessage.fromMap(Map<String, dynamic>.from(r as Map))).toList();
  }

  /// The other member's read/delivered cursors, for tick rendering.
  Future<({DateTime? lastReadAt, DateTime? lastDeliveredAt})> otherMemberState(String conversationId, String myId) async {
    final row = await _c
        .from('dm_conversation_members')
        .select('last_read_at, last_delivered_at')
        .eq('conversation_id', conversationId)
        .neq('user_id', myId)
        .maybeSingle();
    if (row == null) return (lastReadAt: null, lastDeliveredAt: null);
    return (
      lastReadAt: row['last_read_at'] == null ? null : DateTime.parse(row['last_read_at'] as String),
      lastDeliveredAt: row['last_delivered_at'] == null ? null : DateTime.parse(row['last_delivered_at'] as String),
    );
  }

  Future<DmMessage> send({
    required String conversationId,
    DmKind kind = DmKind.text,
    String? body,
    String? ciphertext,
    String? nonce,
    int encVersion = 0,
    String? replyToId,
    String? mediaPath,
    String? mediaName,
    int? mediaSizeBytes,
    String? mediaMime,
    int? durationMs,
    bool isForwarded = false,
  }) async {
    final row = await _c.rpc('send_dm_message', params: {
      'p_conversation': conversationId,
      'p_kind': kind.name,
      'p_body': body,
      'p_ciphertext': ciphertext,
      'p_nonce': nonce,
      'p_enc_version': encVersion,
      'p_reply_to': replyToId,
      'p_media_path': mediaPath,
      'p_media_name': mediaName,
      'p_media_size_bytes': mediaSizeBytes,
      'p_media_mime': mediaMime,
      'p_duration_ms': durationMs,
      'p_is_forwarded': isForwarded,
    });
    return DmMessage.fromMap(Map<String, dynamic>.from(row as Map));
  }

  Future<void> markRead(String conversationId) => _c.rpc('mark_dm_read', params: {'p_conversation': conversationId});
  Future<void> markDelivered(String conversationId) => _c.rpc('mark_dm_delivered', params: {'p_conversation': conversationId});

  Future<void> deleteForEveryone(String messageId) async {
    final path = await _c.rpc('delete_dm_message_for_everyone', params: {'p_message': messageId});
    if (path is String && path.isNotEmpty) {
      try {
        await _c.storage.from(bucket).remove([path]);
      } catch (_) {
        // Message row is already tombstoned and media_path cleared; an
        // orphaned file is a cleanup concern, not a user-facing error.
      }
    }
  }

  Future<void> hideForMe(String messageId) => _c.rpc('hide_dm_message_for_me', params: {'p_message': messageId});
  Future<void> clearForMe(String conversationId) => _c.rpc('clear_dm_conversation_for_me', params: {'p_conversation': conversationId});

  Future<bool> toggleReaction(String messageId, String emoji) async {
    final r = await _c.rpc('toggle_dm_reaction', params: {'p_message': messageId, 'p_emoji': emoji});
    return r == true;
  }

  Future<void> setFlags(String conversationId, {bool? pinned, bool? archived, DateTime? mutedUntil, bool unmute = false}) {
    return _c.rpc('set_dm_conversation_flags', params: {
      'p_conversation': conversationId,
      'p_pinned': pinned,
      'p_archived': archived,
      'p_muted_until': mutedUntil?.toUtc().toIso8601String(),
      'p_unmute': unmute,
    });
  }

  // ---- media -------------------------------------------------------------

  Future<String> uploadMedia({
    required String conversationId,
    required String userId,
    required Uint8List bytes,
    required String fileName,
    required String mime,
  }) async {
    if (bytes.length > maxMediaBytes) {
      throw StateError('Attachments must be 25 MB or smaller.');
    }
    final safe = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path = '$conversationId/$userId/${DateTime.now().microsecondsSinceEpoch}_$safe';
    await _c.storage.from(bucket).uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mime, upsert: false));
    return path;
  }

  /// Copies an existing attachment into another conversation's folder (used
  /// by "forward"), since access is scoped per conversation.
  Future<String> copyMedia({required String fromPath, required String toConversationId, required String userId}) async {
    final name = fromPath.split('/').last;
    final to = '$toConversationId/$userId/${DateTime.now().microsecondsSinceEpoch}_$name';
    await _c.storage.from(bucket).copy(fromPath, to);
    return to;
  }

  Future<String> signedUrl(String path) => _c.storage.from(bucket).createSignedUrl(path, 3600);

  // ---- end-to-end encryption keys ---------------------------------------

  /// Registers [publicKey] unless one already exists; returns the key the
  /// server holds for this account.
  Future<String> registerPublicKey(String publicKey, {bool replace = false}) async {
    final r = await _c.rpc('register_dm_public_key', params: {'p_public_key': publicKey, 'p_replace': replace});
    return r.toString();
  }

  Future<String?> publicKeyOf(String userId) async {
    final r = await _c.rpc('get_dm_public_key', params: {'p_user': userId});
    return r is String ? r : null;
  }

  // ---- privacy -----------------------------------------------------------

  Future<String> getMyDmPrivacy(String userId) async {
    final row = await _c.from('users').select('dm_privacy').eq('id', userId).maybeSingle();
    return (row?['dm_privacy'] as String?) ?? 'everyone';
  }

  Future<void> setMyDmPrivacy(String userId, String value) => _c.from('users').update({'dm_privacy': value}).eq('id', userId);
}
