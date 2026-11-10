/// Models for 1:1 direct messages (Phase 11). All fields mirror the RPC
/// output of migration 124.
library;

enum DmKind { text, image, video, file, voice }

DmKind dmKindFromString(String? s) => DmKind.values.firstWhere((k) => k.name == s, orElse: () => DmKind.text);

enum DmStatus { sending, sent, delivered, read }

class DmReaction {
  const DmReaction({required this.emoji, required this.count, required this.mine});
  final String emoji;
  final int count;
  final bool mine;

  factory DmReaction.fromMap(Map<String, dynamic> m) => DmReaction(
        emoji: m['emoji'] as String,
        count: (m['count'] as num).toInt(),
        mine: m['mine'] == true,
      );
}

class DmReplyPreview {
  const DmReplyPreview({
    required this.id,
    required this.senderId,
    required this.kind,
    this.body,
    this.ciphertext,
    this.nonce,
    required this.encVersion,
    required this.deleted,
  });
  final String id;
  final String senderId;
  final DmKind kind;
  final String? body;
  final String? ciphertext;
  final String? nonce;
  final int encVersion;
  final bool deleted;

  factory DmReplyPreview.fromMap(Map<String, dynamic> m) => DmReplyPreview(
        id: m['id'].toString(),
        senderId: m['sender_id'].toString(),
        kind: dmKindFromString(m['kind'] as String?),
        body: m['body'] as String?,
        ciphertext: m['ciphertext'] as String?,
        nonce: m['nonce'] as String?,
        encVersion: (m['enc_version'] as num?)?.toInt() ?? 0,
        deleted: m['deleted'] == true,
      );
}

class DmMessage {
  const DmMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.kind,
    this.body,
    this.ciphertext,
    this.nonce,
    required this.encVersion,
    this.replyToId,
    this.replyTo,
    required this.isForwarded,
    this.mediaPath,
    this.mediaName,
    this.mediaSizeBytes,
    this.mediaMime,
    this.durationMs,
    required this.createdAt,
    this.deletedAt,
    this.reactions = const [],
  });

  final String id;
  final String conversationId;
  final String senderId;
  final DmKind kind;
  final String? body; // plaintext, only when encVersion == 0
  final String? ciphertext;
  final String? nonce;
  final int encVersion;
  final String? replyToId;
  final DmReplyPreview? replyTo;
  final bool isForwarded;
  final String? mediaPath;
  final String? mediaName;
  final int? mediaSizeBytes;
  final String? mediaMime;
  final int? durationMs;
  final DateTime createdAt;
  final DateTime? deletedAt;
  final List<DmReaction> reactions;

  bool get isDeleted => deletedAt != null;
  bool get isEncrypted => encVersion == 1;

  factory DmMessage.fromMap(Map<String, dynamic> m) => DmMessage(
        id: m['id'].toString(),
        conversationId: m['conversation_id'].toString(),
        senderId: m['sender_id'].toString(),
        kind: dmKindFromString(m['kind'] as String?),
        body: m['body'] as String?,
        ciphertext: m['ciphertext'] as String?,
        nonce: m['nonce'] as String?,
        encVersion: (m['enc_version'] as num?)?.toInt() ?? 0,
        replyToId: m['reply_to_id']?.toString(),
        replyTo: m['reply_to'] is Map ? DmReplyPreview.fromMap(Map<String, dynamic>.from(m['reply_to'] as Map)) : null,
        isForwarded: m['is_forwarded'] == true,
        mediaPath: m['media_path'] as String?,
        mediaName: m['media_name'] as String?,
        mediaSizeBytes: (m['media_size_bytes'] as num?)?.toInt(),
        mediaMime: m['media_mime'] as String?,
        durationMs: (m['duration_ms'] as num?)?.toInt(),
        createdAt: DateTime.parse(m['created_at'] as String),
        deletedAt: m['deleted_at'] == null ? null : DateTime.parse(m['deleted_at'] as String),
        reactions: (m['reactions'] as List? ?? const [])
            .map((e) => DmReaction.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );

  /// Delivery state of one of MY messages, from the other member's cursors.
  DmStatus statusFor({DateTime? otherLastDeliveredAt, DateTime? otherLastReadAt}) {
    if (otherLastReadAt != null && !createdAt.isAfter(otherLastReadAt)) return DmStatus.read;
    if (otherLastDeliveredAt != null && !createdAt.isAfter(otherLastDeliveredAt)) return DmStatus.delivered;
    return DmStatus.sent;
  }
}

class DmConversation {
  const DmConversation({
    required this.id,
    required this.otherUserId,
    required this.otherUsername,
    this.otherAvatarUrl,
    required this.lastMessageAt,
    this.lastKind,
    this.lastSenderId,
    this.lastBody,
    this.lastCiphertext,
    this.lastNonce,
    this.lastEncVersion = 0,
    this.lastDeleted = false,
    required this.unreadCount,
    required this.isPinned,
    required this.isArchived,
    this.mutedUntil,
    this.otherLastReadAt,
  });

  final String id;
  final String otherUserId;
  final String otherUsername;
  final String? otherAvatarUrl;
  final DateTime lastMessageAt;
  final DmKind? lastKind;
  final String? lastSenderId;
  final String? lastBody;
  final String? lastCiphertext;
  final String? lastNonce;
  final int lastEncVersion;
  final bool lastDeleted;
  final int unreadCount;
  final bool isPinned;
  final bool isArchived;
  final DateTime? mutedUntil;
  final DateTime? otherLastReadAt;

  bool isMutedAt(DateTime now) => mutedUntil != null && mutedUntil!.isAfter(now);

  factory DmConversation.fromMap(Map<String, dynamic> m) => DmConversation(
        id: m['conversation_id'].toString(),
        otherUserId: m['other_user_id'].toString(),
        otherUsername: (m['other_username'] as String?) ?? 'user',
        otherAvatarUrl: m['other_avatar_url'] as String?,
        lastMessageAt: DateTime.parse(m['last_message_at'] as String),
        lastKind: m['last_message_kind'] == null ? null : dmKindFromString(m['last_message_kind'] as String?),
        lastSenderId: m['last_message_sender_id']?.toString(),
        lastBody: m['last_message_body'] as String?,
        lastCiphertext: m['last_message_ciphertext'] as String?,
        lastNonce: m['last_message_nonce'] as String?,
        lastEncVersion: (m['last_message_enc_version'] as num?)?.toInt() ?? 0,
        lastDeleted: m['last_message_deleted'] == true,
        unreadCount: (m['unread_count'] as num?)?.toInt() ?? 0,
        isPinned: m['is_pinned'] == true,
        isArchived: m['is_archived'] == true,
        mutedUntil: m['muted_until'] == null ? null : DateTime.parse(m['muted_until'] as String),
        otherLastReadAt: m['other_last_read_at'] == null ? null : DateTime.parse(m['other_last_read_at'] as String),
      );
}

/// Human-readable preview for a non-text message, or null for text.
String? dmKindLabel(DmKind kind) {
  switch (kind) {
    case DmKind.image:
      return 'Photo';
    case DmKind.video:
      return 'Video';
    case DmKind.file:
      return 'File';
    case DmKind.voice:
      return 'Voice message';
    case DmKind.text:
      return null;
  }
}

/// Maps a Postgres/RPC error to a message safe to show the user.
String dmErrorMessage(Object error) {
  final text = error.toString();
  if (text.contains('dm_blocked')) return "You can't message this person.";
  if (text.contains('dm_not_allowed')) return "This person isn't accepting messages from you.";
  if (text.contains('dm_rate_limited')) return "You're sending messages too fast. Try again in a minute.";
  if (text.contains('dm_invalid_media')) return 'That attachment could not be sent.';
  if (text.contains('dm_not_member')) return 'This conversation is not available.';
  return 'Something went wrong. Please try again.';
}
