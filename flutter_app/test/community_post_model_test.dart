import 'package:flutter_test/flutter_test.dart';

import 'package:gather_app/shared/models/models.dart';

void main() {
  group('Community post model', () {
    test('preserves community context when parsing a post', () {
      final post = PostModel.fromMap({
        'id': 'post-1',
        'author_id': 'user-1',
        'community_id': 'community-1',
        'text_content': 'Hello community',
        'created_at': '2026-08-30T10:00:00Z',
        'visibility': 'public',
      });

      expect(post.communityId, 'community-1');
      expect(post.textContent, 'Hello community');
      expect(post.visibility, 'public');
    });

    test('keeps global posts distinguishable from community posts', () {
      final globalPost = PostModel.fromMap({
        'id': 'post-global',
        'author_id': 'user-1',
        'community_id': null,
        'text_content': 'Global post',
        'created_at': '2026-08-30T10:00:00Z',
      });

      final communityPost = PostModel.fromMap({
        'id': 'post-community',
        'author_id': 'user-1',
        'community_id': 'community-1',
        'text_content': 'Community post',
        'created_at': '2026-08-30T10:00:00Z',
      });

      expect(globalPost.communityId, isNull);
      expect(communityPost.communityId, 'community-1');
    });

    test('preserves community post media and pin state', () {
      final post = PostModel.fromMap({
        'id': 'post-2',
        'author_id': 'user-2',
        'community_id': 'community-2',
        'text_content': 'Pinned photo',
        'created_at': '2026-08-30T10:00:00Z',
        'is_pinned': true,
        'media_items': [
          {
            'media_url': 'https://example.com/photo.jpg',
            'media_type': 'image',
          },
        ],
      });

      expect(post.communityId, 'community-2');
      expect(post.isPinned, isTrue);
      expect(post.mediaItems, hasLength(1));
      expect(post.mediaItems.first.mediaType, 'image');
      expect(post.imageUrl, 'https://example.com/photo.jpg');
    });
  });
}
