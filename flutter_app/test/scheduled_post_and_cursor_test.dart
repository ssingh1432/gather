import 'package:flutter_test/flutter_test.dart';
import 'package:gather_app/shared/models/models.dart';

void main() {
  group('ScheduledPostModel.fromMap', () {
    test('parses a pending scheduled post with media', () {
      final model = ScheduledPostModel.fromMap({
        'id': 'sp1',
        'user_id': 'u1',
        'community_id': null,
        'text_content': 'hello later',
        'media': [
          {'media_url': 'https://example.com/a.png', 'thumbnail_url': 'https://example.com/a_thumb.png', 'media_type': 'image'}
        ],
        'tags': ['nepal', 'travel'],
        'visibility': 'followers',
        'content_type': 'text',
        'scheduled_at': '2026-08-01T09:00:00Z',
        'client_timezone': 'Asia/Kathmandu',
        'status': 'pending',
      });

      expect(model.id, 'sp1');
      expect(model.userId, 'u1');
      expect(model.textContent, 'hello later');
      expect(model.visibility, 'followers');
      expect(model.status, 'pending');
      expect(model.isPending, isTrue);
      expect(model.tags, ['nepal', 'travel']);
      expect(model.imageUrl, 'https://example.com/a.png');
      expect(model.clientTimezone, 'Asia/Kathmandu');
    });

    test('defaults gracefully when optional fields are absent', () {
      final model = ScheduledPostModel.fromMap({
        'id': 'sp2',
        'user_id': 'u2',
        'text_content': '',
        'scheduled_at': '2026-08-01T09:00:00Z',
        'status': 'published',
      });

      expect(model.visibility, 'public');
      expect(model.contentType, 'text');
      expect(model.tags, isEmpty);
      expect(model.media, isEmpty);
      expect(model.imageUrl, isNull);
      expect(model.isPending, isFalse);
      expect(model.clientTimezone, 'Asia/Kathmandu');
    });

    test('exposes failure_reason and published_post_id when present', () {
      final model = ScheduledPostModel.fromMap({
        'id': 'sp3',
        'user_id': 'u3',
        'text_content': 'oops',
        'scheduled_at': '2026-08-01T09:00:00Z',
        'status': 'failed',
        'failure_reason': 'community no longer exists',
        'published_post_id': null,
      });

      expect(model.status, 'failed');
      expect(model.failureReason, 'community no longer exists');
      expect(model.publishedPostId, isNull);
    });
  });

  group('FeedCursor.fromLastPost', () {
    test('carries isPinned/createdAt/id straight from the post', () {
      final post = PostModel.fromMap({
        'id': 'p9',
        'author_id': 'u9',
        'text_content': 'pinned one',
        'created_at': '2026-01-02T03:04:05Z',
        'is_pinned': true,
      });

      final cursor = FeedCursor.fromLastPost(post);

      expect(cursor.id, 'p9');
      expect(cursor.isPinned, isTrue);
      expect(cursor.createdAt, post.createdAt);
    });
  });
}
