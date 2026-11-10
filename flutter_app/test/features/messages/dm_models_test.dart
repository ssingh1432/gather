import 'package:flutter_test/flutter_test.dart';
import 'package:gather_app/features/messages/dm_models.dart';

Map<String, dynamic> _row({String created = '2026-01-01T10:00:00Z'}) => {
      'id': 'm1',
      'conversation_id': 'c1',
      'sender_id': 'u1',
      'kind': 'voice',
      'enc_version': 0,
      'is_forwarded': true,
      'media_path': 'c1/u1/a.m4a',
      'duration_ms': 4200,
      'created_at': created,
      'reactions': [
        {'emoji': '👍', 'count': 2, 'mine': true}
      ],
      'reply_to': {'id': 'm0', 'sender_id': 'u2', 'kind': 'text', 'body': 'hi', 'enc_version': 0, 'deleted': false},
    };

void main() {
  test('DmMessage.fromMap parses media, reactions and reply preview', () {
    final m = DmMessage.fromMap(_row());
    expect(m.kind, DmKind.voice);
    expect(m.durationMs, 4200);
    expect(m.isForwarded, isTrue);
    expect(m.reactions.single.mine, isTrue);
    expect(m.replyTo?.body, 'hi');
    expect(m.isDeleted, isFalse);
  });

  test('statusFor derives sent/delivered/read from the other member cursors', () {
    final m = DmMessage.fromMap(_row());
    final t = DateTime.parse('2026-01-01T10:00:00Z');
    expect(m.statusFor(), DmStatus.sent);
    expect(m.statusFor(otherLastDeliveredAt: t), DmStatus.delivered);
    expect(m.statusFor(otherLastDeliveredAt: t, otherLastReadAt: t), DmStatus.read);
    expect(m.statusFor(otherLastReadAt: t.subtract(const Duration(seconds: 1))), DmStatus.sent);
  });

  test('dmErrorMessage maps server error codes to friendly text', () {
    expect(dmErrorMessage('PostgrestException: dm_blocked'), contains("can't message"));
    expect(dmErrorMessage('dm_rate_limited'), contains('too fast'));
    expect(dmErrorMessage('boom'), contains('Something went wrong'));
  });

  test('DmConversation mute check', () {
    final c = DmConversation.fromMap({
      'conversation_id': 'c1', 'other_user_id': 'u2', 'other_username': 'sita',
      'last_message_at': '2026-01-01T10:00:00Z', 'unread_count': 3,
      'is_pinned': true, 'is_archived': false, 'muted_until': '2099-01-01T00:00:00Z',
    });
    expect(c.isMutedAt(DateTime.now()), isTrue);
    expect(c.unreadCount, 3);
    expect(c.lastKind, isNull);
  });
}
